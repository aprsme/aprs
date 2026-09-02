defmodule Aprs.Object do
  @moduledoc """
  APRS object parsing.
  """

  @typep object_value :: String.t() | integer() | float() | boolean() | atom() | map() | nil
  @typep object_map :: %{:data_type => :object, optional(atom()) => object_value()}

  @doc """
  Parse an APRS object report, with or without its `;` data type indicator.

  The name is a fixed nine bytes, followed by the `*` (live) or `_` (killed)
  status byte and a seven-byte timestamp. The remainder is parsed as an
  uncompressed or compressed position followed by the shared comment pipeline.
  Returns `:object_name`, `:live_killed`, `:alive`, `:timestamp` and the
  position fields; a report too short to split comes back as `:raw_data`
  alone.
  """
  @spec parse(String.t()) :: object_map()
  def parse(<<";", object_name::binary-size(9), live_killed::binary-size(1), timestamp::binary-size(7), rest::binary>>) do
    parse_object_data(object_name, live_killed, timestamp, rest)
  end

  def parse(<<object_name::binary-size(9), live_killed::binary-size(1), timestamp::binary-size(7), rest::binary>>) do
    parse_object_data(object_name, live_killed, timestamp, rest)
  end

  def parse(data), do: %{data_type: :object, raw_data: data}

  @spec parse_object_data(String.t(), String.t(), String.t(), String.t()) :: object_map()
  defp parse_object_data(object_name, live_killed, timestamp, rest) do
    position_data =
      rest
      |> parse_object_position()
      |> Aprs.PositionComment.parse()

    Map.merge(
      %{
        object_name: String.trim(object_name),
        live_killed: live_killed,
        alive: if(live_killed == "*", do: 1, else: 0),
        timestamp: Aprs.UtilityHelpers.parse_timestamp(timestamp),
        data_type: :object
      },
      position_data
    )
  end

  @spec parse_object_position(String.t()) :: map()
  defp parse_object_position(<<first_byte, _::binary>> = position_data) when first_byte >= ?0 and first_byte <= ?9 do
    parse_object_uncompressed_position(position_data)
  end

  defp parse_object_position(<<first_byte, _::binary>> = position_data)
       when byte_size(position_data) >= 13 and
              (first_byte in [?/, ?\\] or (first_byte >= ?A and first_byte <= ?Z) or
                 (first_byte >= ?a and first_byte <= ?j)) do
    parse_object_compressed_position(position_data)
  end

  defp parse_object_position(position_data) do
    %{comment: position_data, position_format: :unknown, format: :uncompressed}
  end

  @spec parse_object_compressed_position(String.t()) :: map()
  defp parse_object_compressed_position(
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

  @spec parse_object_uncompressed_position(String.t()) :: map()
  defp parse_object_uncompressed_position(
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

  defp parse_object_uncompressed_position(position_data) do
    %{comment: position_data, position_format: :unknown, format: :uncompressed}
  end
end
