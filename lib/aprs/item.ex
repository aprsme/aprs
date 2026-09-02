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
            alive: alive_flag(live_killed),
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

    case scan_coordinates(data) do
      {:ok, latitude, longitude} ->
        %{latitude: parsed_latitude, longitude: parsed_longitude} =
          Aprs.Position.parse_aprs_position(latitude, longitude)

        Map.merge(base, %{latitude: parsed_latitude, longitude: parsed_longitude})

      :error ->
        base
    end
  end

  # `!` is a live item, `_` a killed one.
  @spec alive_flag(String.t()) :: 0 | 1
  defp alive_flag("!"), do: 1
  defp alive_flag(_live_killed), do: 0

  # Greedy separator semantics choose the last longitude on the same line
  # after the first latitude that has any following longitude.
  @spec scan_coordinates(binary()) :: {:ok, binary(), binary()} | :error
  defp scan_coordinates(data), do: scan_latitude(data)

  @spec scan_latitude(binary()) :: {:ok, binary(), binary()} | :error
  defp scan_latitude(<<_byte, rest::binary>> = data) do
    case latitude_at(data) do
      {:ok, latitude, after_latitude} ->
        coordinates_after_latitude(latitude, last_longitude(after_latitude, nil), rest)

      :error ->
        scan_latitude(rest)
    end
  end

  defp scan_latitude(<<>>), do: :error

  @spec coordinates_after_latitude(binary(), binary() | nil, binary()) ::
          {:ok, binary(), binary()} | :error
  defp coordinates_after_latitude(latitude, longitude, _rest) when is_binary(longitude) do
    {:ok, latitude, longitude}
  end

  defp coordinates_after_latitude(_latitude, nil, rest), do: scan_latitude(rest)

  @spec latitude_at(binary()) :: {:ok, binary(), binary()} | :error
  defp latitude_at(<<d1, d2, d3, d4, d5, ?., fraction, rest::binary>> = data)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_digit(d4) and is_digit(d5) and is_digit(fraction) do
    finish_latitude(rest, data, 7)
  end

  defp latitude_at(<<d1, d2, d3, d4, ?., fraction, rest::binary>> = data)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_digit(d4) and is_digit(fraction) do
    finish_latitude(rest, data, 6)
  end

  defp latitude_at(_data), do: :error

  @spec finish_latitude(binary(), binary(), pos_integer()) :: {:ok, binary(), binary()} | :error
  defp finish_latitude(<<digit, rest::binary>>, data, length) when is_digit(digit) do
    finish_latitude(rest, data, length + 1)
  end

  defp finish_latitude(<<direction, rest::binary>>, data, length) when direction in [?N, ?S] do
    {:ok, binary_part(data, 0, length + 1), rest}
  end

  defp finish_latitude(_rest, _data, _length), do: :error

  @spec last_longitude(binary(), binary() | nil) :: binary() | nil
  defp last_longitude(<<?\n, _::binary>>, candidate), do: candidate

  defp last_longitude(<<_byte, rest::binary>> = data, candidate) do
    case longitude_at(data) do
      {:ok, longitude} -> last_longitude(rest, longitude)
      :error -> last_longitude(rest, candidate)
    end
  end

  defp last_longitude(<<>>, candidate), do: candidate

  @spec longitude_at(binary()) :: {:ok, binary()} | :error
  defp longitude_at(<<d1, d2, d3, d4, d5, d6, ?., fraction, rest::binary>> = data)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_digit(d4) and is_digit(d5) and is_digit(d6) and
              is_digit(fraction) do
    finish_longitude(rest, data, 8)
  end

  defp longitude_at(<<d1, d2, d3, d4, d5, ?., fraction, rest::binary>> = data)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_digit(d4) and is_digit(d5) and is_digit(fraction) do
    finish_longitude(rest, data, 7)
  end

  defp longitude_at(_data), do: :error

  @spec finish_longitude(binary(), binary(), pos_integer()) :: {:ok, binary()} | :error
  defp finish_longitude(<<digit, rest::binary>>, data, length) when is_digit(digit) do
    finish_longitude(rest, data, length + 1)
  end

  defp finish_longitude(<<direction, _rest::binary>>, data, length) when direction in [?E, ?W] do
    {:ok, binary_part(data, 0, length + 1)}
  end

  defp finish_longitude(_rest, _data, _length), do: :error

  @spec split_item(String.t()) :: {:ok, String.t(), String.t(), String.t()} | :error
  defp split_item(data), do: find_status(data, data, 0, nil)

  @spec find_status(
          String.t(),
          binary(),
          non_neg_integer(),
          {0..3, non_neg_integer(), byte()} | nil
        ) :: {:ok, String.t(), String.t(), String.t()} | :error
  defp find_status(data, <<?!, rest::binary>>, index, candidate) when index <= 9 do
    candidate = consider_status(data, index, ?!, candidate)
    find_status(data, rest, index + 1, candidate)
  end

  defp find_status(data, <<?_, rest::binary>>, index, candidate) when index <= 9 do
    candidate = consider_status(data, index, ?_, candidate)
    find_status(data, rest, index + 1, candidate)
  end

  defp find_status(data, <<_byte, rest::binary>>, index, candidate) when index <= 9 do
    find_status(data, rest, index + 1, candidate)
  end

  defp find_status(data, _remaining, _index, {_rank, status_index, status}) do
    item_name = binary_part(data, 0, status_index)
    position_start = status_index + 1
    position_data = binary_part(data, position_start, byte_size(data) - position_start)
    {:ok, item_name, <<status>>, position_data}
  end

  defp find_status(_data, _remaining, _index, nil), do: :error

  @spec consider_status(
          String.t(),
          non_neg_integer(),
          byte(),
          {0..3, non_neg_integer(), byte()} | nil
        ) :: {0..3, non_neg_integer(), byte()}
  defp consider_status(data, index, status, candidate) do
    rank = position_rank(data, index + 1)

    case candidate do
      {best_rank, _, _} when best_rank >= rank -> candidate
      _ -> {rank, index, status}
    end
  end

  # Item names may not contain `!` or `_`, but a compressed position can, so the
  # split is chosen by what actually follows the candidate status byte.
  @spec position_rank(String.t(), non_neg_integer()) :: 0..3
  defp position_rank(data, position_start) when position_start < byte_size(data) do
    position = binary_part(data, position_start, byte_size(data) - position_start)
    rank_position(uncompressed_position_prefix?(position), position)
  end

  defp position_rank(_data, _position_start), do: 0

  @spec rank_position(boolean(), binary()) :: 0..3
  defp rank_position(true, _position), do: 3
  defp rank_position(false, position), do: compressed_position_rank(compressed_position_prefix?(position))

  @spec compressed_position_rank(boolean()) :: 0..2
  defp compressed_position_rank(true), do: 2
  defp compressed_position_rank(false), do: 0

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
