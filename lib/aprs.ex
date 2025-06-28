defmodule Aprs do
  @moduledoc """
  Main APRS packet parsing library
  """
  alias Aprs.Item
  alias Aprs.MicE
  alias Aprs.Object
  alias Aprs.PHG
  alias Aprs.Status
  alias Aprs.Telemetry
  alias Aprs.Weather

  # Simple APRS position parsing to replace parse_aprs_position
  defp parse_aprs_position(lat, lon) do
    with [_, lat_deg, lat_min, lat_dir] <- Regex.run(~r/^(\d{2})(\d{2}\.\d+)([NS])$/, lat),
         [_, lon_deg, lon_min, lon_dir] <- Regex.run(~r/^(\d{3})(\d{2}\.\d+)([EW])$/, lon) do
      lat_val =
        Decimal.add(Decimal.new(lat_deg), Decimal.div(Decimal.new(lat_min), Decimal.new("60")))

      lon_val =
        Decimal.add(Decimal.new(lon_deg), Decimal.div(Decimal.new(lon_min), Decimal.new("60")))

      lat = if lat_dir == "S", do: Decimal.negate(lat_val), else: lat_val
      lon = if lon_dir == "W", do: Decimal.negate(lon_val), else: lon_val
      %{latitude: lat, longitude: lon}
    else
      _ -> %{latitude: nil, longitude: nil}
    end
  end

  @type packet :: %{
          id: String.t(),
          sender: String.t(),
          path: String.t(),
          destination: String.t(),
          information_field: String.t(),
          data_type: atom(),
          base_callsign: String.t(),
          ssid: String.t(),
          data_extended: map() | nil,
          received_at: DateTime.t()
        }

  @type parse_result :: {:ok, packet()} | {:error, atom() | String.t()}

  @type position_ambiguity :: 0..4

  @spec parse(String.t()) :: parse_result()
  def parse(message) when is_binary(message) do
    # Ensure the message is valid UTF-8 before parsing
    if String.valid?(message) do
      do_parse(message)
    else
      # Try to fix invalid UTF-8 by replacing invalid bytes
      try do
        fixed_message = String.replace(message, ~r/[^\x00-\x7F]/, "?")
        do_parse(fixed_message)
      rescue
        _ ->
          {:error, :invalid_utf8}
      end
    end
  rescue
    _ ->
      {:error, :invalid_packet}
  end

  def parse(_), do: {:error, :invalid_packet}

  @spec do_parse(String.t()) :: parse_result()
  defp do_parse(message) do
    case split_packet(message) do
      {:ok, [sender, path, data]} ->
        case parse_callsign(sender) do
          {:ok, callsign_parts} ->
            case parse_datatype_safe(data) do
              {:ok, data_type} ->
                case split_path(path) do
                  {:ok, [destination, path2]} ->
                    try do
                      # Use binary pattern matching for trimming instead of String.trim
                      data_trimmed = trim_binary(data)
                      # Use binary pattern matching instead of String.slice for Unicode safety
                      data_without_type =
                        case data_trimmed do
                          <<_first_char::binary-size(1), rest::binary>> -> rest
                          _ -> ""
                        end

                      data_extended =
                        try do
                          parse_data(data_type, destination, data_without_type)
                        rescue
                          _e ->
                            nil
                        end

                      base_callsign = List.first(callsign_parts)

                      ssid =
                        case List.last(callsign_parts) do
                          nil -> nil
                          s when is_binary(s) -> s
                          i when is_integer(i) -> to_string(i)
                          _ -> nil
                        end

                      {:ok,
                       %{
                         id: 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower),
                         sender: sender,
                         path: path2,
                         destination: destination,
                         information_field: data_trimmed,
                         data_type: data_type,
                         base_callsign: base_callsign,
                         ssid: ssid,
                         data_extended: data_extended,
                         received_at: DateTime.truncate(DateTime.utc_now(), :microsecond)
                       }}
                    rescue
                      _e ->
                        {:error, :invalid_packet}
                    end

                  _err ->
                    {:error, :invalid_packet}
                end

              _err ->
                {:error, :invalid_packet}
            end

          _err ->
            {:error, :invalid_packet}
        end

      _err ->
        {:error, :invalid_packet}
    end
  rescue
    _e ->
      {:error, :invalid_packet}
  end

  # Safely split packet into components using binary pattern matching
  @spec split_packet(String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def split_packet(message) do
    case find_delimiter(message, ?>) do
      {:ok, sender, rest} ->
        case find_delimiter(rest, ?:) do
          {:ok, path, data} ->
            {:ok, [sender, path, data]}

          :error ->
            {:error, "Invalid packet format"}
        end

      :error ->
        {:error, "Invalid packet format"}
    end
  end

  # Helper function to find delimiter using binary pattern matching
  defp find_delimiter(binary, delimiter) do
    find_delimiter(binary, delimiter, 0, binary)
  end

  defp find_delimiter(<<delimiter, rest::binary>>, delimiter, pos, original) do
    {:ok, binary_part(original, 0, pos), rest}
  end

  defp find_delimiter(<<_byte, rest::binary>>, delimiter, pos, original) do
    find_delimiter(rest, delimiter, pos + 1, original)
  end

  defp find_delimiter(<<>>, _delimiter, _pos, _original) do
    :error
  end

  # Binary-safe trim function that handles Unicode characters
  defp trim_binary(binary) do
    binary
    |> trim_leading_whitespace()
    |> trim_trailing_whitespace()
  end

  defp trim_leading_whitespace(<<?\s, rest::binary>>), do: trim_leading_whitespace(rest)
  defp trim_leading_whitespace(<<?\t, rest::binary>>), do: trim_leading_whitespace(rest)
  defp trim_leading_whitespace(<<?\r, rest::binary>>), do: trim_leading_whitespace(rest)
  defp trim_leading_whitespace(<<?\n, rest::binary>>), do: trim_leading_whitespace(rest)
  defp trim_leading_whitespace(binary), do: binary

  defp trim_trailing_whitespace(binary) do
    trim_trailing_whitespace(binary, byte_size(binary))
  end

  defp trim_trailing_whitespace(binary, 0), do: binary

  defp trim_trailing_whitespace(binary, pos) do
    case binary_part(binary, pos - 1, 1) do
      <<?\s>> -> trim_trailing_whitespace(binary, pos - 1)
      <<?\t>> -> trim_trailing_whitespace(binary, pos - 1)
      <<?\r>> -> trim_trailing_whitespace(binary, pos - 1)
      <<?\n>> -> trim_trailing_whitespace(binary, pos - 1)
      _ -> binary_part(binary, 0, pos)
    end
  end

  # Safely split path into destination and digipeater path
  @spec split_path(String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def split_path(path) when is_binary(path) do
    split = String.split(path, ",", parts: 2)
    split_path_parts(split)
  end

  defp split_path_parts([destination, digi_path]), do: {:ok, [destination, digi_path]}
  defp split_path_parts([destination]), do: {:ok, [destination, ""]}
  defp split_path_parts(_), do: {:error, "Invalid path format"}

  # Safe version of parse_datatype that returns {:ok, type} or {:error, reason}
  @spec parse_datatype_safe(String.t()) :: {:ok, atom()} | {:error, String.t()}
  def parse_datatype_safe(""), do: {:error, "Empty data"}
  def parse_datatype_safe(data), do: {:ok, parse_datatype(data)}

  @spec parse_callsign(String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def parse_callsign(callsign) do
    case Aprs.AX25.parse_callsign(callsign) do
      {:ok, {base, ssid}} -> {:ok, [base, ssid]}
      {:error, reason} -> {:error, reason}
    end
  end

  # One of the nutty exceptions in the APRS protocol has to do with this
  # data type indicator. It's usually the first character of the message.
  # However, in some rare cases, the ! indicator can be anywhere in the
  # first 40 characters of the message. I'm not going to deal with that
  # weird case right now. It seems like its for a specific type of old
  # TNC hardware that probably doesn't even exist anymore.
  @spec parse_datatype(String.t()) :: atom()
  def parse_datatype(<<":", _::binary>>), do: :message
  def parse_datatype(<<">", _::binary>>), do: :status
  def parse_datatype("!" <> _), do: :position
  def parse_datatype("/" <> _), do: :timestamped_position
  def parse_datatype("=" <> _), do: :position_with_message
  def parse_datatype("@" <> _), do: :timestamped_position_with_message
  def parse_datatype(";" <> _), do: :object
  def parse_datatype("`" <> _), do: :mic_e_old
  def parse_datatype("'" <> _), do: :mic_e_old
  def parse_datatype("_" <> _), do: :weather
  def parse_datatype("T" <> _), do: :telemetry
  def parse_datatype("$" <> _), do: :raw_gps_ultimeter
  def parse_datatype("<" <> _), do: :station_capabilities
  def parse_datatype("?" <> _), do: :query
  def parse_datatype("{" <> _), do: :user_defined
  def parse_datatype("}" <> _), do: :third_party_traffic
  def parse_datatype("%" <> _), do: :item
  def parse_datatype(")" <> _), do: :item
  def parse_datatype("*" <> _), do: :peet_logging
  def parse_datatype("," <> _), do: :invalid_test_data
  def parse_datatype("#DFS" <> _), do: :df_report
  def parse_datatype("#PHG" <> _), do: :phg_data
  def parse_datatype("#" <> _), do: :phg_data
  def parse_datatype(_), do: :unknown_datatype

  @spec parse_data(atom(), String.t(), String.t()) :: map() | nil
  def parse_data(:mic_e, destination, data), do: MicE.parse(data, destination)
  def parse_data(:mic_e_old, destination, data), do: MicE.parse(data, destination)
  def parse_data(:object, _destination, data), do: Object.parse(data)
  def parse_data(:item, _destination, data), do: Item.parse(data)
  def parse_data(:weather, _destination, data), do: Weather.parse(data)
  def parse_data(:telemetry, _destination, data), do: Telemetry.parse(data)
  def parse_data(:status, _destination, data), do: Status.parse(data)
  def parse_data(:phg_data, _destination, data), do: PHG.parse(data)
  def parse_data(:peet_logging, _destination, data), do: Aprs.SpecialDataHelpers.parse_peet_logging(data)
  def parse_data(:invalid_test_data, _destination, data), do: Aprs.SpecialDataHelpers.parse_invalid_test_data(data)

  def parse_data(:raw_gps_ultimeter, _destination, data) do
    case Aprs.NMEAHelpers.parse_nmea_sentence(data) do
      {:error, error} ->
        %{
          data_type: :raw_gps_ultimeter,
          error: error,
          nmea_type: nil,
          raw_data: data,
          latitude: nil,
          longitude: nil
        }
    end
  end

  def parse_data(:df_report, _destination, data) do
    if String.starts_with?(data, "DFS") and byte_size(data) >= 7 do
      <<"DFS", s, h, g, d, rest::binary>> = data

      %{
        df_strength: Aprs.PHGHelpers.parse_df_strength(s),
        height: Aprs.PHGHelpers.parse_phg_height(h),
        gain: Aprs.PHGHelpers.parse_phg_gain(g),
        directivity: Aprs.PHGHelpers.parse_phg_directivity(d),
        comment: rest,
        data_type: :df_report
      }
    else
      %{
        df_data: data,
        data_type: :df_report
      }
    end
  end

  def parse_data(:user_defined, _destination, data), do: parse_user_defined(data)
  def parse_data(:third_party_traffic, _destination, data), do: parse_third_party_traffic(data)

  def parse_data(:message, _destination, data) do
    case Regex.run(~r/^:([^:]+):(.+?)(\{(\d+)\})?$/s, data) do
      [_, addressee, message_text, _full_ack, message_number] ->
        %{
          data_type: :message,
          addressee: String.trim(addressee),
          message_text: String.trim(message_text),
          message_number: message_number
        }

      [_, addressee, message_text] ->
        %{
          data_type: :message,
          addressee: String.trim(addressee),
          message_text: String.trim(message_text)
        }

      _ ->
        nil
    end
  end

  def parse_data(:position, destination, <<"!", rest::binary>>) do
    parse_data(:position, destination, rest)
  end

  def parse_data(:position, _destination, <<"/", _::binary>> = data) do
    result = parse_position_without_timestamp(data)
    if result.data_type == :malformed_position, do: result, else: %{result | data_type: :position}
  end

  def parse_data(:position, _destination, data) do
    result = parse_position_without_timestamp(data)
    if result.data_type == :malformed_position, do: result, else: %{result | data_type: :position}
  end

  def parse_data(:position_with_message, _destination, data) do
    result = parse_position_with_message_without_timestamp(data)
    %{result | data_type: :position}
  end

  def parse_data(:timestamped_position, _destination, data) do
    parse_position_with_timestamp(false, data, :timestamped_position)
  end

  def parse_data(:timestamped_position_with_message, _destination, data) do
    case data do
      <<time::binary-size(7), latitude::binary-size(8), sym_table_id::binary-size(1), longitude::binary-size(9),
        symbol_code::binary-size(1), rest::binary>> ->
        weather_start = String.starts_with?(rest, "_")

        if weather_start do
          result =
            Aprs.parse_position_with_datetime_and_weather(
              true,
              time,
              latitude,
              sym_table_id,
              longitude,
              symbol_code,
              rest
            )

          add_has_location(result)
        else
          result = parse_position_with_timestamp(true, data, :timestamped_position_with_message)
          add_has_location(result)
        end

      _ ->
        result = parse_position_with_timestamp(true, data, :timestamped_position_with_message)
        add_has_location(result)
    end
  end

  def parse_data(:station_capabilities, _destination, data), do: parse_station_capabilities(data)
  def parse_data(:query, _destination, data), do: parse_query(data)

  # Catch-all for unknown or unsupported types
  def parse_data(_type, _destination, _data), do: nil

  defp add_has_location(result) do
    Map.put(
      result,
      :has_location,
      (is_number(result[:latitude]) or is_struct(result[:latitude], Decimal)) and
        (is_number(result[:longitude]) or is_struct(result[:longitude], Decimal))
    )
  end

  @spec parse_position_with_datetime_and_weather(
          boolean(),
          binary(),
          binary(),
          binary(),
          binary(),
          binary(),
          binary()
        ) :: map()
  def parse_position_with_datetime_and_weather(
        aprs_messaging?,
        time,
        latitude,
        sym_table_id,
        longitude,
        symbol_code,
        weather_report
      ) do
    pos = parse_aprs_position(latitude, longitude)
    weather_data = Aprs.Weather.parse_weather_data(weather_report)

    %{
      latitude: pos.latitude,
      longitude: pos.longitude,
      timestamp: time,
      symbol_table_id: sym_table_id,
      symbol_code: symbol_code,
      weather: weather_data,
      data_type: :position_with_datetime_and_weather,
      aprs_messaging?: aprs_messaging?
    }
  end

  @spec decode_compressed_position(binary()) :: map()
  def decode_compressed_position(
        <<"/", latitude::binary-size(4), longitude::binary-size(4), symbol_code::binary-size(1), _cs::binary-size(2),
          _compression_type::binary-size(2), _rest::binary>>
      ) do
    lat = convert_to_base91(latitude)
    lon = convert_to_base91(longitude)

    %{
      latitude: lat,
      longitude: lon,
      symbol_code: symbol_code
    }
  end

  @spec convert_to_base91(binary()) :: integer()
  def convert_to_base91(<<value::binary-size(4)>>) do
    [v1, v2, v3, v4] = to_charlist(value)
    (v1 - 33) * 91 * 91 * 91 + (v2 - 33) * 91 * 91 + (v3 - 33) * 91 + v4
  end

  # Helper to extract course and speed from comment field (e.g., "/123/045" or "123/045")
  @spec extract_course_and_speed(String.t()) :: {integer() | nil, float() | nil}
  defp extract_course_and_speed(comment) do
    # Match "/123/045" or "123/045" at the start of the comment
    case Regex.run(~r"/?(\d{3})/(\d{3})", comment) do
      [_, course, speed] -> {String.to_integer(course), String.to_integer(speed) * 1.0}
      _ -> {nil, nil}
    end
  end

  # Patch parse_position_without_timestamp to include course/speed
  @spec parse_position_without_timestamp(String.t()) :: map()
  def parse_position_without_timestamp(position_data) do
    case position_data do
      # Uncompressed position with validation
      <<latitude::binary-size(8), sym_table_id::binary-size(1), longitude::binary-size(9), symbol_code::binary-size(1),
        comment::binary>> ->
        if is_valid_aprs_coordinate?(latitude, longitude) do
          parse_position_uncompressed(latitude, sym_table_id, longitude, symbol_code, comment)
        else
          # Try compressed position without "/" prefix as fallback
          try_parse_compressed_without_prefix(position_data)
        end

      <<latitude::binary-size(8), sym_table_id::binary-size(1), longitude::binary-size(9)>> ->
        if is_valid_aprs_coordinate?(latitude, longitude) do
          parse_position_short_uncompressed(latitude, sym_table_id, longitude)
        else
          # Try compressed position without "/" prefix as fallback
          try_parse_compressed_without_prefix(position_data)
        end

      <<"/", latitude_compressed::binary-size(4), longitude_compressed::binary-size(4), symbol_code::binary-size(1),
        cs::binary-size(2), compression_type::binary-size(1), comment::binary>> ->
        parse_position_compressed(
          latitude_compressed,
          longitude_compressed,
          symbol_code,
          cs,
          compression_type,
          comment
        )

      # Fallback: try to parse as compressed position without "/" prefix
      <<latitude_compressed::binary-size(4), longitude_compressed::binary-size(4), symbol_code::binary-size(1),
        cs::binary-size(2), compression_type::binary-size(1), comment::binary>>
      when byte_size(position_data) >= 13 ->
        parse_position_compressed_missing_prefix(
          latitude_compressed,
          longitude_compressed,
          symbol_code,
          cs,
          compression_type,
          comment
        )

      _ ->
        parse_position_malformed(position_data)
    end
  end

  # Helper function to validate APRS coordinates
  defp is_valid_aprs_coordinate?(lat, lon) do
    lat_valid = Regex.match?(~r/^\d{4,5}\.\d+[NS]$/, lat)
    lon_valid = Regex.match?(~r/^\d{5,6}\.\d+[EW]$/, lon)
    lat_valid and lon_valid
  end

  # Helper function to try parsing as compressed position without "/" prefix
  defp try_parse_compressed_without_prefix(position_data) do
    case position_data do
      <<latitude_compressed::binary-size(4), longitude_compressed::binary-size(4), symbol_code::binary-size(1),
        cs::binary-size(2), compression_type::binary-size(1), comment::binary>>
      when byte_size(position_data) >= 13 ->
        parse_position_compressed_missing_prefix(
          latitude_compressed,
          longitude_compressed,
          symbol_code,
          cs,
          compression_type,
          comment
        )

      _ ->
        parse_position_malformed(position_data)
    end
  end

  defp parse_position_uncompressed(latitude, sym_table_id, longitude, symbol_code, comment) do
    %{latitude: lat, longitude: lon} = parse_aprs_position(latitude, longitude)
    ambiguity = Aprs.UtilityHelpers.calculate_position_ambiguity(latitude, longitude)
    dao_data = parse_dao_extension(comment)
    {course, speed} = extract_course_and_speed(comment)

    has_position = valid_coordinate?(lat) and valid_coordinate?(lon)

    base_map = %{
      latitude: lat,
      longitude: lon,
      timestamp: nil,
      symbol_table_id: sym_table_id,
      symbol_code: symbol_code,
      comment: comment,
      data_type: :position,
      aprs_messaging?: false,
      compressed?: false,
      position_ambiguity: ambiguity,
      dao: dao_data,
      course: course,
      speed: speed,
      has_position: has_position
    }

    if sym_table_id == "/" and symbol_code == "_" do
      weather_map = Aprs.Weather.parse_weather_data(comment)
      merged = Map.merge(weather_map, base_map)
      Map.put(merged, :timestamp, base_map[:timestamp])
    else
      base_map
    end
  end

  defp parse_position_short_uncompressed(latitude, sym_table_id, longitude) do
    %{latitude: lat, longitude: lon} = parse_aprs_position(latitude, longitude)
    ambiguity = Aprs.UtilityHelpers.calculate_position_ambiguity(latitude, longitude)

    has_position = valid_coordinate?(lat) and valid_coordinate?(lon)

    %{
      latitude: lat,
      longitude: lon,
      timestamp: nil,
      symbol_table_id: sym_table_id,
      symbol_code: "_",
      data_type: :position,
      aprs_messaging?: false,
      compressed?: false,
      position_ambiguity: ambiguity,
      dao: nil,
      course: nil,
      speed: nil,
      has_position: has_position
    }
  end

  defp parse_position_compressed(latitude_compressed, longitude_compressed, symbol_code, cs, compression_type, comment) do
    case {Aprs.CompressedPositionHelpers.convert_compressed_lat(latitude_compressed),
          Aprs.CompressedPositionHelpers.convert_compressed_lon(longitude_compressed)} do
      {{:ok, converted_lat}, {:ok, converted_lon}} ->
        compressed_cs = Aprs.CompressedPositionHelpers.convert_compressed_cs(cs)
        ambiguity = Aprs.CompressedPositionHelpers.calculate_compressed_ambiguity(compression_type)

        has_position = valid_coordinate?(converted_lat) and valid_coordinate?(converted_lon)

        base_data = %{
          latitude: converted_lat,
          longitude: converted_lon,
          symbol_table_id: "/",
          symbol_code: symbol_code,
          comment: comment,
          position_format: :compressed,
          compression_type: compression_type,
          data_type: :position,
          compressed?: true,
          position_ambiguity: ambiguity,
          dao: nil,
          has_position: has_position
        }

        Map.merge(base_data, compressed_cs)

      _ ->
        %{
          latitude: nil,
          longitude: nil,
          symbol_table_id: "/",
          symbol_code: symbol_code,
          comment: comment,
          position_format: :compressed,
          compression_type: compression_type,
          data_type: :position,
          compressed?: true,
          position_ambiguity: Aprs.CompressedPositionHelpers.calculate_compressed_ambiguity(compression_type),
          dao: nil,
          course: nil,
          speed: nil,
          has_position: false
        }
    end
  end

  defp parse_position_compressed_missing_prefix(
         latitude_compressed,
         longitude_compressed,
         symbol_code,
         cs,
         compression_type,
         comment
       ) do
    case {Aprs.CompressedPositionHelpers.convert_compressed_lat(latitude_compressed),
          Aprs.CompressedPositionHelpers.convert_compressed_lon(longitude_compressed)} do
      {{:ok, converted_lat}, {:ok, converted_lon}} ->
        compressed_cs = Aprs.CompressedPositionHelpers.convert_compressed_cs(cs)
        ambiguity = Aprs.CompressedPositionHelpers.calculate_compressed_ambiguity(compression_type)

        has_position = valid_coordinate?(converted_lat) and valid_coordinate?(converted_lon)

        base_data = %{
          latitude: converted_lat,
          longitude: converted_lon,
          symbol_table_id: "/",
          symbol_code: symbol_code,
          comment: comment,
          position_format: :compressed,
          compression_type: compression_type,
          data_type: :position,
          compressed?: true,
          position_ambiguity: ambiguity,
          dao: nil,
          has_position: has_position
        }

        Map.merge(base_data, compressed_cs)

      _ ->
        %{
          latitude: nil,
          longitude: nil,
          symbol_table_id: "/",
          symbol_code: symbol_code,
          comment: comment,
          position_format: :compressed,
          compression_type: compression_type,
          data_type: :position,
          compressed?: true,
          position_ambiguity: Aprs.CompressedPositionHelpers.calculate_compressed_ambiguity(compression_type),
          dao: nil,
          course: nil,
          speed: nil,
          has_position: false
        }
    end
  end

  defp parse_position_malformed(position_data) do
    %{
      latitude: nil,
      longitude: nil,
      timestamp: nil,
      symbol_table_id: nil,
      symbol_code: nil,
      data_type: :malformed_position,
      aprs_messaging?: false,
      compressed?: false,
      comment: String.trim(position_data),
      dao: nil,
      course: nil,
      speed: nil,
      has_position: false
    }
  end

  # Patch parse_position_with_message_without_timestamp to propagate course/speed
  @spec parse_position_with_message_without_timestamp(String.t()) :: map()
  def parse_position_with_message_without_timestamp(position_data) do
    result = parse_position_without_timestamp(position_data)
    Map.put(result, :aprs_messaging?, true)
  end

  # Patch parse_position_with_timestamp to extract course/speed from comment
  @spec parse_position_with_timestamp(boolean(), binary(), atom()) :: map()
  def parse_position_with_timestamp(
        aprs_messaging?,
        <<time::binary-size(7), latitude::binary-size(8), sym_table_id::binary-size(1), longitude::binary-size(9),
          symbol_code::binary-size(1), comment::binary>>,
        _data_type
      ) do
    case Aprs.UtilityHelpers.validate_position_data(latitude, longitude) do
      {:ok, {lat, lon}} ->
        build_position_result(aprs_messaging?, lat, lon, time, sym_table_id, symbol_code, comment)

      _ ->
        handle_invalid_position_data(aprs_messaging?, time, latitude, sym_table_id, longitude, symbol_code, comment)
    end
  end

  def parse_position_with_timestamp(_aprs_messaging?, _data, _data_type) do
    %{
      data_type: :timestamped_position_error,
      error: "Invalid timestamped position format"
    }
  end

  defp handle_invalid_position_data(aprs_messaging?, time, latitude, sym_table_id, longitude, symbol_code, comment) do
    # Fallback: try to extract lat/lon using regex if binary pattern match fails
    regex =
      ~r/^(?<time>\w{7})(?<lat>\d{4,5}\.\d+[NS])(?<sym_table>.)(?<lon>\d{5,6}\.\d+[EW])(?<sym_code>.)(?<comment>.*)$/

    raw_data = time <> latitude <> sym_table_id <> longitude <> symbol_code <> comment

    case Regex.named_captures(regex, raw_data) do
      %{
        "lat" => lat,
        "lon" => lon,
        "time" => time,
        "sym_table" => sym_table,
        "sym_code" => sym_code,
        "comment" => comment
      } ->
        build_fallback_position_result(aprs_messaging?, lat, lon, time, sym_table, sym_code, comment)

      _ ->
        %{
          data_type: :timestamped_position_error,
          error: "Invalid timestamped position format",
          raw_data: raw_data
        }
    end
  end

  defp build_fallback_position_result(aprs_messaging?, lat, lon, time, sym_table, sym_code, comment) do
    pos = parse_aprs_position(lat, lon)

    base_map = %{
      latitude: pos.latitude,
      longitude: pos.longitude,
      time: time,
      timestamp: time,
      symbol_table_id: sym_table,
      symbol_code: sym_code,
      comment: comment,
      data_type: :position,
      aprs_messaging?: aprs_messaging?,
      compressed?: false
    }

    if sym_table == "/" and sym_code == "_" do
      weather_map = Aprs.Weather.parse_weather_data(comment)
      merged = Map.merge(weather_map, base_map)
      Map.put(merged, :timestamp, base_map[:timestamp])
    else
      base_map
    end
  end

  defp build_position_result(aprs_messaging?, lat, lon, time, sym_table_id, symbol_code, comment) do
    position =
      if is_binary(lat) and is_binary(lon) do
        parse_aprs_position(lat, lon)
      else
        %{latitude: lat, longitude: lon}
      end

    {course, speed} = extract_course_and_speed(comment)

    base_map = %{
      latitude: position.latitude,
      longitude: position.longitude,
      position: position,
      time: Aprs.UtilityHelpers.validate_timestamp(time),
      timestamp: time,
      symbol_table_id: sym_table_id,
      symbol_code: symbol_code,
      comment: comment,
      data_type: :position,
      aprs_messaging?: aprs_messaging?,
      compressed?: false,
      course: course,
      speed: speed
    }

    if sym_table_id == "/" and symbol_code == "_" do
      weather_map = Aprs.Weather.parse_weather_data(comment)
      merged = Map.merge(weather_map, base_map)
      Map.put(merged, :timestamp, base_map[:timestamp])
    else
      base_map
    end
  end

  # Status Report parsing
  def parse_status(<<">", status_text::binary>>) do
    %{
      status_text: status_text,
      data_type: :status
    }
  end

  @spec parse_status(String.t()) :: map()
  def parse_status(data) do
    %{
      status_text: data,
      data_type: :status
    }
  end

  # Station Capabilities parsing
  def parse_station_capabilities(<<"<", capabilities::binary>>) do
    %{
      capabilities: capabilities,
      data_type: :station_capabilities
    }
  end

  @spec parse_station_capabilities(String.t()) :: map()
  def parse_station_capabilities(data) do
    %{
      capabilities: data,
      data_type: :station_capabilities
    }
  end

  # Query parsing
  def parse_query(<<"?", query_type::binary-size(1), query_data::binary>>) do
    %{
      query_type: query_type,
      query_data: query_data,
      data_type: :query
    }
  end

  @spec parse_query(String.t()) :: map()
  def parse_query(data) do
    %{
      query_data: data,
      data_type: :query
    }
  end

  # User Defined parsing
  def parse_user_defined(<<"{", user_id::binary-size(1), user_data::binary>>) do
    parsed_data = parse_user_defined_format(user_id, user_data)

    Map.merge(
      %{
        user_id: user_id,
        data_type: :user_defined,
        raw_data: user_data
      },
      parsed_data
    )
  end

  @spec parse_user_defined(String.t()) :: map()
  def parse_user_defined(data) do
    %{
      user_data: data,
      data_type: :user_defined
    }
  end

  # Parse specific user-defined formats
  defp parse_user_defined_format("A", user_data), do: %{format: :experimental_a, content: user_data}
  defp parse_user_defined_format("B", user_data), do: %{format: :experimental_b, content: user_data}
  defp parse_user_defined_format("C", user_data), do: %{format: :custom_c, content: user_data}
  defp parse_user_defined_format(_, user_data), do: %{format: :unknown, content: user_data}

  # Third Party Traffic parsing
  def parse_third_party_traffic(packet) do
    if Aprs.UtilityHelpers.count_leading_braces(packet) + 1 > 3 do
      %{
        error: "Maximum tunnel depth exceeded"
      }
    else
      case parse_tunneled_packet(packet) do
        {:ok, parsed_packet} ->
          build_third_party_traffic_result(packet, parsed_packet)

        {:error, reason} ->
          %{
            error: reason
          }
      end
    end
  end

  defp build_third_party_traffic_result(packet, parsed_packet) do
    case parse_nested_tunnel(packet) do
      {:ok, nested_packet} ->
        %{
          third_party_packet: nested_packet,
          data_type: :third_party_traffic,
          raw_data: packet
        }

      {:error, _} ->
        %{
          third_party_packet: parsed_packet,
          data_type: :third_party_traffic,
          raw_data: packet
        }
    end
  end

  @spec parse_tunneled_packet(String.t()) :: {:ok, map()} | {:error, String.t()}
  defp parse_tunneled_packet(packet) do
    case String.split(packet, ":", parts: 2) do
      [header, information] ->
        parse_tunneled_packet_with_header(header, information)

      _ ->
        {:error, "Invalid tunneled packet format"}
    end
  end

  defp parse_tunneled_packet_with_header(header, information) do
    case parse_tunneled_header(header) do
      {:ok, header_data} ->
        parse_tunneled_packet_with_information(header_data, information)

      {:error, reason} ->
        {:error, "Invalid header: #{reason}"}
    end
  end

  defp parse_tunneled_packet_with_information(header_data, information) do
    case parse_datatype_safe(information) do
      {:ok, data_type} ->
        data_without_type = String.slice(information, 1..-1//1)
        data_extended = parse_data(data_type, header_data.destination, data_without_type)

        {:ok,
         Map.merge(header_data, %{
           information_field: information,
           data_type: data_type,
           data_extended: data_extended
         })}

      {:error, reason} ->
        {:error, "Invalid data type: #{reason}"}
    end
  end

  @spec parse_tunneled_header(String.t()) :: {:ok, map()} | {:error, String.t()}
  defp parse_tunneled_header(header) do
    case String.split(header, ">", parts: 2) do
      [sender, path] ->
        parse_sender_and_path(sender, path)

      _ ->
        {:error, "Invalid header format"}
    end
  end

  defp parse_sender_and_path(sender, path) do
    case parse_callsign(sender) do
      {:ok, callsign_parts} ->
        base_callsign = List.first(callsign_parts)
        ssid = extract_ssid(List.last(callsign_parts))

        case split_path_for_tunnel(path) do
          {:ok, [destination, digi_path]} ->
            {:ok,
             %{
               sender: sender,
               base_callsign: base_callsign,
               ssid: ssid,
               destination: destination,
               digi_path: digi_path
             }}

          {:error, reason} ->
            {:error, "Invalid path: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Invalid callsign: #{reason}"}
    end
  end

  defp extract_ssid(nil), do: nil
  defp extract_ssid(s) when is_binary(s), do: s
  defp extract_ssid(i) when is_integer(i), do: to_string(i)
  defp extract_ssid(_), do: nil

  defp split_path_for_tunnel(path) do
    split_path(path)
  end

  # Add network tunneling support
  @spec parse_network_tunnel(String.t()) :: {:ok, map()} | {:error, String.t()}
  defp parse_network_tunnel(packet) do
    # Network tunneling packets start with "}" and contain a complete APRS packet
    case String.slice(packet, 1..-1//1) do
      tunneled_packet ->
        case parse_tunneled_packet(tunneled_packet) do
          {:ok, parsed_packet} ->
            {:ok,
             Map.merge(parsed_packet, %{
               tunnel_type: :network,
               raw_data: packet
             })}

          {:error, reason} ->
            {:error, "Invalid tunneled packet: #{reason}"}
        end
    end
  end

  # Add support for multiple levels of tunneling
  defp parse_nested_tunnel(packet, depth \\ 0) do
    cond do
      depth > 3 ->
        {:error, "Maximum tunnel depth exceeded"}

      String.starts_with?(packet, "}") ->
        case parse_network_tunnel(packet) do
          {:ok, parsed_packet} -> handle_parsed_network_tunnel(parsed_packet, depth)
          {:error, reason} -> {:error, reason}
        end

      true ->
        {:error, "Not a tunneled packet"}
    end
  end

  defp handle_parsed_network_tunnel(parsed_packet, depth) do
    case Map.get(parsed_packet, :data_extended) do
      %{raw_data: nested_data} when is_binary(nested_data) ->
        case parse_nested_tunnel(nested_data, depth + 1) do
          {:ok, nested_packet} -> {:ok, Map.put(parsed_packet, :nested_packet, nested_packet)}
          {:error, _} -> {:ok, parsed_packet}
        end

      _ ->
        {:ok, parsed_packet}
    end
  end

  # Add DAO (Datum) extension support
  @spec parse_dao_extension(String.t()) :: map() | nil
  defp parse_dao_extension(comment) do
    case Regex.run(~r/!([A-Za-z])([A-Za-z])([A-Za-z])!/, comment) do
      [_, lat_dao, lon_dao, _] ->
        %{
          lat_dao: lat_dao,
          lon_dao: lon_dao,
          datum: "WGS84"
        }

      _ ->
        nil
    end
  end

  # Helper to check if coordinate is valid (reduces redundant checks)
  defp valid_coordinate?(coord) do
    is_number(coord) or is_struct(coord, Decimal)
  end
end
