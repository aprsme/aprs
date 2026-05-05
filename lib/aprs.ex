defmodule Aprs do
  @moduledoc """
  Main APRS packet parsing library
  """

  import Aprs.Guards

  alias Aprs.Item
  alias Aprs.MicE
  alias Aprs.Object
  alias Aprs.PHG
  alias Aprs.Status
  alias Aprs.Telemetry
  alias Aprs.Weather

  @version "0.1.6"

  @doc """
  Returns the current version of the APRS library as a static string.
  """
  @spec version() :: String.t()
  def version, do: @version

  # APRS position parsing with position ambiguity support
  @spec parse_aprs_position(String.t(), String.t()) :: %{
          latitude: float() | nil,
          longitude: float() | nil,
          ambiguity: 0..4
        }
  defp parse_aprs_position(lat, lon) do
    Aprs.Position.parse_aprs_position(lat, lon)
  end

  @type packet :: %{
          required(:id) => String.t(),
          required(:sender) => String.t(),
          required(:path) => String.t(),
          required(:destination) => String.t(),
          required(:information_field) => String.t(),
          required(:data_type) => atom(),
          required(:base_callsign) => String.t(),
          required(:ssid) => String.t() | nil,
          required(:data_extended) => map() | nil,
          required(:received_at) => DateTime.t(),
          optional(atom()) => term()
        }

  @type parse_result :: {:ok, packet()} | {:error, atom() | String.t()}

  @type position_ambiguity :: 0..4

  @type coordinate :: float() | nil

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
    # Strip trailing null bytes before parsing
    message = String.trim_trailing(message, <<0>>)
    # Ensure the message is valid UTF-8 before parsing
    parse_with_encoding(message, String.valid?(message))
  end

  @spec parse(any()) :: parse_result()
  def parse(_), do: {:error, :invalid_packet}

  @spec parse_with_encoding(String.t(), boolean()) :: parse_result()
  defp parse_with_encoding(message, true), do: do_parse(message)
  # Try to fix invalid UTF-8 by replacing invalid bytes
  defp parse_with_encoding(message, false) do
    fixed_message = String.replace(message, ~r/[^\x00-\x7F]/, "?")
    do_parse(fixed_message)
  end

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
    end
  rescue
    _ ->
      {:error, "Parse exception"}
  end

  @spec format_error_message(:invalid_packet) :: :invalid_packet
  defp format_error_message(:invalid_packet), do: :invalid_packet

  @spec validate_packet_parts(String.t(), String.t(), atom()) :: :ok | {:error, :invalid_packet}
  defp validate_packet_parts("", _, :empty), do: {:error, :invalid_packet}
  defp validate_packet_parts(_, _, _), do: :ok

  @spec build_packet_data(String.t(), String.t(), String.t(), String.t(), atom(), [String.t()]) ::
          {:ok, packet()}
  defp build_packet_data(sender, path, destination, data, data_type, callsign_parts) do
    data_trimmed = trim_binary(data)
    # For messages and items, we need to keep the type indicator
    data_for_parsing = prepare_data_for_parsing(data_type, data_trimmed)

    data_extended = parse_data(data_type, destination, data_for_parsing)

    # Parse digipeaters from path
    digipeaters = parse_digipeaters(path)

    # Use data_type from data_extended if available (e.g., weather packets)
    final_data_type = determine_final_data_type(data_extended, data_type)

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
    final_packet = merge_data_extended(base_packet, data_extended)

    # Map internal field names to reference parser format
    final_packet = map_fields_to_reference_format(final_packet)

    {:ok, final_packet}
  end

  @spec generate_packet_id() :: String.t()
  defp generate_packet_id do
    16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end

  @spec extract_data_without_type(String.t()) :: String.t()
  defp extract_data_without_type(<<_first_char::binary-size(1), rest::binary>>), do: rest
  defp extract_data_without_type(_), do: ""

  @spec extract_ssid([String.t()]) :: String.t()
  defp extract_ssid(callsign_parts), do: List.last(callsign_parts)

  @spec prepare_data_for_parsing(atom(), String.t()) :: String.t()
  defp prepare_data_for_parsing(:message, data), do: data
  defp prepare_data_for_parsing(:item, data), do: data
  defp prepare_data_for_parsing(_, data), do: extract_data_without_type(data)

  @spec determine_final_data_type(map() | nil, atom()) :: atom()
  defp determine_final_data_type(%{data_type: type}, _) when is_atom(type), do: type
  defp determine_final_data_type(_, data_type), do: data_type

  # Map of internal data_type atoms to standard type strings
  @standard_type_map %{
    position: "location",
    position_with_message: "location",
    timestamped_position: "location",
    timestamped_position_with_message: "location",
    position_with_datetime_and_weather: "wx",
    weather: "wx",
    object: "object",
    item: "item",
    message: "message",
    telemetry_message: "telemetry-message",
    telemetry: "telemetry",
    status: "status",
    station_capabilities: "capabilities",
    mic_e: "location",
    mic_e_old: "location",
    mic_e_error: "location",
    malformed_position: "location",
    nmea: "location"
  }

  # Convert internal data_type atoms to standard type strings
  @spec atom_to_standard_type(atom()) :: String.t()
  defp atom_to_standard_type(type) do
    Map.get(@standard_type_map, type, Atom.to_string(type))
  end

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
  defp parse_single_digipeater(<<"q", _::binary-size(2)>> = digi) do
    %{call: digi, wasdigied: 0}
  end

  defp parse_single_digipeater(digi) do
    parse_digipeater_usage(digi, String.ends_with?(digi, "*"))
  end

  @spec parse_digipeater_usage(String.t(), boolean()) :: map()
  defp parse_digipeater_usage(digi, true) do
    %{call: String.trim_trailing(digi, "*"), wasdigied: 1}
  end

  defp parse_digipeater_usage(digi, false) do
    %{call: digi, wasdigied: 0}
  end

  # Map internal field names to reference parser format
  @spec map_fields_to_reference_format(map()) :: map()
  defp map_fields_to_reference_format(packet) do
    packet
    |> map_position_ambiguity()
    |> map_dao_data()
    |> map_weather_data()
    |> map_telemetry_data()
    |> map_format_field()
    |> map_symbol_fields()
    |> map_messaging()
  end

  @spec map_messaging(map()) :: map()
  defp map_messaging(%{aprs_messaging?: true} = packet), do: Map.put(packet, :messaging, 1)
  defp map_messaging(packet), do: packet

  @spec merge_data_extended(map(), map() | nil) :: map()
  defp merge_data_extended(base_packet, data_extended) when is_map(data_extended) do
    Map.merge(base_packet, data_extended)
  end

  defp merge_data_extended(base_packet, _), do: base_packet

  @spec map_position_ambiguity(map()) :: map()
  defp map_position_ambiguity(%{position_ambiguity: ambiguity} = packet) do
    Map.put(packet, :posambiguity, ambiguity)
  end

  defp map_position_ambiguity(packet), do: packet

  @spec map_dao_data(map()) :: map()
  defp map_dao_data(%{dao: %{datum: datum}} = packet) do
    Map.put(packet, :daodatumbyte, datum)
  end

  defp map_dao_data(packet), do: packet

  @spec map_weather_data(map()) :: map()
  defp map_weather_data(%{weather: weather_data} = packet) when is_map(weather_data) do
    Map.put(packet, :wx, weather_data)
  end

  defp map_weather_data(packet), do: packet

  @spec map_telemetry_data(map()) :: map()
  defp map_telemetry_data(%{telemetry: %{bits: bits}} = packet) do
    Map.put(packet, :mbits, bits)
  end

  defp map_telemetry_data(%{telemetry: telemetry_data} = packet) when is_map(telemetry_data) do
    Map.put(packet, :mbits, telemetry_data[:bits])
  end

  defp map_telemetry_data(packet), do: packet

  @spec map_format_field(map()) :: map()
  defp map_format_field(%{data_extended: %{format: format}} = packet) do
    Map.put(packet, :format, format)
  end

  defp map_format_field(%{format: _format} = packet), do: packet

  @spec map_symbol_fields(map()) :: map()
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
  def parse_datatype("#DFS" <> _rest), do: :df_report
  def parse_datatype("#PHG" <> _rest), do: :phg_data
  def parse_datatype("#" <> _rest), do: :phg_data

  def parse_datatype(<<first_char::binary-size(1), _::binary>> = data) when is_binary(data) do
    Map.get(@datatype_map, first_char, :unknown_datatype)
  end

  def parse_datatype(_), do: :unknown_datatype

  @spec parse_data(atom(), String.t(), String.t()) :: map() | nil
  def parse_data(:empty, _destination, _data), do: %{data_type: :empty}
  def parse_data(:mic_e, destination, data), do: MicE.parse(data, strip_ssid(destination), :mic_e)
  def parse_data(:mic_e_old, destination, data), do: MicE.parse(data, strip_ssid(destination), :mic_e_old)
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
      {:ok, nmea_result} ->
        %{
          data_type: :nmea,
          format: "nmea",
          latitude: nmea_result.latitude,
          longitude: nmea_result.longitude,
          speed: nmea_result[:speed],
          course: nmea_result[:course],
          symbol_table_id: "/",
          symbol_code: "/",
          position_ambiguity: 0,
          has_position: true
        }

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
    case Regex.run(~r/^:([^:]+):(.*?)(\{(\d+)\})?$/s, data) do
      [_, addressee, message_text, _full_ack, message_number] ->
        trimmed_text = String.trim(message_text)

        %{
          data_type: classify_message_type(trimmed_text),
          addressee: String.trim(addressee),
          message_text: trimmed_text,
          message: trimmed_text,
          message_number: message_number
        }

      [_, addressee, message_text] ->
        trimmed_text = String.trim(message_text)

        %{
          data_type: classify_message_type(trimmed_text),
          addressee: String.trim(addressee),
          message_text: trimmed_text,
          message: trimmed_text
        }

      _ ->
        %{
          data_type: :message,
          addressee: nil,
          message: nil,
          error: "Failed to parse message format"
        }
    end
  end

  def parse_data(:position, destination, <<"!", rest::binary>>) do
    parse_data(:position, destination, rest)
  end

  def parse_data(:position, _destination, <<"/", _::binary>> = data) do
    data
    |> parse_position_without_timestamp()
    |> handle_position_with_timestamp_result()
  end

  def parse_data(:position, _destination, data) do
    data
    |> parse_position_without_timestamp()
    |> handle_position_result(:position)
  end

  def parse_data(:position_with_message, _destination, data) do
    data
    |> parse_position_with_message_without_timestamp()
    |> Map.put(:data_type, :position_with_message)
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

  # Telemetry definition messages (PARM, UNIT, EQNS, BITS) are typed as telemetry-message by FAP
  @spec classify_message_type(String.t()) :: :telemetry_message | :message
  defp classify_message_type(<<"PARM.", _::binary>>), do: :telemetry_message
  defp classify_message_type(<<"UNIT.", _::binary>>), do: :telemetry_message
  defp classify_message_type(<<"EQNS.", _::binary>>), do: :telemetry_message
  defp classify_message_type(<<"BITS.", _::binary>>), do: :telemetry_message
  defp classify_message_type(_), do: :message

  @spec handle_position_result(map(), atom()) :: map()
  defp handle_position_result(%{data_type: :malformed_position} = result, _data_type), do: result
  defp handle_position_result(result, data_type), do: Map.put(result, :data_type, data_type)

  @spec handle_position_with_timestamp_result(map()) :: map()
  defp handle_position_with_timestamp_result(%{data_type: :malformed_position} = result), do: result
  defp handle_position_with_timestamp_result(result), do: Map.put(result, :data_type, :position)

  @spec add_has_location(map()) :: map()
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

    Map.merge(
      %{
        latitude: pos.latitude,
        longitude: pos.longitude,
        timestamp: time,
        symbol_table_id: sym_table_id,
        symbol_code: symbol_code,
        weather: weather_data_without_timestamp,
        data_type: :weather,
        aprs_messaging?: aprs_messaging?
      },
      weather_data_without_timestamp
    )
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

  # Helper to extract altitude from comment field (e.g., "/A=000680" or "/A=-00088")
  @spec extract_altitude_and_clean_comment(String.t()) :: {float() | nil, String.t()}
  defp extract_altitude_and_clean_comment(comment) do
    # Use negative lookahead (?!\d) to ensure exactly 5-6 digits, not more
    case Regex.run(~r"/([Aa])=(-?\d{5,6})(?!\d)", comment) do
      [full_match, case_letter, altitude_str] ->
        altitude = String.to_integer(altitude_str) * 1.0

        # Validate altitude is within reasonable range
        # Valid range: -10,000 to 500,000 feet
        # (Dead Sea to high-altitude balloons/low satellites)
        validated_altitude =
          cond do
            altitude < -10_000.0 -> nil
            altitude > 500_000.0 -> nil
            true -> altitude
          end

        cleaned_comment =
          if case_letter == "a" do
            # lowercase /a= - keep a=NNNNNN in comment (FAP-compatible)
            comment |> String.replace(full_match, "a=" <> altitude_str) |> String.trim()
          else
            # uppercase /A= - strip entirely from comment
            comment |> String.replace(full_match, "") |> strip_leading_slash() |> String.trim()
          end

        {validated_altitude, cleaned_comment}

      _ ->
        {nil, comment}
    end
  end

  @spec strip_leading_slash(String.t()) :: String.t()
  defp strip_leading_slash(<<"/", rest::binary>>), do: rest
  defp strip_leading_slash(comment), do: comment

  # Strip SSID from callsign (FAP.pm: $dstcallsign =~ s/-\d+$//;)
  @spec strip_ssid(String.t() | nil) :: String.t() | nil
  defp strip_ssid(nil), do: nil

  defp strip_ssid(callsign) do
    case Regex.run(~r/^(.+)-\d+$/, callsign) do
      [_, base] -> base
      _ -> callsign
    end
  end

  # Strip leading / or space from comment (FAP.pm line 1211: $rest =~ s/^[\/\s]//;)
  @spec strip_leading_delimiter(String.t()) :: String.t()
  defp strip_leading_delimiter(<<"/", rest::binary>>), do: rest
  defp strip_leading_delimiter(<<" ", rest::binary>>), do: rest
  defp strip_leading_delimiter(comment), do: comment

  # Extract APRS data extension from the start of comment.
  # FAP.pm processes Course/Speed OR PHG OR RNG as mutually exclusive,
  # all anchored to the start of the comment text.
  @spec extract_data_extension(String.t()) ::
          {integer() | nil, float() | nil, String.t() | nil, String.t() | nil, String.t()}
  defp extract_data_extension(comment) do
    cond do
      # Course/Speed: NNN/NNN at start (7 chars)
      match = Regex.run(~r/^([0-9. ]{3})\/([0-9. ]{3})/, comment) ->
        [full_match, course_str, speed_str] = match
        rest = binary_part(comment, byte_size(full_match), byte_size(comment) - byte_size(full_match))
        course = parse_course_value(course_str)

        speed =
          if Regex.match?(~r/^\d{3}$/, speed_str),
            do: String.to_integer(speed_str) * 1.0

        {course, speed, nil, nil, rest}

      # PHGR: PHG + 4 chars + rate char + / (8 chars stripped)
      Regex.match?(~r/^PHG\d[\x30-\x7e]\d\d[0-9A-Z]\//, comment) ->
        phg_string = binary_part(comment, 3, 4)
        rest = binary_part(comment, 8, byte_size(comment) - 8)
        {nil, nil, phg_string, nil, rest}

      # PHG: PHG + 4 chars (7 chars stripped)
      Regex.match?(~r/^PHG\d[\x30-\x7e]\d\d/, comment) ->
        phg_string = binary_part(comment, 3, 4)
        rest = binary_part(comment, 7, byte_size(comment) - 7)
        {nil, nil, phg_string, nil, rest}

      # RNG: RNG + 4 digits (7 chars stripped)
      match = Regex.run(~r/^RNG(\d{4})/, comment) ->
        [_full, range_digits] = match
        range_miles = String.to_integer(range_digits)
        rest = binary_part(comment, 7, byte_size(comment) - 7)
        {nil, nil, nil, Integer.to_string(range_miles), rest}

      true ->
        {nil, nil, nil, nil, comment}
    end
  end

  @spec parse_course_value(String.t()) :: non_neg_integer()
  defp parse_course_value(course_str) do
    if Regex.match?(~r/^\d{3}$/, course_str) do
      c = String.to_integer(course_str)
      if c >= 1 and c <= 360, do: c, else: 0
    else
      0
    end
  end

  # Helper to extract PHG data from comment
  # PHG format: PHG followed by 4+ digits, optionally followed by /
  @spec extract_phg_data(String.t()) :: {map() | nil, String.t()}
  defp extract_phg_data(comment) do
    case Regex.run(~r"PHG(\d)(\d)(\d)(\d)(?:\d+/)?\s?", comment) do
      [full_match, p, h, g, d] ->
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

        cleaned_comment = comment |> String.replace(full_match, "") |> String.trim()
        {phg_map, cleaned_comment}

      _ ->
        {nil, comment}
    end
  end

  # Helper to extract PHG string from comment (for compatibility)
  # Returns exactly 4 PHG digits matching FAP behavior
  @spec extract_phg_string(String.t()) :: String.t() | nil
  defp extract_phg_string(comment) do
    case Regex.run(~r"PHG(\d{4})", comment) do
      [_, phg_digits] -> phg_digits
      _ -> nil
    end
  end

  # Strip weather parameters from a comment string, returning only the non-weather part.
  # Matches FAP.pm _wx_parse behavior:
  # - Initial wind/gust/temp pattern is front-anchored
  # - Secondary fields use non-anchored first-match-only replacement (Perl s/...//)
  @spec strip_weather_from_comment(String.t()) :: String.t()
  defp strip_weather_from_comment(comment) do
    comment
    |> strip_weather_initial_match()
    |> strip_weather_secondary_fields()
    |> strip_weather_nodata_patterns()
    |> String.trim()
  end

  # Front-anchored initial match: wind direction/speed + gust + temp (FAP lines 2115-2131)
  @spec strip_weather_initial_match(String.t()) :: String.t()
  defp strip_weather_initial_match(s) do
    cond do
      # _NNN/NNNgNNNtNNN or cNNNsNNNgNNNtNNN
      m = Regex.run(~r/^_{0,1}([\d .\-]{3})\/([\d .]{3})g([\d .]+)t(-?\d{1,3}|\.{2,3})/, s) ->
        binary_part(s, byte_size(hd(m)), byte_size(s) - byte_size(hd(m)))

      m = Regex.run(~r/^_{0,1}c([\d .\-]{3})s([\d .]{3})g([\d .]+)t(-?\d{1,3}|\.{2,3})/, s) ->
        binary_part(s, byte_size(hd(m)), byte_size(s) - byte_size(hd(m)))

      # wind + temp (no gust)
      m = Regex.run(~r/^_{0,1}([\d .\-]{3})\/([\d .]{3})t(-?\d{1,3}|\.{2,3})/, s) ->
        binary_part(s, byte_size(hd(m)), byte_size(s) - byte_size(hd(m)))

      # wind + gust (no temp)
      m = Regex.run(~r/^_{0,1}([\d .\-]{3})\/([\d .]{3})g([\d .]+)/, s) ->
        binary_part(s, byte_size(hd(m)), byte_size(s) - byte_size(hd(m)))

      # gust + temp only (no wind direction/speed prefix)
      m = Regex.run(~r/^g(\d+)t(-?\d{1,3}|\.{2,3})/, s) ->
        binary_part(s, byte_size(hd(m)), byte_size(s) - byte_size(hd(m)))

      true ->
        s
    end
  end

  # Non-anchored first-match-only replacement for secondary weather fields
  # (FAP lines 2133-2178). Each field replaced at most once (no global flag).
  @weather_secondary_patterns [
    ~r/t(-?\d{1,3})/,
    ~r/r(\d{1,3})/,
    ~r/p(\d{1,3})/,
    ~r/P(\d{1,3})/,
    ~r/h(\d{1,3})/,
    ~r/b(\d{4,5})/,
    ~r/[lL](\d{1,3})/,
    ~r/v([\-+]?\d+)/,
    ~r/s(\d{1,3})/,
    ~r/#(\d+)/
  ]

  @spec strip_weather_secondary_fields(String.t()) :: String.t()
  defp strip_weather_secondary_fields(s) do
    Enum.reduce(@weather_secondary_patterns, s, fn pattern, acc ->
      String.replace(acc, pattern, "", global: false)
    end)
  end

  # Strip remaining no-data patterns like "r..." "P..." (FAP line 2180)
  @spec strip_weather_nodata_patterns(String.t()) :: String.t()
  defp strip_weather_nodata_patterns(s) do
    String.replace(s, ~r/^([rPphblLs#][\. ]{1,5})+/, "")
  end

  # Patch parse_position_without_timestamp to include course/speed
  @spec parse_position_without_timestamp(String.t()) :: map() | nil
  def parse_position_without_timestamp(
        <<latitude::binary-size(8), sym_table_id::binary-size(1), longitude::binary-size(9), symbol_code::binary-size(1),
          comment::binary>> = position_data
      ) do
    if valid_aprs_coordinate?(latitude, longitude) do
      parse_position_uncompressed(latitude, sym_table_id, longitude, symbol_code, comment)
    else
      try_parse_compressed_without_prefix(position_data)
    end
  end

  def parse_position_without_timestamp(
        <<latitude::binary-size(8), sym_table_id::binary-size(1), longitude::binary-size(9)>> = position_data
      ) do
    if valid_aprs_coordinate?(latitude, longitude) do
      parse_position_short_uncompressed(latitude, sym_table_id, longitude)
    else
      try_parse_compressed_without_prefix(position_data)
    end
  end

  # Try compressed position for data >= 13 bytes that didn't match uncompressed patterns
  def parse_position_without_timestamp(position_data) when byte_size(position_data) >= 13 do
    try_parse_compressed_without_prefix(position_data)
  end

  def parse_position_without_timestamp(_invalid_data) do
    %{data_type: :malformed_position, error: "Invalid position format"}
  end

  # Helper function to validate APRS coordinates using binary pattern matching
  @spec valid_aprs_coordinate?(String.t(), String.t()) :: boolean()
  defp valid_aprs_coordinate?(lat, lon) do
    lat_valid = valid_latitude_format?(lat)
    lon_valid = valid_longitude_format?(lon)
    lat_valid and lon_valid
  end

  # Accept digits and spaces in minute/fraction positions (APRS position ambiguity)
  # FAP regex: (\d{2})([0-7 ][0-9 ]\.[0-9 ]{2})([NnSs])
  @spec valid_latitude_format?(binary()) :: boolean()
  defp valid_latitude_format?(<<d1::8, d2::8, m1::8, m2::8, ?., f1::8, f2::8, dir::8>>)
       when is_digit(d1) and is_digit(d2) and is_minute_tens(m1) and is_digit_or_space(m2) and is_digit_or_space(f1) and
              is_digit_or_space(f2) and dir in [?N, ?S] do
    true
  end

  defp valid_latitude_format?(_), do: false

  # FAP regex: (\d{3})([0-7 ][0-9 ]\.[0-9 ]{2})([EeWw])
  @spec valid_longitude_format?(binary()) :: boolean()
  defp valid_longitude_format?(<<d1::8, d2::8, d3::8, m1::8, m2::8, ?., f1::8, f2::8, dir::8>>)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_minute_tens(m1) and is_digit_or_space(m2) and
              is_digit_or_space(f1) and is_digit_or_space(f2) and dir in [?E, ?W] do
    true
  end

  defp valid_longitude_format?(_), do: false

  # Helper function to try parsing as compressed position without "/" prefix
  @spec try_parse_compressed_without_prefix(binary()) :: map()
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
          # No real course/speed
          "",
          # No compression type
          " ",
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

      # Alternate symbol table compressed format with cs + compression type
      <<sym_table_id::binary-size(1), latitude_compressed::binary-size(4), longitude_compressed::binary-size(4),
        symbol_code::binary-size(1), cs::binary-size(2), compression_type::binary-size(1), comment::binary>>
      when byte_size(position_data) >= 13 and sym_table_id != <<"/">> and
             sym_table_id >= <<"!">> and sym_table_id <= <<"~">> ->
        parse_position_compressed_with_full_data(
          sym_table_id,
          latitude_compressed,
          longitude_compressed,
          symbol_code,
          cs,
          compression_type,
          comment
        )

      # No symbol-table prefix (byte 0 outside `!`..`~`): the leading byte
      # cannot be valid base91, so this always fails compressed lat decoding.
      <<_::binary-size(4), _::binary-size(4), _::binary-size(1), _::binary-size(2), _::binary-size(1), _::binary>>
      when byte_size(position_data) >= 13 ->
        %{
          data_type: :position_error,
          error_message: "Invalid compressed location",
          has_position: false
        }
    end
  end

  @spec parse_position_uncompressed(String.t(), String.t(), String.t(), String.t(), String.t()) :: map()
  defp parse_position_uncompressed(latitude, sym_table_id, longitude, symbol_code, comment) do
    %{latitude: lat, longitude: lon, ambiguity: ambiguity} = parse_aprs_position(latitude, longitude)

    # FAP.pm order: Course/Speed OR PHG OR RNG (mutually exclusive, from start)
    {course, speed, phg_string, radiorange, comment_after_ext} =
      extract_data_extension(comment)

    # Then altitude (anywhere in comment)
    {altitude, comment_after_alt} = extract_altitude_and_clean_comment(comment_after_ext)

    # Then comment telemetry |...|
    {_telemetry, comment_after_telemetry} =
      Aprs.TelemetryFromComment.extract_telemetry_from_comment(comment_after_alt)

    # Then DAO !XYZ!
    {dao_data, comment_after_dao} = parse_dao_extension(comment_after_telemetry)

    # Strip leading / or space (FAP line 1211)
    comment_cleaned = comment_after_dao |> strip_leading_delimiter() |> String.trim()

    has_position = valid_coordinate?(lat) and valid_coordinate?(lon)
    posresolution = Aprs.UtilityHelpers.calculate_position_resolution(ambiguity)

    base_map = %{
      latitude: lat,
      longitude: lon,
      timestamp: nil,
      symbol_table_id: sym_table_id,
      symbol_code: symbol_code,
      comment: comment_cleaned,
      altitude: altitude,
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
      posambiguity: ambiguity,
      messaging: 0,
      radiorange: radiorange,
      wx: nil
    }

    # Check if this is a weather packet and merge accordingly
    merge_weather_if_present(base_map, sym_table_id, symbol_code, comment)
  end

  @spec parse_position_short_uncompressed(String.t(), String.t(), String.t()) :: map()
  defp parse_position_short_uncompressed(latitude, sym_table_id, longitude) do
    %{latitude: lat, longitude: lon, ambiguity: ambiguity} = parse_aprs_position(latitude, longitude)

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

  @spec parse_position_compressed_with_full_data(
          String.t(),
          binary(),
          binary(),
          String.t(),
          binary(),
          binary(),
          String.t()
        ) :: map()
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

        # FAP only strips telemetry for non-weather compressed positions
        # (via _comments_to_decimal). Weather packets go through _wx_parse which
        # does NOT strip telemetry.
        {telemetry, comment_for_processing} =
          if symbol_code == "_" do
            # Weather packet: extract telemetry values but keep text in comment
            {telemetry_data, _} = Aprs.TelemetryFromComment.extract_telemetry_from_comment(comment)
            {telemetry_data, comment}
          else
            Aprs.TelemetryFromComment.extract_telemetry_from_comment(comment)
          end

        # Parse DAO extension from comment
        {dao_data, cleaned_comment_after_dao} = parse_dao_extension(comment_for_processing)

        # Extract altitude and PHG from compressed position comment
        {altitude, cleaned_comment_after_alt} = extract_altitude_and_clean_comment(cleaned_comment_after_dao)
        {_phg_data, cleaned_comment_after_phg} = extract_phg_data(cleaned_comment_after_alt)
        phg_string = extract_phg_string(cleaned_comment_after_alt)
        cleaned_comment_after_dao = cleaned_comment_after_phg

        posresolution = Aprs.UtilityHelpers.calculate_compressed_position_resolution()

        base_data = %{
          latitude: converted_lat,
          longitude: converted_lon,
          symbol_table_id: sym_table_id,
          symbol_code: symbol_code,
          comment: String.trim(cleaned_comment_after_dao),
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
          posambiguity: ambiguity,
          messaging: compression_info.aprs_messaging,
          altitude: altitude,
          phg: phg_string
        }

        base_data =
          if telemetry == nil do
            base_data
          else
            Map.put(base_data, :telemetry, telemetry)
          end

        # Add course and speed if available
        base_data = Map.merge(base_data, compressed_cs)

        # Merge weather data for weather station symbol
        merge_weather_if_present(base_data, sym_table_id, symbol_code, cleaned_comment_after_dao)

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
    end
  end

  # Patch parse_position_with_message_without_timestamp to propagate course/speed
  @spec parse_position_with_message_without_timestamp(String.t()) :: map()
  def parse_position_with_message_without_timestamp(position_data) do
    position_data
    |> parse_position_without_timestamp()
    |> Map.put(:aprs_messaging?, true)
  end

  # Patch parse_position_with_timestamp to extract course/speed from comment
  @spec parse_position_with_timestamp(boolean(), binary(), atom()) :: map()
  def parse_position_with_timestamp(
        aprs_messaging?,
        <<time::binary-size(7), latitude::binary-size(8), sym_table_id::binary-size(1), longitude::binary-size(9),
          symbol_code::binary-size(1), comment::binary>>,
        data_type
      ) do
    if valid_aprs_coordinate?(latitude, longitude) do
      build_position_result(aprs_messaging?, latitude, longitude, time, sym_table_id, symbol_code, comment, data_type)
    else
      handle_invalid_position_data(
        aprs_messaging?,
        time,
        latitude,
        sym_table_id,
        longitude,
        symbol_code,
        comment,
        data_type
      )
    end
  end

  def parse_position_with_timestamp(_aprs_messaging?, _data, _data_type) do
    %{
      data_type: :timestamped_position_error,
      error: "Invalid timestamped position format"
    }
  end

  @spec handle_invalid_position_data(boolean(), binary(), binary(), binary(), binary(), binary(), binary(), atom()) ::
          map()
  defp handle_invalid_position_data(
         aprs_messaging?,
         time,
         latitude,
         sym_table_id,
         longitude,
         symbol_code,
         comment,
         data_type
       ) do
    position_data = latitude <> sym_table_id <> longitude <> symbol_code <> comment

    # Try compressed position first (13+ bytes starting with symbol table char)
    case try_compressed_timestamped(position_data, aprs_messaging?, time, data_type) do
      {:ok, result} ->
        result

      :error ->
        # Fallback: try to extract lat/lon using regex
        try_regex_position_fallback(aprs_messaging?, time, position_data)
    end
  end

  @spec try_compressed_timestamped(binary(), boolean(), binary(), atom()) :: {:ok, map()} | :error
  defp try_compressed_timestamped(position_data, aprs_messaging?, time, data_type) do
    compressed_result = try_parse_compressed_without_prefix(position_data)

    case compressed_result do
      %{data_type: type} when type in [:malformed_position, :position_error] ->
        :error

      %{latitude: lat, longitude: lon} = result when is_number(lat) and is_number(lon) ->
        unix_timestamp = Aprs.UtilityHelpers.validate_timestamp(time)

        {:ok,
         result
         |> Map.put(:timestamp, unix_timestamp)
         |> Map.put(:time, unix_timestamp)
         |> Map.put(:aprs_messaging?, aprs_messaging?)
         |> Map.put(:data_type, data_type)
         |> Map.put(:messaging, if(aprs_messaging?, do: 1, else: 0))}
    end
  end

  @spec try_regex_position_fallback(boolean(), String.t(), String.t()) :: map()
  defp try_regex_position_fallback(aprs_messaging?, time, raw_data) do
    regex =
      ~r/^(?<lat>\d{4,5}\.\d+[NS])(?<sym_table>.)(?<lon>\d{5,6}\.\d+[EW])(?<sym_code>.)(?<comment>.*)$/

    case Regex.named_captures(regex, raw_data) do
      %{
        "lat" => lat,
        "lon" => lon,
        "sym_table" => sym_table,
        "sym_code" => sym_code,
        "comment" => comment
      } ->
        build_fallback_position_result(aprs_messaging?, lat, lon, time, sym_table, sym_code, comment)

      _ ->
        %{
          data_type: :timestamped_position_error,
          error: "Invalid timestamped position format",
          raw_data: time <> raw_data
        }
    end
  end

  @spec build_fallback_position_result(boolean(), String.t(), String.t(), String.t(), String.t(), String.t(), String.t()) ::
          map()
  defp build_fallback_position_result(aprs_messaging?, lat, lon, time, sym_table, sym_code, comment) do
    pos = parse_aprs_position(lat, lon)
    ambiguity = Map.get(pos, :ambiguity, 0)

    # FAP.pm order: data extension → altitude → telemetry → DAO → leading delimiter
    {course, speed, phg_string, radiorange, comment_after_ext} = extract_data_extension(comment)
    {altitude, comment_after_alt} = extract_altitude_and_clean_comment(comment_after_ext)

    {_telemetry, comment_after_telemetry} =
      Aprs.TelemetryFromComment.extract_telemetry_from_comment(comment_after_alt)

    {_dao_data, comment_after_dao} = parse_dao_extension(comment_after_telemetry)
    comment_cleaned = comment_after_dao |> strip_leading_delimiter() |> String.trim()

    base_map = %{
      latitude: pos.latitude,
      longitude: pos.longitude,
      time: time,
      timestamp: time,
      symbol_table_id: sym_table,
      symbol_code: sym_code,
      comment: comment_cleaned,
      aprs_messaging?: aprs_messaging?,
      compressed?: false,
      altitude: altitude,
      phg: phg_string,
      radiorange: radiorange,
      course: course,
      speed: speed,
      position_ambiguity: ambiguity,
      posambiguity: ambiguity
    }

    merge_weather_if_present(base_map, sym_table, sym_code, comment)
  end

  @spec build_position_result(boolean(), String.t(), String.t(), String.t(), String.t(), String.t(), String.t(), atom()) ::
          map()
  defp build_position_result(aprs_messaging?, lat, lon, time, sym_table_id, symbol_code, comment, data_type) do
    position = parse_aprs_position(lat, lon)

    ambiguity = Map.get(position, :ambiguity, 0)
    unix_timestamp = Aprs.UtilityHelpers.validate_timestamp(time)

    # FAP.pm order: data extension → altitude → telemetry → DAO → leading delimiter
    {course, speed, phg_string, radiorange, comment_after_ext} = extract_data_extension(comment)
    {altitude, comment_after_alt} = extract_altitude_and_clean_comment(comment_after_ext)

    {_telemetry, comment_after_telemetry} =
      Aprs.TelemetryFromComment.extract_telemetry_from_comment(comment_after_alt)

    {dao_data, comment_after_dao} = parse_dao_extension(comment_after_telemetry)
    comment_cleaned = comment_after_dao |> strip_leading_delimiter() |> String.trim()

    posresolution = Aprs.UtilityHelpers.calculate_position_resolution(ambiguity)

    base_map = %{
      latitude: position.latitude,
      longitude: position.longitude,
      position: position,
      time: unix_timestamp,
      timestamp: unix_timestamp,
      symbol_table_id: sym_table_id,
      symbol_code: symbol_code,
      comment: comment_cleaned,
      aprs_messaging?: aprs_messaging?,
      compressed?: false,
      course: course,
      speed: speed,
      altitude: altitude,
      phg: phg_string,
      radiorange: radiorange,
      dao: dao_data,
      data_type: data_type,
      format: "uncompressed",
      messaging: if(aprs_messaging?, do: 1, else: 0),
      position_ambiguity: ambiguity,
      posambiguity: ambiguity,
      posresolution: posresolution
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
    parse_third_party_with_depth_check(packet, Aprs.UtilityHelpers.count_leading_braces(packet))
  end

  @spec parse_third_party_with_depth_check(String.t(), integer()) :: map()
  defp parse_third_party_with_depth_check(_packet, depth) when depth + 1 > 3 do
    %{error: "Maximum tunnel depth exceeded"}
  end

  defp parse_third_party_with_depth_check(packet, _depth) do
    case parse_tunneled_packet(packet) do
      {:ok, parsed_packet} ->
        build_third_party_traffic_result(packet, parsed_packet)

      {:error, reason} ->
        %{error: reason}
    end
  end

  @spec build_third_party_traffic_result(String.t(), map()) :: map()
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

  @spec parse_tunneled_packet_with_header(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  defp parse_tunneled_packet_with_header(header, information) do
    case parse_tunneled_header(header) do
      {:ok, header_data} ->
        parse_tunneled_packet_with_information(header_data, information)

      {:error, reason} ->
        {:error, "Invalid header: #{reason}"}
    end
  end

  @spec parse_tunneled_packet_with_information(map(), String.t()) :: {:ok, map()}
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

  @spec parse_sender_and_path(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  defp parse_sender_and_path(sender, path) do
    case parse_callsign(sender) do
      {:ok, callsign_parts} ->
        base_callsign = List.first(callsign_parts)
        ssid = List.last(callsign_parts)
        {:ok, [destination, digi_path]} = split_path(path)

        {:ok,
         %{
           sender: sender,
           base_callsign: base_callsign,
           ssid: ssid,
           destination: destination,
           digi_path: digi_path
         }}

      {:error, reason} ->
        {:error, "Invalid callsign: #{reason}"}
    end
  end

  # Add network tunneling support
  @spec parse_network_tunnel(String.t()) :: {:ok, map()} | {:error, String.t()}
  defp parse_network_tunnel(packet) do
    # Network tunneling packets start with "}" and contain a complete APRS packet
    tunneled_packet = String.slice(packet, 1..-1//1)

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

  # Add support for multiple levels of tunneling
  @spec parse_nested_tunnel(String.t(), non_neg_integer()) :: {:ok, map()} | {:error, String.t()}
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

  @spec handle_parsed_network_tunnel(map(), non_neg_integer()) :: {:ok, map()}
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

    case Regex.run(~r/!([A-Za-z])([\x21-\x7b])([\x21-\x7b])!/, comment) do
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
  @spec valid_coordinate?(float() | nil) :: boolean()
  defp valid_coordinate?(coord) do
    is_number(coord)
  end

  # Weather merging for position packets.
  # Position packets with the `_` weather symbol (any symbol table, including overlays)
  # get weather data extracted. The data_type is NOT changed here.
  @spec merge_weather_if_present(map(), String.t(), String.t(), String.t()) :: map()
  defp merge_weather_if_present(base_map, _sym_table_id, "_", comment) do
    weather_data = Weather.parse_weather_data(comment)
    weather_data_without_timestamp = Map.delete(weather_data, :timestamp)
    cleaned_comment = strip_weather_from_comment(comment)

    base_map
    |> Map.put(:weather, weather_data_without_timestamp)
    |> Map.put(:wx, Map.get(weather_data_without_timestamp, :wx, weather_data_without_timestamp))
    |> Map.put(:comment, cleaned_comment)
  end

  defp merge_weather_if_present(base_map, _sym_table_id, _symbol_code, _comment), do: base_map
end
