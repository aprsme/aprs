defmodule Aprs.Item do
  @moduledoc """
  APRS item parsing.
  """

  import Aprs.Guards

  @doc """
  Parse an APRS item report, data type indicator included.

  The name runs to the `!` (live) or `_` (killed) status byte, and the rest is
  parsed as an uncompressed or compressed position followed by the shared
  comment pipeline. Returns `:item_name`/`:itemname`, `:live_killed`, `:alive`
  and the position fields; a report whose name cannot be delimited comes back
  as `:raw_data` alone.
  """
  @spec parse(String.t()) :: map()
  def parse(<<item_indicator, item_name_and_data::binary>>) when item_indicator in [?%, ?)] do
    case split_item(item_name_and_data) do
      {:ok, item_name, live_killed, position_data} ->
        item_name = String.trim(item_name)

        parsed_position =
          position_data
          |> parse_item_position()
          |> Aprs.PositionComment.parse()

        Map.merge(
          %{
            item_name: item_name,
            itemname: item_name,
            live_killed: live_killed,
            alive: if(live_killed == "!", do: 1, else: 0),
            data_type: :item
          },
          parsed_position
        )

      :error ->
        %{
          item_name: item_name_and_data,
          raw_data: <<item_indicator>> <> item_name_and_data,
          data_type: :item
        }
    end
  end

  def parse(data) do
    base = %{raw_data: data, data_type: :item}

    case Regex.run(~r/(\d{4,5}\.\d+[NS]).*([\/]?)(\d{5,6}\.\d+[EW])/, data) do
      [_, latitude, _, longitude] ->
        %{latitude: parsed_latitude, longitude: parsed_longitude} =
          Aprs.Position.parse_aprs_position(latitude, longitude)

        Map.merge(base, %{latitude: parsed_latitude, longitude: parsed_longitude})

      _ ->
        base
    end
  end

  @spec split_item(String.t()) :: {:ok, String.t(), String.t(), String.t()} | :error
  defp split_item(data), do: find_status(data, 0, nil)

  @spec find_status(
          String.t(),
          non_neg_integer(),
          {non_neg_integer(), non_neg_integer(), byte()} | nil
        ) :: {:ok, String.t(), String.t(), String.t()} | :error
  defp find_status(data, index, candidate) when index < byte_size(data) and index <= 9 do
    byte = :binary.at(data, index)

    candidate =
      if byte in [?!, ?_] do
        rank = position_rank(data, index + 1)

        case candidate do
          {best_rank, _, _} when best_rank >= rank -> candidate
          _ -> {rank, index, byte}
        end
      else
        candidate
      end

    find_status(data, index + 1, candidate)
  end

  defp find_status(data, _index, {_rank, status_index, status}) do
    item_name = binary_part(data, 0, status_index)
    position_start = status_index + 1
    position_data = binary_part(data, position_start, byte_size(data) - position_start)
    {:ok, item_name, <<status>>, position_data}
  end

  defp find_status(_data, _index, nil), do: :error

  # Item names may not contain `!` or `_`, but a compressed position can, so the
  # split is chosen by what actually follows the candidate status byte.
  @spec position_rank(String.t(), non_neg_integer()) :: 0..3
  defp position_rank(data, position_start) when position_start < byte_size(data) do
    position = binary_part(data, position_start, byte_size(data) - position_start)

    cond do
      uncompressed_position_prefix?(position) -> 3
      compressed_position_prefix?(position) -> 2
      true -> 0
    end
  end

  defp position_rank(_data, _position_start), do: 0

  @spec uncompressed_position_prefix?(String.t()) :: boolean()
  defp uncompressed_position_prefix?(<<latitude::binary-size(8), _table, longitude::binary-size(9), _::binary>>) do
    Aprs.Position.valid_latitude_format?(latitude) and Aprs.Position.valid_longitude_format?(longitude)
  end

  defp uncompressed_position_prefix?(_position), do: false

  @spec compressed_position_prefix?(String.t()) :: boolean()
  defp compressed_position_prefix?(<<table, coordinates::binary-size(8), code, cs1, cs2, type, _::binary>>)
       when is_compressed_table(table) and code >= 33 and code <= 126 and cs1 >= 32 and cs2 >= 32 and type >= 32 do
    base91_run?(coordinates)
  end

  defp compressed_position_prefix?(_position_data), do: false

  @spec base91_run?(binary()) :: boolean()
  defp base91_run?(<<>>), do: true
  defp base91_run?(<<byte, rest::binary>>) when is_base91(byte), do: base91_run?(rest)
  defp base91_run?(_data), do: false

  @spec parse_item_position(String.t()) :: map()
  defp parse_item_position(<<first_byte, _::binary>> = position_data) when first_byte >= ?0 and first_byte <= ?9 do
    parse_uncompressed_position(position_data)
  end

  defp parse_item_position(<<first_byte, _::binary>> = position_data)
       when byte_size(position_data) >= 13 and
              (first_byte in [?/, ?\\] or (first_byte >= ?A and first_byte <= ?Z) or
                 (first_byte >= ?a and first_byte <= ?j)) do
    position_data
    |> parse_compressed_position()
    |> ensure_valid_position(position_data)
  end

  defp parse_item_position(position_data) do
    %{comment: position_data, position_format: :unknown}
  end

  @spec ensure_valid_position(map(), String.t()) :: map()
  defp ensure_valid_position(%{latitude: latitude, longitude: longitude} = result, _position_data)
       when is_number(latitude) and is_number(longitude) do
    result
  end

  defp ensure_valid_position(_result, position_data) do
    %{comment: position_data, position_format: :unknown}
  end

  @spec parse_uncompressed_position(String.t()) :: map()
  defp parse_uncompressed_position(
         <<latitude::binary-size(8), symbol_table_id::binary-size(1), longitude::binary-size(9),
           symbol_code::binary-size(1), comment::binary>>
       ) do
    position = Aprs.Position.parse_aprs_position(latitude, longitude)
    ambiguity = Map.get(position, :ambiguity, 0)

    %{
      latitude: position.latitude,
      longitude: position.longitude,
      symbol_table_id: symbol_table_id,
      symbol_code: symbol_code,
      comment: comment,
      phg: nil,
      position_format: :uncompressed,
      format: :uncompressed,
      posambiguity: ambiguity,
      has_position: is_number(position.latitude) and is_number(position.longitude),
      posresolution: Aprs.UtilityHelpers.position_resolution(ambiguity)
    }
  end

  defp parse_uncompressed_position(position_data) do
    %{comment: position_data, position_format: :unknown}
  end

  @spec parse_compressed_position(String.t()) :: map()
  defp parse_compressed_position(
         <<symbol_table_id::binary-size(1), latitude_compressed::binary-size(4), longitude_compressed::binary-size(4),
           symbol_code::binary-size(1), cs::binary-size(2), compression_type::binary-size(1), comment::binary>>
       ) do
    latitude = decode_coordinate(latitude_compressed, &Aprs.CompressedPositionHelpers.convert_compressed_lat/1)
    longitude = decode_coordinate(longitude_compressed, &Aprs.CompressedPositionHelpers.convert_compressed_lon/1)

    base_data = %{
      latitude: latitude,
      longitude: longitude,
      symbol_table_id: symbol_table_id,
      symbol_code: symbol_code,
      comment: comment,
      position_format: :compressed,
      format: :compressed,
      compression_type: compression_type,
      posambiguity: 0,
      has_position: is_number(latitude) and is_number(longitude),
      posresolution: Aprs.UtilityHelpers.compressed_position_resolution()
    }

    Map.merge(
      base_data,
      Aprs.CompressedPositionHelpers.convert_compressed_cs(cs, compression_type)
    )
  end

  @spec decode_coordinate(String.t(), (String.t() -> {:ok, float()} | {:error, String.t()})) :: float() | nil
  defp decode_coordinate(value, converter) do
    case converter.(value) do
      {:ok, coordinate} -> coordinate
      {:error, _reason} -> nil
    end
  end
end
