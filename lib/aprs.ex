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

  @version "0.1.5"

  @doc """
  Returns the current version of the APRS library as a static string.
  """
  @spec version() :: String.t()
  def version, do: @version

  # Simple APRS position parsing to replace parse_aprs_position
  @spec parse_aprs_position(String.t(), String.t()) :: %{latitude: coordinate(), longitude: coordinate()}
  defp parse_aprs_position(lat, lon) do
    with [_, lat_deg, lat_min, lat_dir] <- Regex.run(~r/^(\d{2})(\d{2}\.\d+)([NS])$/, lat),
         [_, lon_deg, lon_min, lon_dir] <- Regex.run(~r/^(\d{3})(\d{2}\.\d+)([EW])$/, lon) do
      lat_val =
        Decimal.add(Decimal.new(lat_deg), Decimal.div(Decimal.new(lat_min), Decimal.new("60")))

      lon_val =
        Decimal.add(Decimal.new(lon_deg), Decimal.div(Decimal.new(lon_min), Decimal.new("60")))

      lat = if lat_dir == "S", do: Decimal.negate(lat_val), else: lat_val
      lon = if lon_dir == "W", do: Decimal.negate(lon_val), else: lon_val

      # Convert to float
      lat_float = Decimal.to_float(lat)
      lon_float = Decimal.to_float(lon)

      %{latitude: lat_float, longitude: lon_float}
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
          ssid: String.t() | nil,
          data_extended: map() | nil,
          received_at: DateTime.t()
        }

  @type parse_result :: {:ok, packet()} | {:error, atom() | String.t()}

  @type position_ambiguity :: 0..4

  @type coordinate :: Decimal.t() | nil

  @type position_data :: %{
          required(:latitude) => coordinate(),
          required(:longitude) => coordinate(),
          optional(:timestamp) => String.t() | nil,
          optional(:symbol_table_id) => String.t() | nil,
          optional(:symbol_code) => String.t() | nil,
          optional(:comment) => String.t(),
          optional(:altitude) => float() | nil,
          optional(:phg) => map() | nil,
          optional(:aprs_messaging?) => boolean(),
          optional(:compressed?) => boolean(),
          optional(:position_ambiguity) => position_ambiguity(),
          optional(:dao) => map() | nil,
          optional(:course) => integer() | nil,
          optional(:speed) => float() | nil,
          optional(:has_position) => boolean(),
          optional(:data_type) => atom()
        }

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
    with {:ok, [sender, path, data]} <- split_packet(message),
         {:ok, callsign_parts} <- parse_callsign(sender),
         {:ok, data_type} <- parse_datatype_safe(data),
         {:ok, [destination, path2]} <- split_path(path),
         :ok <- validate_packet_parts(destination, sender, data_type),
         {:ok, packet_data} <- build_packet_data(sender, path2, destination, data, data_type, callsign_parts) do
      # Add resultcode and resultmsg for successful parse
      enriched_packet =
        Map.merge(packet_data, %{
          resultcode: "success",
          resultmsg: "OK"
        })

      {:ok, enriched_packet}
    else
      {:error, reason} ->
        {:error, format_error_message(reason)}

      _ ->
        {:error, :invalid_packet}
    end
  rescue
    _ ->
      {:error, "Parse exception"}
  end

  @spec format_error_message(any()) :: atom() | String.t()
  defp format_error_message(:invalid_packet), do: :invalid_packet
  defp format_error_message(:invalid_utf8), do: :invalid_utf8
  defp format_error_message(reason) when is_binary(reason), do: reason
  defp format_error_message(reason) when is_atom(reason), do: reason
  defp format_error_message(_), do: "Unknown error"

  @spec validate_packet_parts(String.t(), String.t(), atom()) :: :ok | {:error, :invalid_packet}
  defp validate_packet_parts(destination, sender, data_type) do
    if destination == "" and (sender == "" or (sender != "" and data_type == :empty)) do
      {:error, :invalid_packet}
    else
      :ok
    end
  end

  @spec build_packet_data(String.t(), String.t(), String.t(), String.t(), atom(), [String.t()]) ::
          {:ok, packet()} | {:error, :invalid_packet}
  defp build_packet_data(sender, path, destination, data, data_type, callsign_parts) do
    data_trimmed = trim_binary(data)
    data_without_type = extract_data_without_type(data_trimmed)
    data_extended = parse_data(data_type, destination, data_without_type)

    # Parse digipeaters from path
    digipeaters = parse_digipeaters(path)

    # Use data_type from data_extended if available (e.g., weather packets)
    final_data_type = if is_map(data_extended) && Map.has_key?(data_extended, :data_type) do
      data_extended.data_type
    else
      data_type
    end

    # Add standard APRS fields to the main packet structure
    base_packet = %{
      id: generate_packet_id(),
      sender: sender,
      path: path,
      destination: destination,
      information_field: data_trimmed,
      data_type: final_data_type,
      base_callsign: List.first(callsign_parts),
      ssid: extract_ssid(callsign_parts),
      data_extended: data_extended,
      received_at: DateTime.truncate(DateTime.utc_now(), :microsecond),
      # Standard APRS parser fields
      srccallsign: sender,
      dstcallsign: destination,
      body: data_trimmed,
      origpacket: sender <> ">" <> destination <> if(path == "", do: "", else: "," <> path) <> ":" <> data_trimmed,
      header: sender <> ">" <> destination <> if(path == "", do: "", else: "," <> path),
      alive: 1,
      # Add reference parser field mappings
      type: atom_to_standard_type(final_data_type),
      digipeaters: digipeaters,
      # Add commonly missing fields with default values
      posambiguity: 0,
      format: "uncompressed",
      messaging: 0,
      daodatumbyte: nil,
      gpsfixstatus: nil,
      mbits: nil,
      message: nil,
      phg: nil,
      wx: nil,
      radiorange: nil,
      itemname: nil
    }

    # Merge data_extended fields into main packet
    final_packet =
      if is_map(data_extended) do
        Map.merge(base_packet, data_extended)
      else
        base_packet
      end

    # Map internal field names to reference parser format
    final_packet = map_fields_to_reference_format(final_packet)

    {:ok, final_packet}
  rescue
    _ -> {:error, :invalid_packet}
  end

  @spec generate_packet_id() :: String.t()
  defp generate_packet_id do
    16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end

  @spec extract_data_without_type(String.t()) :: String.t()
  defp extract_data_without_type(<<_first_char::binary-size(1), rest::binary>>), do: rest
  defp extract_data_without_type(_), do: ""

  @spec extract_ssid([String.t()]) :: String.t() | nil
  defp extract_ssid(callsign_parts) do
    case List.last(callsign_parts) do
      nil -> nil
      s when is_binary(s) -> s
      i when is_integer(i) -> to_string(i)
      _ -> nil
    end
  end

  # Convert internal data_type atoms to standard type strings
  @spec atom_to_standard_type(atom()) :: String.t()
  defp atom_to_standard_type(:position), do: "location"
  defp atom_to_standard_type(:position_with_message), do: "location"
  defp atom_to_standard_type(:timestamped_position), do: "location"
  defp atom_to_standard_type(:timestamped_position_with_message), do: "location"
  defp atom_to_standard_type(:position_with_datetime_and_weather), do: "wx"
  defp atom_to_standard_type(:weather), do: "wx"
  defp atom_to_standard_type(:object), do: "object"
  defp atom_to_standard_type(:item), do: "item"
  defp atom_to_standard_type(:message), do: "message"
  defp atom_to_standard_type(:telemetry), do: "telemetry"
  defp atom_to_standard_type(:status), do: "status"
  defp atom_to_standard_type(:station_capabilities), do: "capabilities"
  defp atom_to_standard_type(:mic_e), do: "location"
  defp atom_to_standard_type(:mic_e_old), do: "location"
  defp atom_to_standard_type(:mic_e_error), do: "location"
  defp atom_to_standard_type(:malformed_position), do: "location"
  defp atom_to_standard_type(type), do: Atom.to_string(type)

  # Parse digipeaters from path string
  @spec parse_digipeaters(String.t()) :: [map()]
  defp parse_digipeaters(""), do: []

  defp parse_digipeaters(path) do
    path
    |> String.split(",")
    |> Enum.map(&parse_single_digipeater/1)
    |> Enum.reject(&is_nil/1)
  end

  @spec parse_single_digipeater(String.t()) :: map() | nil
  defp parse_single_digipeater(digi) do
    # Skip special digipeaters like qAC, qAS etc
    if String.starts_with?(digi, "q") and String.length(digi) == 3 do
      %{call: digi, wasdigied: 0}
    else
      # Check if the digipeater has been used (marked with *)
      if String.ends_with?(digi, "*") do
        %{call: String.trim_trailing(digi, "*"), wasdigied: 1}
      else
        %{call: digi, wasdigied: 0}
      end
    end
  end

  # Map internal field names to reference parser format
  defp map_fields_to_reference_format(packet) do
    packet
    |> map_position_ambiguity()
    |> map_dao_data()
    |> map_weather_data()
    |> map_telemetry_data()
    |> map_format_field()
    |> map_symbol_fields()
  end

  defp map_position_ambiguity(packet) do
    case packet do
      %{position_ambiguity: ambiguity} ->
        Map.put(packet, :posambiguity, ambiguity)

      _ ->
        packet
    end
  end

  defp map_dao_data(packet) do
    case packet do
      %{dao: %{datum: datum}} ->
        Map.put(packet, :daodatumbyte, datum)

      _ ->
        packet
    end
  end

  defp map_weather_data(packet) do
    case packet do
      %{weather: weather_data} when is_map(weather_data) ->
        Map.put(packet, :wx, weather_data)

      _ ->
        packet
    end
  end

  defp map_telemetry_data(packet) do
    case packet do
      %{telemetry: telemetry_data} when is_map(telemetry_data) ->
        Map.put(packet, :mbits, telemetry_data[:bits])

      _ ->
        packet
    end
  end

  defp map_format_field(packet) do
    case packet do
      %{data_extended: %{format: format}} ->
        Map.put(packet, :format, format)

      %{compressed?: true} ->
        Map.put(packet, :format, "compressed")

      %{format: _format} ->
        packet

      _ ->
        packet
    end
  end

  defp map_symbol_fields(packet) do
    packet
    |> Map.put(:symbolcode, Map.get(packet, :symbol_code))
    |> Map.put(:symboltable, Map.get(packet, :symbol_table_id))
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
            {:error, :invalid_packet}
        end

      :error ->
        {:error, :invalid_packet}
    end
  end

  # Helper function to find delimiter using binary pattern matching
  @spec find_delimiter(binary(), byte()) :: {:ok, binary(), binary()} | :error
  defp find_delimiter(binary, delimiter) do
    find_delimiter(binary, delimiter, 0, binary)
  end

  @spec find_delimiter(binary(), byte(), non_neg_integer(), binary()) :: {:ok, binary(), binary()} | :error
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
  # Using String.trim/1 is safe here as APRS packets should be ASCII
  @spec trim_binary(binary()) :: binary()
  defp trim_binary(binary) do
    String.trim(binary)
  end

  # Safely split path into destination and digipeater path
  @spec split_path(String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def split_path(path) when is_binary(path) do
    split = String.split(path, ",", parts: 2)
    split_path_parts(split)
  end

  @spec split_path_parts(list(String.t())) :: {:ok, [String.t()]} | {:error, String.t()}
  defp split_path_parts([destination, digi_path]), do: {:ok, [destination, digi_path]}
  defp split_path_parts([destination]), do: {:ok, [destination, ""]}
  defp split_path_parts(_), do: {:error, "Invalid path format"}

  # Safe version of parse_datatype that returns {:ok, type}
  @spec parse_datatype_safe(String.t()) :: {:ok, atom()}
  def parse_datatype_safe(""), do: {:ok, :empty}
  def parse_datatype_safe(data), do: {:ok, parse_datatype(data)}

  @spec parse_callsign(String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def parse_callsign(callsign) do
    case Aprs.AX25.parse_callsign(callsign) do
      {:ok, {base, ssid}} -> {:ok, [base, ssid]}
      {:error, reason} -> {:error, reason}
    end
  end

  # Map of data type indicators to their corresponding atom types
  @datatype_map %{
    ":" => :message,
    ">" => :status,
    "!" => :position,
    "/" => :timestamped_position,
    "=" => :position_with_message,
    "@" => :timestamped_position_with_message,
    ";" => :object,
    "`" => :mic_e_old,
    "'" => :mic_e_old,
    "_" => :weather,
    "T" => :telemetry,
    "$" => :raw_gps_ultimeter,
    "<" => :station_capabilities,
    "?" => :query,
    "{" => :user_defined,
    "}" => :third_party_traffic,
    "%" => :item,
    ")" => :item,
    "*" => :peet_logging,
    "," => :invalid_test_data
  }

  # One of the nutty exceptions in the APRS protocol has to do with this
  # data type indicator. It's usually the first character of the message.
  # However, in some rare cases, the ! indicator can be anywhere in the
  # first 40 characters of the message. I'm not going to deal with that
  # weird case right now. It seems like its for a specific type of old
  # TNC hardware that probably doesn't even exist anymore.
  @spec parse_datatype(String.t()) :: atom()
  def parse_datatype(data) when is_binary(data) and byte_size(data) > 0 do
    # Special cases for multi-character prefixes
    cond do
      String.starts_with?(data, "#DFS") ->
        :df_report

      String.starts_with?(data, "#PHG") ->
        :phg_data

      String.starts_with?(data, "#") ->
        :phg_data

      true ->
        # Get first character and look up in map
        <<first_char::binary-size(1), _::binary>> = data
        Map.get(@datatype_map, first_char, :unknown_datatype)
    end
  end

  def parse_datatype(_), do: :unknown_datatype

  @spec parse_data(atom(), String.t(), String.t()) :: map() | nil
  def parse_data(:empty, _destination, _data), do: %{data_type: :empty}
  def parse_data(:mic_e, destination, data), do: MicE.parse(data, destination, :mic_e)
  def parse_data(:mic_e_old, destination, data), do: MicE.parse(data, destination, :mic_e_old)
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
        trimmed_text = String.trim(message_text)

        %{
          data_type: :message,
          addressee: String.trim(addressee),
          message_text: trimmed_text,
          # Also store as 'message' field
          message: trimmed_text,
          message_number: message_number
        }

      [_, addressee, message_text] ->
        trimmed_text = String.trim(message_text)

        %{
          data_type: :message,
          addressee: String.trim(addressee),
          message_text: trimmed_text,
          # Also store as 'message' field
          message: trimmed_text
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
    if is_nil(result) do
      %{data_type: :malformed_position, error: "Failed to parse position with timestamp"}
    else
      data_type = Map.get(result, :data_type, :position)
      if data_type == :malformed_position, do: result, else: Map.put(result, :data_type, :position)
    end
  end

  def parse_data(:position, _destination, data) do
    result = parse_position_without_timestamp(data)
    if is_nil(result) do
      %{data_type: :malformed_position, error: "Failed to parse position"}
    else
      data_type = Map.get(result, :data_type, :position)
      if data_type == :malformed_position do 
        result 
      else 
        Map.put(result, :data_type, :position)
      end
    end
  end

  def parse_data(:position_with_message, _destination, data) do
    result = parse_position_with_message_without_timestamp(data)
    if is_nil(result) do
      %{data_type: :malformed_position, error: "Failed to parse position with message"}
    else
      Map.put(result, :data_type, :position_with_message)
    end
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
    Map.put(result, :has_location, has_valid_coordinates?(result))
  end

  @spec has_valid_coordinates?(map()) :: boolean()
  defp has_valid_coordinates?(%{latitude: lat, longitude: lon}) do
    valid_coordinate?(lat) and valid_coordinate?(lon)
  end

  defp has_valid_coordinates?(_), do: false

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
    weather_data = Weather.parse_weather_data(weather_report)
    
    # Remove timestamp from weather data to preserve the position timestamp
    weather_data_without_timestamp = Map.delete(weather_data, :timestamp)

    %{
      latitude: pos.latitude,
      longitude: pos.longitude,
      timestamp: time,
      symbol_table_id: sym_table_id,
      symbol_code: symbol_code,
      weather: weather_data_without_timestamp,
      data_type: :weather,
      aprs_messaging?: aprs_messaging?
    }
    |> Map.merge(weather_data_without_timestamp)
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

  # Helper to extract course and speed from comment field and clean the comment
  @spec extract_course_speed_and_clean_comment(String.t()) :: {integer() | nil, float() | nil, String.t()}
  defp extract_course_speed_and_clean_comment(comment) do
    cond do
      # Skip if comment starts with PHG
      String.starts_with?(comment, "PHG") ->
        {nil, nil, comment}

      # Match "/123/045" or "123/045" or "[123/045" pattern
      match = Regex.run(~r"^([/\[]?)(\d{3})/(\d{3})", comment) ->
        [full_match, _prefix, course_str, speed_str] = match
        course = String.to_integer(course_str)
        speed = String.to_integer(speed_str) * 1.0

        # Validate course (0-360) and reasonable speed (< 300 knots)
        if course >= 0 and course <= 360 and speed < 300 do
          cleaned_comment = comment |> String.replace(full_match, "") |> String.trim()
          {course, speed, cleaned_comment}
        else
          {nil, nil, comment}
        end

      true ->
        {nil, nil, comment}
    end
  end

  # Helper to extract course and speed from comment field (e.g., "/123/045" or "123/045" or "[123/045")
  @spec extract_course_and_speed(String.t()) :: {integer() | nil, float() | nil}
  defp extract_course_and_speed(comment) do
    {course, speed, _} = extract_course_speed_and_clean_comment(comment)
    {course, speed}
  end

  # Helper to extract altitude from comment field (e.g., "/A=000680")
  @spec extract_altitude_and_clean_comment(String.t()) :: {float() | nil, String.t()}
  defp extract_altitude_and_clean_comment(comment) do
    case Regex.run(~r"/A=(\d{6})", comment) do
      [full_match, altitude_str] ->
        # Convert to feet (altitude is in feet in APRS)
        altitude = String.to_integer(altitude_str) * 1.0
        # Remove the altitude from the comment
        cleaned_comment = comment |> String.replace(full_match, "") |> String.trim()
        {altitude, cleaned_comment}

      _ ->
        {nil, comment}
    end
  end

  # Helper to extract PHG data from comment
  @spec extract_phg_data(String.t()) :: {map() | nil, String.t()}
  defp extract_phg_data(comment) do
    case Regex.run(~r"PHG(\d)(\d)(\d)(\d)", comment) do
      [full_match, p, h, g, d] ->
        # PHG helpers expect character codes, not strings
        <<p_char::8>> = p
        <<h_char::8>> = h
        <<g_char::8>> = g
        <<d_char::8>> = d

        {power_val, _} = Aprs.PHGHelpers.parse_phg_power(p_char)
        {height_val, _} = Aprs.PHGHelpers.parse_phg_height(h_char)
        {gain_val, _} = Aprs.PHGHelpers.parse_phg_gain(g_char)
        {dir_val, _} = Aprs.PHGHelpers.parse_phg_directivity(d_char)

        phg_map = %{
          power: power_val,
          height: height_val,
          gain: gain_val,
          directivity: dir_val
        }

        # Remove PHG from comment
        cleaned_comment = comment |> String.replace(full_match, "") |> String.trim()
        {phg_map, cleaned_comment}

      _ ->
        {nil, comment}
    end
  end

  # Helper to extract PHG string from comment (for compatibility)
  @spec extract_phg_string(String.t()) :: String.t() | nil
  defp extract_phg_string(comment) do
    case Regex.run(~r"PHG(\d{4})", comment) do
      [_, phg_digits] -> phg_digits
      _ -> nil
    end
  end

  # Helper to extract radiorange (RNG) from comment and clean it
  @spec extract_radiorange_and_clean_comment(String.t()) :: {String.t() | nil, String.t()}
  defp extract_radiorange_and_clean_comment(comment) do
    case Regex.run(~r"RNG(\d{4})", comment) do
      [full_match, range_digits] ->
        # Convert to range in miles (APRS standard)
        range_miles = String.to_integer(range_digits)
        cleaned_comment = comment |> String.replace(full_match, "") |> String.trim()
        {Integer.to_string(range_miles), cleaned_comment}

      _ ->
        {nil, comment}
    end
  end

  # Helper to extract weather data from comment and clean it
  @spec extract_weather_and_clean_comment(String.t()) :: {map() | nil, String.t()}
  defp extract_weather_and_clean_comment(comment) do
    if Weather.weather_packet_comment?(comment) do
      weather_data = Weather.parse_weather_data(comment)

      # Extract all weather parameters and remove them from comment
      cleaned_comment =
        comment
        # timestamp
        |> remove_weather_pattern(~r/_\d{8}/)
        # wind direction/speed
        |> remove_weather_pattern(~r/\d{3}\/\d{3}/)
        # wind gust
        |> remove_weather_pattern(~r/g\d{3}/)
        # temperature
        |> remove_weather_pattern(~r/t-?\d{3}/)
        # rain 1h
        |> remove_weather_pattern(~r/r\d{3}/)
        # rain 24h
        |> remove_weather_pattern(~r/p\d{3}/)
        # rain since midnight
        |> remove_weather_pattern(~r/P\d{3}/)
        # humidity
        |> remove_weather_pattern(~r/h\d{2}/)
        # pressure
        |> remove_weather_pattern(~r/b\d{5}/)
        # luminosity
        |> remove_weather_pattern(~r/L\d{3}/)
        # luminosity (lowercase)
        |> remove_weather_pattern(~r/l\d{3}/)
        # snow
        |> remove_weather_pattern(~r/s\d{3}/)
        |> String.trim()

      {weather_data, cleaned_comment}
    else
      {nil, comment}
    end
  end

  # Helper to remove weather patterns from comment
  defp remove_weather_pattern(comment, pattern) do
    String.replace(comment, pattern, "")
  end

  # Patch parse_position_without_timestamp to include course/speed
  @spec parse_position_without_timestamp(String.t()) :: map()
  def parse_position_without_timestamp(position_data) do
    case position_data do
      # Uncompressed position with validation
      <<latitude::binary-size(8), sym_table_id::binary-size(1), longitude::binary-size(9), symbol_code::binary-size(1),
        comment::binary>> ->
        if valid_aprs_coordinate?(latitude, longitude) do
          parse_position_uncompressed(latitude, sym_table_id, longitude, symbol_code, comment)
        else
          # Try compressed position without "/" prefix as fallback
          try_parse_compressed_without_prefix(position_data)
        end

      <<latitude::binary-size(8), sym_table_id::binary-size(1), longitude::binary-size(9)>> ->
        if valid_aprs_coordinate?(latitude, longitude) do
          parse_position_short_uncompressed(latitude, sym_table_id, longitude)
        else
          # Try compressed position without "/" prefix as fallback
          try_parse_compressed_without_prefix(position_data)
        end

      # Compressed format with DAO extension - Symbol table first: TYYYYXXXXC>&!...
      <<sym_table::binary-size(1), latitude_compressed::binary-size(4), longitude_compressed::binary-size(4), 
        cs_byte::binary-size(1), symbol_code::binary-size(1), "&!", comment::binary>> 
      when byte_size(position_data) >= 13 ->
        # Parse with symbol table and course/speed
        parse_position_compressed_with_full_data(
          sym_table,
          latitude_compressed,
          longitude_compressed,
          symbol_code,
          cs_byte <> " ",  # Course/speed with padding
          " ",             # No compression type with DAO
          comment
        )

      # Check for DAO extension in standard compressed format: /YYYYXXXXS>&!...
      <<"/", latitude_compressed::binary-size(4), longitude_compressed::binary-size(4), symbol_code::binary-size(1),
        cs::binary-size(2), compression_type::binary-size(1), comment::binary>> 
      when cs == "&!" ->
        # This is a DAO extension pattern where symbol is at standard position
        # but cs contains "&!" marker
        parse_position_compressed(
          latitude_compressed,
          longitude_compressed,
          symbol_code,
          "",  # No real course/speed
          " ",  # No compression type
          compression_type <> comment  # Keep the byte that was compression_type
        )

      # Compressed format with DAO extension: /YYYYXXXX>&!HDDDDD...
      <<"/", latitude_compressed::binary-size(4), longitude_compressed::binary-size(4), symbol_code::binary-size(1),
        "&!", comment::binary>> ->
        parse_position_compressed(
          latitude_compressed,
          longitude_compressed,
          symbol_code,
          # No course/speed data with DAO extension
          "",
          # Use space as default compression type  
          " ",
          "&!" <> comment
        )

      # Standard compressed format: /YYYYXXXXSCTHHHHHH...
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

      # Compressed format with "!" prefix and DAO extension: !YYYYXXXXC>&!...
      <<"!", latitude_compressed::binary-size(4), longitude_compressed::binary-size(4), cs_byte::binary-size(1), 
        symbol_code::binary-size(1), "&!", comment::binary>> ->
        # Special DAO format where symbol comes after course/speed byte
        parse_position_compressed(
          latitude_compressed,
          longitude_compressed,
          symbol_code,
          # Use cs_byte as course/speed with empty second byte
          cs_byte <> " ",
          # No compression type with DAO
          " ",
          comment
        )

      # Standard compressed format with "!" prefix: !YYYYXXXXSCTHHHHHH...
      <<"!", latitude_compressed::binary-size(4), longitude_compressed::binary-size(4), symbol_code::binary-size(1),
        cs::binary-size(2), compression_type::binary-size(1), comment::binary>> ->
        parse_position_compressed(
          latitude_compressed,
          longitude_compressed,
          symbol_code,
          cs,
          compression_type,
          comment
        )

      # Compressed position with leading symbol table (alternate table)
      <<sym_table_id::binary-size(1), latitude_compressed::binary-size(4), longitude_compressed::binary-size(4),
        symbol_code::binary-size(1), rest::binary>>
      when byte_size(position_data) >= 10 ->
        # Check if this is likely an alternate symbol table format
        # by checking if sym_table_id is a common alternate table char
        case sym_table_id do
          <<"L">> ->
            # This is the specific format we're looking for
            parse_position_compressed_with_symbol_table(
              sym_table_id,
              latitude_compressed,
              longitude_compressed,
              symbol_code,
              rest
            )

          <<"\\">> ->
            # Alternate symbol table
            parse_position_compressed_with_symbol_table(
              sym_table_id,
              latitude_compressed,
              longitude_compressed,
              symbol_code,
              rest
            )

          _ ->
            # Not an alternate table, try other formats
            parse_position_without_timestamp_fallback(position_data)
        end

      # Special case: if bytes 9-10 are '&!', this is a DAO extension
      <<latitude_compressed::binary-size(4), longitude_compressed::binary-size(4), symbol_code::binary-size(1),
        "&!", comment::binary>> ->
        # IO.puts("[DEBUG] Matched DAO extension pattern starting with &!")
        # The compression type should be space (no compression type byte)
        # Use the first character of comment as compression type fallback

        parse_position_compressed_missing_prefix(
          latitude_compressed,
          longitude_compressed,
          symbol_code,
          # No course/speed data when DAO extension is present
          "",
          # Use space as compression type
          " ",
          "&!" <> comment
        )

      # Normal case (but not starting with "/")
      <<latitude_compressed::binary-size(4), longitude_compressed::binary-size(4), symbol_code::binary-size(1),
        cs::binary-size(2), compression_type::binary-size(1), rest::binary>>
      when byte_size(position_data) >= 13 and not (binary_part(position_data, 0, 1) == "/") ->
        parse_position_compressed_missing_prefix(
          latitude_compressed,
          longitude_compressed,
          symbol_code,
          cs,
          compression_type,
          rest
        )

      _ ->
        parse_position_malformed(position_data)
    end
  end

  # Helper function to validate APRS coordinates
  @spec valid_aprs_coordinate?(String.t(), String.t()) :: boolean()
  defp valid_aprs_coordinate?(lat, lon) do
    lat_valid = Regex.match?(~r/^\d{4}\.\d{2}[NS]$/, lat)
    lon_valid = Regex.match?(~r/^\d{5}\.\d{2}[EW]$/, lon)
    lat_valid and lon_valid
  end

  # Helper function to try parsing as compressed position without "/" prefix
  defp try_parse_compressed_without_prefix(position_data) do
    case position_data do
      # Handle "/" symbol table compressed positions with DAO check
      <<"/", latitude_compressed::binary-size(4), longitude_compressed::binary-size(4), symbol_code::binary-size(1),
        cs::binary-size(2), compression_type::binary-size(1), comment::binary>> 
      when cs == "&!" ->
        parse_position_compressed_with_full_data(
          "/",
          latitude_compressed,
          longitude_compressed,
          symbol_code,
          "",  # No real course/speed
          " ",  # No compression type
          compression_type <> comment
        )

      # Handle "/" symbol table compressed positions
      <<"/", latitude_compressed::binary-size(4), longitude_compressed::binary-size(4), symbol_code::binary-size(1),
        cs::binary-size(2), compression_type::binary-size(1), comment::binary>> ->
        parse_position_compressed_with_full_data(
          "/",
          latitude_compressed,
          longitude_compressed,
          symbol_code,
          cs,
          compression_type,
          comment
        )

      # Check for alternate symbol table compressed format first
      <<sym_table_id::binary-size(1), latitude_compressed::binary-size(4), longitude_compressed::binary-size(4),
        symbol_code::binary-size(1), rest::binary>>
      when byte_size(position_data) >= 10 and sym_table_id in [<<"L">>, <<"\\">>] ->
        parse_position_compressed_with_symbol_table(
          sym_table_id,
          latitude_compressed,
          longitude_compressed,
          symbol_code,
          rest
        )

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
    {dao_data, comment_after_dao} = parse_dao_extension(comment)

    # Extract altitude and clean the comment
    {altitude, comment_after_altitude} = extract_altitude_and_clean_comment(comment_after_dao)

    # Extract PHG data but don't remove it from comment
    {_phg_data, _} = extract_phg_data(comment_after_altitude)
    phg_string = extract_phg_string(comment_after_altitude)

    # Extract RNG (radio range) data and clean comment
    {radiorange, comment_after_rng} = extract_radiorange_and_clean_comment(comment_after_altitude)

    # Extract weather data from comment and clean it
    {weather_data, comment_after_weather} = extract_weather_and_clean_comment(comment_after_rng)

    # Extract course and speed from the cleaned comment and clean it further
    {course, speed, comment_cleaned} = extract_course_speed_and_clean_comment(comment_after_weather)

    has_position = valid_coordinate?(lat) and valid_coordinate?(lon)

    # Calculate position resolution based on ambiguity
    posresolution = Aprs.UtilityHelpers.calculate_position_resolution(ambiguity)

    base_map = %{
      latitude: lat,
      longitude: lon,
      timestamp: nil,
      symbol_table_id: sym_table_id,
      symbol_code: symbol_code,
      # Ensure proper trimming
      comment: String.trim(comment_cleaned),
      altitude: altitude,
      # Use string representation only
      phg: phg_string,
      aprs_messaging?: false,
      compressed?: false,
      position_ambiguity: ambiguity,
      dao: dao_data,
      course: course,
      speed: speed,
      has_position: has_position,
      posresolution: posresolution,
      format: "uncompressed",
      # Standard parser fields
      posambiguity: ambiguity,
      messaging: 0,
      radiorange: radiorange,
      wx: weather_data
    }

    # Check if this is a weather packet and merge accordingly
    merge_weather_if_present(base_map, sym_table_id, symbol_code, comment)
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
      has_position: has_position,
      format: "uncompressed",
      # Standard parser fields
      posambiguity: ambiguity,
      messaging: 0
    }
  end

  defp parse_position_compressed(latitude_compressed, longitude_compressed, symbol_code, cs, compression_type, comment) do
    # IO.puts("parse_position_compressed called with comment: #{comment}")

    case {Aprs.CompressedPositionHelpers.convert_compressed_lat(latitude_compressed),
          Aprs.CompressedPositionHelpers.convert_compressed_lon(longitude_compressed)} do
      {{:ok, converted_lat}, {:ok, converted_lon}} ->
        compressed_cs = Aprs.CompressedPositionHelpers.convert_compressed_cs(cs)

        # Parse full compression type information
        compression_info = Aprs.CompressedPositionHelpers.parse_compression_type(compression_type)
        ambiguity = compression_info.position_resolution

        has_position = valid_coordinate?(converted_lat) and valid_coordinate?(converted_lon)

        # Extract telemetry from comment if present
        {telemetry, cleaned_comment} = Aprs.TelemetryFromComment.extract_telemetry_from_comment(comment)

        # Parse DAO extension from comment
        {dao_data, cleaned_comment_after_dao} = parse_dao_extension(cleaned_comment)

        # Calculate position resolution for compressed format
        posresolution = Aprs.UtilityHelpers.calculate_compressed_position_resolution()

        base_data = %{
          latitude: converted_lat,
          longitude: converted_lon,
          symbol_table_id: "/",
          symbol_code: symbol_code,
          comment: cleaned_comment_after_dao,
          position_format: :compressed,
          compression_type: compression_type,
          compression_info: compression_info,
          data_type: :position,
          compressed?: true,
          position_ambiguity: ambiguity,
          dao: dao_data,
          has_position: has_position,
          posresolution: posresolution,
          format: "compressed",
          # Standard parser fields
          posambiguity: ambiguity,
          messaging: if(compression_info.aprs_messaging, do: 1, else: 0)
        }

        # Add telemetry if found
        data_with_cs = Map.merge(base_data, compressed_cs)

        if telemetry do
          Map.put(data_with_cs, :telemetry, telemetry)
        else
          data_with_cs
        end

      {{:error, lat_error}, _} ->
        %{
          data_type: :position_error,
          error_message: "Invalid compressed location: #{lat_error}",
          has_position: false
        }

      {_, {:error, lon_error}} ->
        %{
          data_type: :position_error,
          error_message: "Invalid compressed location: #{lon_error}",
          has_position: false
        }

      _ ->
        %{
          data_type: :position_error,
          error_message: "Invalid compressed location",
          has_position: false
        }
    end
  end

  defp parse_position_without_timestamp_fallback(position_data) do
    # Try the standard compressed format without prefix
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

  defp parse_position_compressed_with_full_data(
         sym_table_id,
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
        compression_info = Aprs.CompressedPositionHelpers.parse_compression_type(compression_type)
        ambiguity = compression_info.position_resolution
        has_position = valid_coordinate?(converted_lat) and valid_coordinate?(converted_lon)

        # Extract telemetry from comment if present
        {telemetry, cleaned_comment} = Aprs.TelemetryFromComment.extract_telemetry_from_comment(comment)

        # Parse DAO extension from comment
        {dao_data, cleaned_comment_after_dao} = parse_dao_extension(cleaned_comment)

        # Calculate position resolution for compressed format
        _posresolution = Aprs.UtilityHelpers.calculate_compressed_position_resolution()

        base_data = %{
          latitude: converted_lat,
          longitude: converted_lon,
          symbol_table_id: sym_table_id,
          symbol_code: symbol_code,
          comment: cleaned_comment_after_dao,
          position_format: :compressed,
          compression_type: compression_type,
          compression_info: compression_info,
          data_type: :position,
          compressed?: true,
          position_ambiguity: ambiguity,
          dao: dao_data,
          has_position: has_position,
          format: "compressed",
          posambiguity: ambiguity,
          messaging: compression_info.aprs_messaging
        }

        base_data = 
          if telemetry != nil do
            Map.put(base_data, :telemetry, telemetry)
          else
            base_data
          end

        # Add course and speed if available
        Map.merge(base_data, compressed_cs)

      {{:error, lat_error}, _} ->
        %{
          data_type: :position_error,
          error_message: "Invalid compressed location: #{lat_error}",
          has_position: false
        }

      {_, {:error, lon_error}} ->
        %{
          data_type: :position_error,
          error_message: "Invalid compressed location: #{lon_error}",
          has_position: false
        }

      _ ->
        %{
          data_type: :position_error,
          error_message: "Invalid compressed location",
          has_position: false
        }
    end
  end

  defp parse_position_compressed_with_symbol_table(
         sym_table_id,
         latitude_compressed,
         longitude_compressed,
         symbol_code,
         comment
       ) do
    case {Aprs.CompressedPositionHelpers.convert_compressed_lat(latitude_compressed),
          Aprs.CompressedPositionHelpers.convert_compressed_lon(longitude_compressed)} do
      {{:ok, converted_lat}, {:ok, converted_lon}} ->
        has_position = valid_coordinate?(converted_lat) and valid_coordinate?(converted_lon)

        # Extract telemetry from comment if present
        {telemetry, cleaned_comment} = Aprs.TelemetryFromComment.extract_telemetry_from_comment(comment)

        # Parse DAO extension from comment
        {dao_data, cleaned_comment_after_dao} = parse_dao_extension(cleaned_comment)

        # Calculate position resolution for compressed format
        posresolution = Aprs.UtilityHelpers.calculate_compressed_position_resolution()

        base_data = %{
          latitude: converted_lat,
          longitude: converted_lon,
          symbol_table_id: sym_table_id,
          symbol_code: symbol_code,
          comment: cleaned_comment_after_dao,
          position_format: :compressed,
          compression_type: nil,
          data_type: :position,
          compressed?: true,
          position_ambiguity: 0,
          dao: dao_data,
          has_position: has_position,
          course: nil,
          speed: nil,
          posresolution: posresolution,
          format: "compressed",
          # Standard parser fields
          posambiguity: 0,
          messaging: 0
        }

        # Add telemetry if found
        if telemetry do
          Map.put(base_data, :telemetry, telemetry)
        else
          base_data
        end

      {{:error, lat_error}, _} ->
        %{
          data_type: :position_error,
          error_message: "Invalid compressed location: #{lat_error}",
          has_position: false
        }

      {_, {:error, lon_error}} ->
        %{
          data_type: :position_error,
          error_message: "Invalid compressed location: #{lon_error}",
          has_position: false
        }

      _ ->
        %{
          data_type: :position_error,
          error_message: "Invalid compressed location",
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
    # IO.puts("parse_position_compressed_missing_prefix called with comment: #{comment}")

    case {Aprs.CompressedPositionHelpers.convert_compressed_lat(latitude_compressed),
          Aprs.CompressedPositionHelpers.convert_compressed_lon(longitude_compressed)} do
      {{:ok, converted_lat}, {:ok, converted_lon}} ->
        compressed_cs = Aprs.CompressedPositionHelpers.convert_compressed_cs(cs)

        # Parse full compression type information
        compression_info = Aprs.CompressedPositionHelpers.parse_compression_type(compression_type)
        ambiguity = compression_info.position_resolution

        has_position = valid_coordinate?(converted_lat) and valid_coordinate?(converted_lon)

        # Parse DAO extension from comment
        {dao_data, cleaned_comment_after_dao} = parse_dao_extension(comment)

        base_data = %{
          latitude: converted_lat,
          longitude: converted_lon,
          symbol_table_id: "/",
          symbol_code: symbol_code,
          comment: cleaned_comment_after_dao,
          position_format: :compressed,
          compression_type: compression_type,
          compression_info: compression_info,
          data_type: :position,
          compressed?: true,
          position_ambiguity: ambiguity,
          dao: dao_data,
          has_position: has_position
        }

        Map.merge(base_data, compressed_cs)

      {{:error, lat_error}, _} ->
        %{
          data_type: :position_error,
          error_message: "Invalid compressed location: #{lat_error}",
          has_position: false
        }

      {_, {:error, lon_error}} ->
        %{
          data_type: :position_error,
          error_message: "Invalid compressed location: #{lon_error}",
          has_position: false
        }

      _ ->
        %{
          data_type: :position_error,
          error_message: "Invalid compressed location",
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
    if is_nil(result) do
      nil
    else
      Map.put(result, :aprs_messaging?, true)
    end
  end

  # Patch parse_position_with_timestamp to extract course/speed from comment
  @spec parse_position_with_timestamp(boolean(), binary(), atom()) :: map()
  def parse_position_with_timestamp(
        aprs_messaging?,
        <<time::binary-size(7), latitude::binary-size(8), sym_table_id::binary-size(1), longitude::binary-size(9),
          symbol_code::binary-size(1), comment::binary>>,
        data_type
      ) do
    case Aprs.UtilityHelpers.validate_position_data(latitude, longitude) do
      {:ok, {lat, lon}} ->
        build_position_result(aprs_messaging?, lat, lon, time, sym_table_id, symbol_code, comment, data_type)

      _ ->
        handle_invalid_position_data(aprs_messaging?, time, latitude, sym_table_id, longitude, symbol_code, comment, data_type)
    end
  end

  def parse_position_with_timestamp(_aprs_messaging?, _data, _data_type) do
    %{
      data_type: :timestamped_position_error,
      error: "Invalid timestamped position format"
    }
  end

  defp handle_invalid_position_data(aprs_messaging?, time, latitude, sym_table_id, longitude, symbol_code, comment, _data_type) do
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
      aprs_messaging?: aprs_messaging?,
      compressed?: false
    }

    merge_weather_if_present(base_map, sym_table, sym_code, comment)
  end

  defp build_position_result(aprs_messaging?, lat, lon, time, sym_table_id, symbol_code, comment, data_type) do
    position =
      if is_binary(lat) and is_binary(lon) do
        parse_aprs_position(lat, lon)
      else
        %{latitude: lat, longitude: lon}
      end

    {course, speed} = extract_course_and_speed(comment)
    unix_timestamp = Aprs.UtilityHelpers.validate_timestamp(time)

    base_map = %{
      latitude: position.latitude,
      longitude: position.longitude,
      position: position,
      time: unix_timestamp,
      # Also store as 'timestamp' field
      timestamp: unix_timestamp,
      symbol_table_id: sym_table_id,
      symbol_code: symbol_code,
      comment: comment,
      aprs_messaging?: aprs_messaging?,
      compressed?: false,
      course: course,
      speed: speed,
      data_type: data_type,
      # Standard fields
      format: "uncompressed",
      messaging: if(aprs_messaging?, do: 1, else: 0)
    }

    merge_weather_if_present(base_map, sym_table_id, symbol_code, comment)
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

  # Map of user-defined format identifiers
  @user_defined_formats %{
    "A" => :experimental_a,
    "B" => :experimental_b,
    "C" => :custom_c
  }

  # Parse specific user-defined formats
  @spec parse_user_defined_format(String.t(), String.t()) :: map()
  defp parse_user_defined_format(user_id, user_data) do
    format = Map.get(@user_defined_formats, user_id, :unknown)
    %{format: format, content: user_data}
  end

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
    {:ok, data_type} = parse_datatype_safe(information)
    data_without_type = String.slice(information, 1..-1//1)
    data_extended = parse_data(data_type, header_data.destination, data_without_type)

    {:ok,
     Map.merge(header_data, %{
       information_field: information,
       data_type: data_type,
       data_extended: data_extended
     })}
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
        ssid = List.last(callsign_parts)

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
  @spec parse_dao_extension(String.t()) :: {map() | nil, String.t()}
  defp parse_dao_extension(comment) do
    # IO.puts("parse_dao_extension called with comment: #{comment}")

    case Regex.run(~r/!([A-Za-z])([A-Za-z])([A-Za-z])!/, comment) do
      [full_match, lat_dao, lon_dao, _] ->
        cleaned_comment = comment |> String.replace(full_match, "") |> String.trim()

        dao_data = %{
          lat_dao: lat_dao,
          lon_dao: lon_dao,
          datum: "WGS84"
        }

        # IO.puts("DAO regex 1 matched: #{inspect(dao_data)}")
        {dao_data, cleaned_comment}

      _ ->
        # Try alternative DAO format with & prefix
        case Regex.run(~r/&!([A-Za-z])/, comment) do
          [full_match, datum_byte] ->
            cleaned_comment = comment |> String.replace(full_match, "") |> String.trim()

            dao_data = %{
              lat_dao: nil,
              lon_dao: nil,
              datum: datum_byte
            }

            # IO.puts("DAO regex 2 matched: #{inspect(dao_data)}")
            {dao_data, cleaned_comment}

          _ ->
            # IO.puts("DAO regex did not match")
            {nil, comment}
        end
    end
  end

  # Helper to check if coordinate is valid (reduces redundant checks)
  defp valid_coordinate?(coord) do
    is_number(coord) or is_struct(coord, Decimal)
  end

  # Extract common weather merging logic
  @spec merge_weather_if_present(map(), String.t(), String.t(), String.t()) :: map()
  defp merge_weather_if_present(base_map, sym_table_id, symbol_code, comment) do
    if weather_packet?(sym_table_id, symbol_code, comment) do
      weather_data = extract_weather_data(sym_table_id, symbol_code, comment)
      # Remove timestamp from weather data to preserve the position timestamp
      weather_data_without_timestamp = Map.delete(weather_data, :timestamp)
      base_map
      |> Map.merge(weather_data_without_timestamp)
      |> Map.put(:data_type, :weather)
    else
      base_map
    end
  end

  @spec weather_packet?(String.t(), String.t(), String.t()) :: boolean()
  defp weather_packet?(sym_table_id, symbol_code, comment) do
    (sym_table_id == "/" and symbol_code == "_") or Weather.weather_packet_comment?(comment)
  end

  @spec extract_weather_data(String.t(), String.t(), String.t()) :: map()
  defp extract_weather_data("/", "_", comment) do
    Weather.parse_weather_data(comment)
  end

  defp extract_weather_data(_sym_table_id, _symbol_code, comment) do
    case Weather.parse_from_comment(comment) do
      nil -> %{}
      weather_map -> weather_map
    end
  end

end
