defmodule Aprs.Item do
  @moduledoc """
  APRS item parsing.
  """

  @doc """
  Parse an APRS item string. Returns a struct or error.
  """
  @spec parse(String.t()) :: %{
          optional(:item_name) => String.t(),
          optional(:live_killed) => String.t(),
          optional(:data_type) => :item,
          optional(:raw_data) => String.t(),
          optional(:latitude) => float() | nil,
          optional(:longitude) => float() | nil,
          optional(:symbol_table_id) => String.t(),
          optional(:symbol_code) => String.t(),
          optional(:comment) => String.t(),
          optional(:phg) => String.t() | nil,
          optional(:position_format) => :uncompressed | :compressed | :unknown,
          optional(:format) => String.t(),
          optional(:posambiguity) => non_neg_integer(),
          optional(:compression_type) => String.t(),
          optional(:course) => non_neg_integer(),
          optional(:speed) => float(),
          optional(:range) => float()
        }
  def parse(<<item_indicator, item_name_and_data::binary>>) when item_indicator in [?%, ?)] do
    case Regex.run(~r/^(.{1,9})([!_])(.*)$/, item_name_and_data) do
      [_, item_name, status_char, position_data] ->
        parsed_position = parse_item_position(position_data)

        base_data = %{
          item_name: String.trim(item_name),
          live_killed: status_char,
          data_type: :item
        }

        Map.merge(base_data, parsed_position)

      _ ->
        %{
          item_name: item_name_and_data,
          raw_data: <<item_indicator>> <> item_name_and_data,
          data_type: :item
        }
    end
  end

  def parse(data) do
    # Try to extract position from raw_data if present
    base = %{raw_data: data, data_type: :item}

    case Regex.run(~r/(\d{4,5}\.\d+[NS]).*([\/]?)(\d{5,6}\.\d+[EW])/, data) do
      [_, lat_str, _, lon_str] ->
        %{latitude: lat, longitude: lon} = Aprs.Position.parse_aprs_position(lat_str, lon_str)
        Map.merge(base, %{latitude: lat, longitude: lon})

      _ ->
        base
    end
  end

  @spec extract_phg(String.t()) :: {String.t() | nil, String.t()}
  defp extract_phg(comment) do
    case Regex.run(~r"PHG(\d{4})", comment) do
      [full_match, phg_digits] ->
        cleaned = comment |> String.replace(full_match, "", global: false) |> String.trim()
        {phg_digits, cleaned}

      _ ->
        {nil, comment}
    end
  end

  @spec parse_item_position(String.t()) :: %{
          optional(:latitude) => float() | nil,
          optional(:longitude) => float() | nil,
          optional(:symbol_table_id) => String.t(),
          optional(:symbol_code) => String.t(),
          optional(:comment) => String.t(),
          optional(:phg) => String.t() | nil,
          optional(:position_format) => :uncompressed | :compressed | :unknown,
          optional(:format) => String.t(),
          optional(:posambiguity) => non_neg_integer(),
          optional(:compression_type) => String.t(),
          optional(:course) => non_neg_integer(),
          optional(:speed) => float(),
          optional(:range) => float()
        }
  # FAP distinguishes compressed vs uncompressed by the first character:
  # - digit → uncompressed position
  # - /\A-Za-j → compressed position
  defp parse_item_position(<<first_byte, _::binary>> = position_data) when first_byte >= ?0 and first_byte <= ?9 do
    parse_uncompressed_position(position_data)
  end

  defp parse_item_position(<<first_byte, _::binary>> = position_data)
       when byte_size(position_data) >= 13 and
              (first_byte in [?/, ?\\] or (first_byte >= ?A and first_byte <= ?Z) or
                 (first_byte >= ?a and first_byte <= ?j)) do
    position_data |> parse_compressed_position() |> ensure_valid_position(position_data)
  end

  defp parse_item_position(position_data) do
    %{comment: position_data, position_format: :unknown}
  end

  # Compressed parsing returns a result map with latitude/longitude set when
  # the base91 decoding succeeded; otherwise we fall back to :unknown.
  @spec ensure_valid_position(map(), String.t()) :: map()
  defp ensure_valid_position(%{latitude: lat, longitude: lon} = result, _data) when not is_nil(lat) and not is_nil(lon),
    do: result

  defp ensure_valid_position(_result, position_data), do: %{comment: position_data, position_format: :unknown}

  @spec parse_uncompressed_position(String.t()) :: %{
          optional(:latitude) => float() | nil,
          optional(:longitude) => float() | nil,
          optional(:symbol_table_id) => String.t(),
          optional(:symbol_code) => String.t(),
          optional(:comment) => String.t(),
          optional(:phg) => String.t() | nil,
          optional(:position_format) => :uncompressed | :unknown,
          optional(:format) => String.t(),
          optional(:posambiguity) => non_neg_integer()
        }
  defp parse_uncompressed_position(
         <<latitude::binary-size(8), sym_table_id::binary-size(1),
           longitude::binary-size(9), symbol_code::binary-size(1), comment::binary>>
       ) do
    pos = Aprs.Position.parse_aprs_position(latitude, longitude)
    ambiguity = Map.get(pos, :ambiguity, 0)
    {phg, cleaned_comment} = extract_phg(comment)

    %{
      latitude: pos.latitude,
      longitude: pos.longitude,
      symbol_table_id: sym_table_id,
      symbol_code: symbol_code,
      comment: cleaned_comment,
      phg: phg,
      position_format: :uncompressed,
      format: :uncompressed,
      posambiguity: ambiguity
    }
  end

  defp parse_uncompressed_position(position_data) do
    %{comment: position_data, position_format: :unknown}
  end

  @spec parse_compressed_position(String.t()) :: %{
          optional(:latitude) => float() | nil,
          optional(:longitude) => float() | nil,
          optional(:symbol_table_id) => String.t(),
          optional(:symbol_code) => String.t(),
          optional(:comment) => String.t(),
          optional(:position_format) => :compressed | :unknown,
          optional(:format) => String.t(),
          optional(:compression_type) => String.t(),
          optional(:posambiguity) => non_neg_integer(),
          optional(:course) => non_neg_integer(),
          optional(:speed) => float(),
          optional(:range) => float()
        }
  defp parse_compressed_position(
         <<sym_table::binary-size(1), latitude_compressed::binary-size(4), longitude_compressed::binary-size(4),
           symbol_code::binary-size(1), cs::binary-size(2), compression_type::binary-size(1), comment::binary>>
       ) do
    converted_lat =
      case Aprs.CompressedPositionHelpers.convert_compressed_lat(latitude_compressed) do
        {:ok, lat} -> lat
        {:error, _} -> nil
      end

    converted_lon =
      case Aprs.CompressedPositionHelpers.convert_compressed_lon(longitude_compressed) do
        {:ok, lon} -> lon
        {:error, _} -> nil
      end

    compressed_cs = Aprs.CompressedPositionHelpers.convert_compressed_cs(cs)

    base_data = %{
      latitude: converted_lat,
      longitude: converted_lon,
      symbol_table_id: sym_table,
      symbol_code: symbol_code,
      comment: comment,
      position_format: :compressed,
      format: :compressed,
      compression_type: compression_type,
      posambiguity: 0
    }

    Map.merge(base_data, compressed_cs)
  end
end
