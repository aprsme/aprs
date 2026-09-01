defmodule Aprs do
  @moduledoc """
  Main APRS packet parsing library.

  `parse/1` accepts a TNC2-format packet (`SRC>DST,PATH:information`) and
  returns `{:ok, map}` or `{:error, reason}`.

  ## Units

  Every packet format reports the same units, so a caller does not have to know
  how a packet happened to encode a value:

    * `speed` - knots, float
    * `altitude` - feet, float
    * `course` - degrees, integer; 360 is due north, 0 (or absent) is unknown
    * `posresolution` - metres, float
  """

  import Aprs.Guards

  alias Aprs.CompressedPositionHelpers
  alias Aprs.DAO
  alias Aprs.Item
  alias Aprs.MicE
  alias Aprs.Object
  alias Aprs.PHG
  alias Aprs.PHGHelpers
  alias Aprs.Status
  alias Aprs.Telemetry
  alias Aprs.TelemetryFromComment
  alias Aprs.UtilityHelpers
  alias Aprs.Weather

  @version "1.0.1"

  @max_packet_size 8192

  # APRS101: the `!` data type indicator may appear anywhere in the first 40
  # bytes of the information field, preceded by free text from old TNCs.
  @legacy_position_scan_limit 40

  @doc """
  Returns the current version of the APRS library as a static string.
  """
  @spec version() :: String.t()
  def version, do: @version

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
          optional(:timestamp) => String.t() | integer() | nil,
          optional(:symbol_table_id) => String.t() | nil,
          optional(:symbol_code) => String.t() | nil,
          optional(:comment) => String.t(),
          optional(:altitude) => float() | nil,
          optional(:phg) => String.t() | nil,
          optional(:aprs_messaging?) => boolean(),
          optional(:compressed?) => boolean(),
          optional(:position_ambiguity) => position_ambiguity(),
          optional(:dao) => map() | nil,
          optional(:course) => integer() | nil,
          optional(:speed) => float() | nil,
          optional(:has_position) => boolean(),
          optional(:data_type) => atom()
        }

  @spec parse(term()) :: parse_result()
  def parse(message) when is_binary(message) do
    if byte_size(message) > @max_packet_size do
      {:error, :packet_too_large}
    else
      message |> scrub_encoding() |> do_parse()
    end
  end

  def parse(_), do: {:error, :invalid_packet}

  # A packet is normally valid UTF-8. When it is not, the bad bytes are nearly
  # always Latin-1 from a radio, so decode them as Latin-1 rather than replacing
  # every non-ASCII byte in the packet.
  @spec scrub_encoding(binary()) :: String.t()
  defp scrub_encoding(message) do
    if String.valid?(message), do: message, else: scrub(message, <<>>)
  end

  @spec scrub(binary(), binary()) :: String.t()
  defp scrub(<<>>, acc), do: acc
  defp scrub(<<c::utf8, rest::binary>>, acc), do: scrub(rest, <<acc::binary, c::utf8>>)
  defp scrub(<<b, rest::binary>>, acc), do: scrub(rest, <<acc::binary, b::utf8>>)

  @spec do_parse(String.t()) :: parse_result()
  defp do_parse(message) do
    with {:ok, [sender, path, data]} <- split_packet(message),
         {:ok, callsign_parts} <- parse_callsign(sender),
         {:ok, [destination, digi_path]} <- split_path(path),
         :ok <- validate_digi_path(digi_path),
         data_trimmed = strip_trailing_control(data),
         {data_type, data_for_parsing} = resolve_datatype(data_trimmed),
         :ok <- validate_packet_parts(destination, sender, data_type) do
      packet_data =
        build_packet_data(
          sender,
          digi_path,
          destination,
          data_trimmed,
          data_type,
          data_for_parsing,
          callsign_parts
        )

      {:ok, Map.merge(packet_data, %{resultcode: "success", resultmsg: "OK"})}
    else
      {:error, reason} -> {:error, format_error_message(reason)}
    end
  rescue
    exception ->
      {:error, "Parse exception: " <> Exception.message(exception)}
  end

  @spec format_error_message(term()) :: term()
  defp format_error_message(:invalid_packet), do: :invalid_packet
  defp format_error_message(reason), do: reason

  @spec validate_packet_parts(String.t(), String.t(), atom()) :: :ok | {:error, :invalid_packet}
  defp validate_packet_parts("", _, :empty), do: {:error, :invalid_packet}
  defp validate_packet_parts(_, _, _), do: :ok

  # An empty digipeater element (`APRS,,WIDE1-1`) is not a legal AX.25 path.
  @spec validate_digi_path(String.t()) :: :ok | {:error, :invalid_packet}
  defp validate_digi_path(""), do: :ok

  defp validate_digi_path(path) do
    if path |> String.split(",") |> Enum.any?(&(&1 == "")) do
      {:error, :invalid_packet}
    else
      :ok
    end
  end

  @spec build_packet_data(String.t(), String.t(), String.t(), String.t(), atom(), String.t(), [String.t()]) :: packet()
  defp build_packet_data(sender, path, destination, data, data_type, data_for_parsing, callsign_parts) do
    data_extended = parse_data(data_type, destination, prepare_data_for_parsing(data_type, data_for_parsing))
    digipeaters = parse_digipeaters(path)
    final_data_type = determine_final_data_type(data_extended, data_type)
    header = sender <> ">" <> destination <> if(path == "", do: "", else: "," <> path)

    base_packet = %{
      id: generate_packet_id(),
      sender: sender,
      path: path,
      destination: destination,
      information_field: data,
      data_type: final_data_type,
      base_callsign: List.first(callsign_parts),
      ssid: extract_ssid(callsign_parts),
      data_extended: data_extended,
      received_at: timestamp_now(),
      # Standard APRS parser fields
      srccallsign: sender,
      dstcallsign: destination,
      body: data,
      origpacket: header <> ":" <> data,
      header: header,
      alive: 1,
      type: atom_to_standard_type(final_data_type),
      digipeaters: digipeaters,
      posambiguity: 0,
      format: :uncompressed,
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

    base_packet
    |> merge_data_extended(data_extended)
    |> map_fields_to_reference_format()
  end

  # A random prefix, drawn once per VM, followed by a counter. Ids are unique
  # for the life of the VM. Drawing random bytes for every packet took about a
  # microsecond, which is a large share of the cost of parsing a short packet.
  @spec generate_packet_id() :: String.t()
  defp generate_packet_id do
    packet_id_prefix() <> Integer.to_string(:erlang.unique_integer([:positive]), 16)
  end

  @spec packet_id_prefix() :: String.t()
  defp packet_id_prefix do
    case :persistent_term.get({__MODULE__, :id_prefix}, nil) do
      nil ->
        prefix = 8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
        :persistent_term.put({__MODULE__, :id_prefix}, prefix)
        prefix

      prefix ->
        prefix
    end
  end

  @spec extract_data_without_type(String.t()) :: String.t()
  defp extract_data_without_type(<<_first_char::binary-size(1), rest::binary>>), do: rest
  defp extract_data_without_type(_), do: ""

  @spec extract_ssid([String.t()]) :: String.t()
  defp extract_ssid(callsign_parts), do: List.last(callsign_parts)

  # Messages and items are parsed with their data type indicator in place.
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
    weather: "wx",
    object: "object",
    item: "item",
    message: "message",
    message_ack: "messageack",
    message_rej: "messagerej",
    telemetry_message: "telemetry-message",
    telemetry: "telemetry",
    status: "status",
    station_capabilities: "capabilities",
    maidenhead_grid: "location",
    mic_e: "location",
    mic_e_old: "location",
    mic_e_error: "location",
    malformed_position: "location",
    nmea: "location"
  }

  @spec atom_to_standard_type(atom()) :: String.t()
  defp atom_to_standard_type(type) do
    Map.get(@standard_type_map, type, Atom.to_string(type))
  end

  # Every digipeater at or before the last `*` has repeated the packet:
  # `WIDE1-1,WIDE2*` means WIDE1-1 was used too.
  @spec parse_digipeaters(String.t()) :: [map()]
  defp parse_digipeaters(""), do: []

  defp parse_digipeaters(path) do
    segments = String.split(path, ",")
    last_used = last_used_index(segments)

    segments
    |> Enum.with_index()
    |> Enum.map(fn {digi, index} -> parse_single_digipeater(digi, index <= last_used) end)
  end

  @spec last_used_index([String.t()]) :: integer()
  defp last_used_index(segments) do
    segments
    |> Enum.with_index()
    |> Enum.reduce(-1, fn {digi, index}, acc ->
      if String.ends_with?(digi, "*"), do: index, else: acc
    end)
  end

  @spec parse_single_digipeater(String.t(), boolean()) :: map()
  defp parse_single_digipeater(<<"q", _::binary-size(2)>> = digi, _used) do
    %{call: digi, wasdigied: 0}
  end

  defp parse_single_digipeater(digi, true) do
    %{call: String.trim_trailing(digi, "*"), wasdigied: 1}
  end

  defp parse_single_digipeater(digi, false) do
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
  defp map_telemetry_data(%{telemetry: telemetry_data} = packet) when is_map(telemetry_data) do
    Map.put(packet, :mbits, telemetry_data[:bits])
  end

  defp map_telemetry_data(packet), do: packet

  @spec map_format_field(map()) :: map()
  defp map_format_field(%{data_extended: %{format: format}} = packet) do
    Map.put(packet, :format, format)
  end

  defp map_format_field(packet), do: packet

  @spec map_symbol_fields(map()) :: map()
  defp map_symbol_fields(packet) do
    packet
    |> Map.put(:symbolcode, Map.get(packet, :symbol_code))
    |> Map.put(:symboltable, Map.get(packet, :symbol_table_id))
  end

  # Safely split packet into components using binary pattern matching
  @spec split_packet(String.t()) :: {:ok, [String.t()]} | {:error, :invalid_packet}
  def split_packet(message) do
    with {:ok, sender, rest} <- find_delimiter(message, ?>),
         {:ok, path, data} <- find_delimiter(rest, ?:) do
      {:ok, [sender, path, data]}
    else
      :error -> {:error, :invalid_packet}
    end
  end

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

  # Only line endings and NULs are stripped. A trailing space is significant:
  # in the compressed format it is the spec value for "no course/speed" and
  # "no compression type".
  @spec strip_trailing_control(binary()) :: binary()
  defp strip_trailing_control(<<>>), do: <<>>

  defp strip_trailing_control(binary) do
    size = byte_size(binary) - 1

    case binary do
      <<rest::binary-size(^size), c>> when c in [?\r, ?\n, 0] -> strip_trailing_control(rest)
      _ -> binary
    end
  end

  # Safely split path into destination and digipeater path
  @spec split_path(String.t()) :: {:ok, [String.t()]}
  def split_path(path) when is_binary(path) do
    path |> String.split(",", parts: 2) |> split_path_parts()
  end

  @spec split_path_parts([String.t()]) :: {:ok, [String.t()]}
  defp split_path_parts([destination, digi_path]), do: {:ok, [destination, digi_path]}
  defp split_path_parts([destination]), do: {:ok, [destination, ""]}

  @spec parse_datatype_safe(String.t()) :: {:ok, atom()}
  def parse_datatype_safe(data), do: {:ok, parse_datatype(data)}

  @spec parse_callsign(String.t()) :: {:ok, [String.t()]} | {:error, String.t() | atom()}
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
    "`" => :mic_e,
    "'" => :mic_e_old,
    <<0x1C>> => :mic_e,
    <<0x1D>> => :mic_e_old,
    "_" => :weather,
    "$" => :raw_gps_ultimeter,
    "<" => :station_capabilities,
    "?" => :query,
    "{" => :user_defined,
    "}" => :third_party_traffic,
    ")" => :item,
    "%" => :agrelo_dfjr,
    "[" => :maidenhead_grid,
    "#" => :peet_logging,
    "*" => :peet_logging,
    "," => :invalid_test_data
  }

  @doc """
  Determine the data type of an information field.
  """
  @spec parse_datatype(String.t()) :: atom()
  def parse_datatype(data) when is_binary(data) do
    {data_type, _data} = resolve_datatype(data)
    data_type
  end

  def parse_datatype(_), do: :unknown_datatype

  # Returns the data type together with the information field the parser should
  # read, which differs from the packet body only for the legacy "`!` within the
  # first 40 bytes" position form.
  @spec resolve_datatype(String.t()) :: {atom(), String.t()}
  defp resolve_datatype(""), do: {:empty, ""}
  defp resolve_datatype(<<"T#", _::binary>> = data), do: {:telemetry, data}
  defp resolve_datatype(<<"#DFS", _::binary>> = data), do: {:df_report, data}
  defp resolve_datatype(<<"#PHG", _::binary>> = data), do: {:phg_data, data}

  defp resolve_datatype(<<first::binary-size(1), _::binary>> = data) do
    case Map.fetch(@datatype_map, first) do
      {:ok, data_type} -> {data_type, data}
      :error -> legacy_position_datatype(data)
    end
  end

  @spec legacy_position_datatype(String.t()) :: {atom(), String.t()}
  defp legacy_position_datatype(data) do
    case find_legacy_position(data, 0) do
      {:ok, pos} -> {:position, binary_part(data, pos, byte_size(data) - pos)}
      :error -> {:unknown_datatype, data}
    end
  end

  @spec find_legacy_position(binary(), non_neg_integer()) :: {:ok, non_neg_integer()} | :error
  defp find_legacy_position(_data, @legacy_position_scan_limit), do: :error
  defp find_legacy_position(<<?!, _::binary>>, pos), do: {:ok, pos}
  defp find_legacy_position(<<_, rest::binary>>, pos), do: find_legacy_position(rest, pos + 1)
  defp find_legacy_position(<<>>, _pos), do: :error

  @spec parse_data(atom(), String.t(), String.t()) :: map() | nil
  def parse_data(:empty, _destination, _data), do: %{data_type: :empty}
  def parse_data(:mic_e, destination, data), do: MicE.parse(data, strip_ssid(destination), :mic_e)
  def parse_data(:mic_e_old, destination, data), do: MicE.parse(data, strip_ssid(destination), :mic_e_old)
  def parse_data(:object, _destination, data), do: Object.parse(data)
  def parse_data(:item, _destination, data), do: Item.parse(data)
  def parse_data(:telemetry, _destination, data), do: Telemetry.parse(data)
  def parse_data(:status, _destination, data), do: Status.parse(data)
  def parse_data(:phg_data, _destination, data), do: PHG.parse(data)
  def parse_data(:peet_logging, _destination, data), do: Aprs.SpecialDataHelpers.parse_peet_logging(data)
  def parse_data(:invalid_test_data, _destination, data), do: Aprs.SpecialDataHelpers.parse_invalid_test_data(data)
  def parse_data(:agrelo_dfjr, _destination, data), do: %{data_type: :agrelo_dfjr, raw_data: data}
  def parse_data(:maidenhead_grid, _destination, data), do: parse_maidenhead(data)
  def parse_data(:station_capabilities, _destination, data), do: parse_station_capabilities(data)
  def parse_data(:query, _destination, data), do: parse_query(data)
  def parse_data(:user_defined, _destination, data), do: parse_user_defined(data)
  def parse_data(:third_party_traffic, _destination, data), do: parse_third_party_traffic(data)

  def parse_data(:weather, _destination, data) do
    weather = Weather.parse_weather_data(data)

    weather
    |> Map.put(:data_type, :weather)
    |> Map.put(:weather, weather)
    |> Map.put(:has_position, false)
  end

  def parse_data(:raw_gps_ultimeter, _destination, data) do
    case Aprs.NMEAHelpers.parse_nmea_sentence(data) do
      {:ok, nmea_result} ->
        nmea_position(nmea_result)

      {:error, error} ->
        %{data_type: :raw_gps_ultimeter, error: error, nmea_type: nil, raw_data: data, latitude: nil, longitude: nil}
    end
  end

  def parse_data(:df_report, _destination, <<"DFS", s, h, g, d, rest::binary>>) do
    {strength, _} = PHGHelpers.parse_df_strength(s)
    {height, _} = PHGHelpers.parse_phg_height(h)
    {gain, _} = PHGHelpers.parse_phg_gain(g)
    {directivity, _} = PHGHelpers.parse_phg_directivity(d)

    %{
      dfs: <<s, h, g, d>>,
      df_strength: strength,
      height: height,
      gain: gain,
      directivity: directivity,
      comment: rest,
      data_type: :df_report
    }
  end

  def parse_data(:df_report, _destination, data) do
    %{df_data: data, data_type: :df_report}
  end

  def parse_data(:message, _destination, <<":", rest::binary>>) do
    case split_addressee(rest) do
      {:ok, addressee, body} -> build_message(addressee, body)
      :error -> message_parse_error()
    end
  end

  def parse_data(:message, _destination, _data), do: message_parse_error()

  def parse_data(:position, _destination, data) do
    data
    |> parse_position_without_timestamp()
    |> handle_position_result(:position)
  end

  def parse_data(:position_with_message, _destination, data) do
    data
    |> parse_position_without_timestamp()
    |> Map.put(:aprs_messaging?, true)
    |> handle_position_result(:position_with_message)
  end

  def parse_data(:timestamped_position, _destination, data) do
    false
    |> parse_position_with_timestamp(data, :timestamped_position)
    |> add_has_position()
  end

  def parse_data(:timestamped_position_with_message, _destination, data) do
    true
    |> parse_position_with_timestamp(data, :timestamped_position_with_message)
    |> add_has_position()
  end

  # Catch-all for unknown or unsupported types
  def parse_data(_type, _destination, _data), do: nil

  @spec nmea_position(map()) :: map()
  defp nmea_position(nmea_result) do
    %{
      data_type: nmea_data_type(nmea_result[:nmea_type]),
      format: :nmea,
      nmea_type: nmea_result[:nmea_type],
      latitude: nmea_result[:latitude],
      longitude: nmea_result[:longitude],
      speed: nmea_result[:speed],
      course: nmea_result[:course],
      altitude: nmea_result[:altitude],
      symbol_table_id: "/",
      symbol_code: "/",
      position_ambiguity: 0,
      posresolution: UtilityHelpers.nmea_position_resolution(),
      has_position: is_number(nmea_result[:latitude]) and is_number(nmea_result[:longitude])
    }
    |> maybe_put(:weather, nmea_result[:weather])
    |> maybe_put(:wx, nmea_result[:weather])
    |> maybe_put(:waypoint_name, nmea_result[:waypoint_name])
  end

  # Peet Bros Ultimeter packets share the `$` data type indicator but are not
  # NMEA sentences and carry no position.
  @spec nmea_data_type(atom()) :: atom()
  defp nmea_data_type(:ultimeter), do: :raw_gps_ultimeter
  defp nmea_data_type(_), do: :nmea

  @spec maybe_put(map(), atom(), term()) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  ## Messages

  @spec message_parse_error() :: map()
  defp message_parse_error do
    %{data_type: :message, addressee: nil, message: nil, error: "Failed to parse message format"}
  end

  # The addressee field is nine bytes wide; tolerate shorter non-conformant
  # fields by falling back to the next colon.
  @spec split_addressee(String.t()) :: {:ok, String.t(), String.t()} | :error
  defp split_addressee(<<addressee::binary-size(9), ":", body::binary>>), do: {:ok, addressee, body}

  defp split_addressee(rest) do
    case find_delimiter(rest, ?:) do
      {:ok, addressee, body} -> {:ok, addressee, body}
      :error -> :error
    end
  end

  @spec build_message(String.t(), String.t()) :: map()
  defp build_message(addressee, body) do
    addressee = String.trim(addressee)

    case classify_message(body) do
      {:ack, id} ->
        %{
          data_type: :message_ack,
          addressee: addressee,
          message_number: id,
          messageack: id,
          message_text: body,
          message: body
        }

      {:rej, id} ->
        %{
          data_type: :message_rej,
          addressee: addressee,
          message_number: id,
          messagerej: id,
          message_text: body,
          message: body
        }

      {:telemetry, definition} ->
        Map.merge(definition, %{data_type: :telemetry_message, addressee: addressee, message_text: body, message: body})

      :message ->
        {text, number, reply_ack} = split_message_id(body)

        %{data_type: :message, addressee: addressee, message_text: text, message: text}
        |> maybe_put(:message_number, number)
        |> maybe_put(:message_ack, reply_ack)
    end
  end

  @spec classify_message(String.t()) :: {:ack, String.t()} | {:rej, String.t()} | {:telemetry, map()} | :message
  defp classify_message(<<"ack", rest::binary>>) do
    case parse_message_id(rest) do
      {:ok, id, _reply_ack} -> {:ack, id}
      :error -> :message
    end
  end

  defp classify_message(<<"rej", rest::binary>>) do
    case parse_message_id(rest) do
      {:ok, id, _reply_ack} -> {:rej, id}
      :error -> :message
    end
  end

  defp classify_message(body) do
    case Telemetry.parse_definition(body) do
      nil -> :message
      definition -> {:telemetry, Map.delete(definition, :data_type)}
    end
  end

  # Message id: `{` followed by 1-5 alphanumerics with no closing brace, or the
  # APRS 1.1 reply-ack form `{MM}AA`.
  @spec split_message_id(String.t()) :: {String.t(), String.t() | nil, String.t() | nil}
  defp split_message_id(body) do
    case last_brace_index(body, 0, :error) do
      {:ok, index} -> split_at_message_id(body, index)
      :error -> {body, nil, nil}
    end
  end

  @spec split_at_message_id(String.t(), non_neg_integer()) :: {String.t(), String.t() | nil, String.t() | nil}
  defp split_at_message_id(body, index) do
    rest = binary_part(body, index + 1, byte_size(body) - index - 1)

    case parse_message_id(rest) do
      {:ok, number, reply_ack} -> {binary_part(body, 0, index), number, reply_ack}
      :error -> {body, nil, nil}
    end
  end

  @spec last_brace_index(binary(), non_neg_integer(), {:ok, non_neg_integer()} | :error) ::
          {:ok, non_neg_integer()} | :error
  defp last_brace_index(<<>>, _pos, found), do: found
  defp last_brace_index(<<?{, rest::binary>>, pos, _found), do: last_brace_index(rest, pos + 1, {:ok, pos})
  defp last_brace_index(<<_, rest::binary>>, pos, found), do: last_brace_index(rest, pos + 1, found)

  @spec parse_message_id(binary()) :: {:ok, String.t(), String.t() | nil} | :error
  defp parse_message_id(rest) do
    case take_alphanumeric(rest, 5, <<>>) do
      {<<>>, _tail} -> :error
      {id, <<>>} -> {:ok, id, nil}
      {id, <<?}, tail::binary>>} -> parse_reply_ack(id, tail)
      {_id, _tail} -> :error
    end
  end

  @spec parse_reply_ack(String.t(), binary()) :: {:ok, String.t(), String.t()} | :error
  defp parse_reply_ack(id, tail) do
    case take_alphanumeric(tail, 5, <<>>) do
      {<<>>, _} -> :error
      {ack, <<>>} -> {:ok, id, ack}
      {_ack, _rest} -> :error
    end
  end

  @spec take_alphanumeric(binary(), non_neg_integer(), binary()) :: {binary(), binary()}
  defp take_alphanumeric(rest, 0, acc), do: {acc, rest}

  defp take_alphanumeric(<<c, rest::binary>>, remaining, acc) when is_alphanumeric(c) do
    take_alphanumeric(rest, remaining - 1, <<acc::binary, c>>)
  end

  defp take_alphanumeric(rest, _remaining, acc), do: {acc, rest}

  ## Positions

  @spec parse_aprs_position(String.t(), String.t()) :: %{
          latitude: coordinate(),
          longitude: coordinate(),
          ambiguity: position_ambiguity()
        }
  defp parse_aprs_position(lat, lon), do: Aprs.Position.parse_aprs_position(lat, lon)

  @spec handle_position_result(map(), atom()) :: map()
  defp handle_position_result(%{data_type: type} = result, _data_type)
       when type in [:malformed_position, :position_error], do: result

  defp handle_position_result(result, data_type), do: Map.put(result, :data_type, data_type)

  @spec add_has_position(map()) :: map()
  defp add_has_position(result) do
    Map.put(result, :has_position, has_valid_coordinates?(result))
  end

  @spec has_valid_coordinates?(map()) :: boolean()
  defp has_valid_coordinates?(%{latitude: lat, longitude: lon}) do
    is_number(lat) and is_number(lon)
  end

  defp has_valid_coordinates?(_), do: false

  @spec parse_position_without_timestamp(String.t()) :: map()
  def parse_position_without_timestamp(
        <<lat::binary-size(8), table::binary-size(1), lon::binary-size(9), code::binary-size(1), comment::binary>> =
          position_data
      ) do
    if valid_aprs_coordinate?(lat, lon) do
      parse_position_uncompressed(lat, table, lon, code, comment)
    else
      try_parse_compressed(position_data)
    end
  end

  def parse_position_without_timestamp(
        <<latitude::binary-size(8), sym_table_id::binary-size(1), longitude::binary-size(9)>> = position_data
      ) do
    if valid_aprs_coordinate?(latitude, longitude) do
      parse_position_short_uncompressed(latitude, sym_table_id, longitude)
    else
      try_parse_compressed(position_data)
    end
  end

  def parse_position_without_timestamp(position_data) when byte_size(position_data) >= 13 do
    try_parse_compressed(position_data)
  end

  def parse_position_without_timestamp(_invalid_data) do
    %{data_type: :malformed_position, error: "Invalid position format"}
  end

  @spec valid_aprs_coordinate?(String.t(), String.t()) :: boolean()
  defp valid_aprs_coordinate?(lat, lon) do
    Aprs.Position.valid_latitude_format?(lat) and Aprs.Position.valid_longitude_format?(lon)
  end

  # The compressed format is a fixed 13-byte frame: symbol table, four base-91
  # latitude bytes, four base-91 longitude bytes, symbol code, cs pair and the
  # compression type byte.
  @spec try_parse_compressed(binary()) :: map()
  defp try_parse_compressed(
         <<sym_table_id, latitude::binary-size(4), longitude::binary-size(4), symbol_code, c, s, t, comment::binary>>
       )
       when is_compressed_table(sym_table_id) do
    if base91_run?(latitude) and base91_run?(longitude) do
      compressed_frame(sym_table_id, latitude, longitude, symbol_code, c, s, t, comment)
    else
      compressed_location_error()
    end
  end

  defp try_parse_compressed(_position_data), do: compressed_location_error()

  @spec compressed_location_error() :: map()
  defp compressed_location_error do
    %{data_type: :position_error, error_message: "Invalid compressed location", has_position: false}
  end

  @spec base91_run?(binary()) :: boolean()
  defp base91_run?(<<>>), do: true
  defp base91_run?(<<byte, rest::binary>>) when is_base91(byte), do: base91_run?(rest)
  defp base91_run?(_data), do: false

  @spec compressed_frame(byte(), binary(), binary(), byte(), byte(), byte(), byte(), binary()) :: map()
  defp compressed_frame(sym_table_id, latitude, longitude, symbol_code, c, s, t, comment) do
    parse_position_compressed(
      <<sym_table_id>>,
      latitude,
      longitude,
      <<symbol_code>>,
      <<c, s>>,
      <<t>>,
      comment
    )
  end

  @spec parse_position_uncompressed(String.t(), String.t(), String.t(), String.t(), String.t()) :: map()
  defp parse_position_uncompressed(latitude, sym_table_id, longitude, symbol_code, comment) do
    %{latitude: lat, longitude: lon, ambiguity: ambiguity} = parse_aprs_position(latitude, longitude)
    {weather, extension, altitude, telemetry, dao, cleaned_comment} = parse_position_comment(symbol_code, comment)
    {lat, lon} = DAO.apply_precision(lat, lon, dao, ambiguity)

    %{
      latitude: lat,
      longitude: lon,
      timestamp: nil,
      symbol_table_id: sym_table_id,
      symbol_code: symbol_code,
      comment: cleaned_comment,
      altitude: altitude,
      phg: nil,
      course: nil,
      speed: nil,
      radiorange: nil,
      aprs_messaging?: false,
      compressed?: false,
      position_ambiguity: ambiguity,
      dao: dao,
      has_position: is_number(lat) and is_number(lon),
      posresolution: UtilityHelpers.position_resolution(ambiguity),
      format: :uncompressed,
      posambiguity: ambiguity,
      messaging: 0,
      wx: nil
    }
    |> Map.merge(extension)
    |> maybe_put(:telemetry, telemetry)
    |> maybe_put(:weather, weather)
    |> maybe_put(:wx, weather)
  end

  @spec parse_position_short_uncompressed(String.t(), String.t(), String.t()) :: map()
  defp parse_position_short_uncompressed(latitude, sym_table_id, longitude) do
    %{latitude: lat, longitude: lon, ambiguity: ambiguity} = parse_aprs_position(latitude, longitude)

    %{
      latitude: lat,
      longitude: lon,
      timestamp: nil,
      symbol_table_id: sym_table_id,
      symbol_code: nil,
      data_type: :position,
      aprs_messaging?: false,
      compressed?: false,
      position_ambiguity: ambiguity,
      dao: nil,
      course: nil,
      speed: nil,
      has_position: is_number(lat) and is_number(lon),
      posresolution: UtilityHelpers.position_resolution(ambiguity),
      format: :uncompressed,
      posambiguity: ambiguity,
      messaging: 0
    }
  end

  @spec parse_position_compressed(String.t(), binary(), binary(), String.t(), binary(), binary(), String.t()) :: map()
  defp parse_position_compressed(
         sym_table_id,
         latitude_compressed,
         longitude_compressed,
         symbol_code,
         cs,
         compression_type,
         comment
       ) do
    case {CompressedPositionHelpers.convert_compressed_lat(latitude_compressed),
          CompressedPositionHelpers.convert_compressed_lon(longitude_compressed)} do
      {{:ok, lat}, {:ok, lon}} ->
        build_compressed_position(sym_table_id, lat, lon, symbol_code, cs, compression_type, comment)

      {{:error, lat_error}, _} ->
        compressed_position_error(lat_error)

      {_, {:error, lon_error}} ->
        compressed_position_error(lon_error)
    end
  end

  @spec compressed_position_error(String.t()) :: map()
  defp compressed_position_error(reason) do
    %{
      data_type: :position_error,
      error_message: "Invalid compressed location: #{reason}",
      has_position: false
    }
  end

  @spec build_compressed_position(String.t(), float(), float(), String.t(), binary(), binary(), String.t()) :: map()
  defp build_compressed_position(sym_table_id, lat, lon, symbol_code, cs, compression_type, comment) do
    compressed_cs = CompressedPositionHelpers.convert_compressed_cs(cs, compression_type)
    compression_info = CompressedPositionHelpers.parse_compression_type(compression_type)

    {weather, _extension, altitude, telemetry, dao, cleaned_comment} =
      parse_position_comment(symbol_code, comment, false)

    {phg, cleaned_comment} = extract_phg(cleaned_comment)
    {lat, lon} = DAO.apply_precision(lat, lon, dao, 0)

    %{
      latitude: lat,
      longitude: lon,
      symbol_table_id: sym_table_id,
      symbol_code: symbol_code,
      comment: String.trim(cleaned_comment),
      position_format: :compressed,
      compression_type: compression_type,
      compression_info: compression_info,
      data_type: :position,
      compressed?: true,
      position_ambiguity: 0,
      dao: dao,
      has_position: is_number(lat) and is_number(lon),
      posresolution: UtilityHelpers.compressed_position_resolution(),
      format: :compressed,
      posambiguity: 0,
      messaging: 0,
      altitude: altitude,
      phg: phg
    }
    |> Map.merge(compressed_cs)
    |> maybe_put(:telemetry, telemetry)
    |> maybe_put(:weather, weather)
    |> maybe_put(:wx, weather)
  end

  # Shared comment pipeline: weather (weather symbol only), then the APRS data
  # extension, altitude, base-91 comment telemetry and finally DAO.
  #
  # A weather report keeps the weather scanner's remainder as its comment. Only
  # the weather fields are cut from it, so an altitude or telemetry value stays
  # in the text even though it is still decoded into its own field.
  @spec parse_position_comment(String.t() | nil, String.t(), boolean()) ::
          {map() | nil, map(), float() | nil, map() | nil, DAO.t() | nil, String.t()}
  defp parse_position_comment(symbol_code, comment, extension? \\ true) do
    {weather, after_weather} = extract_weather(symbol_code, comment)
    {extension, after_extension} = extract_data_extension(extension? and is_nil(weather), after_weather)
    {altitude, after_altitude} = extract_altitude(after_extension)
    {telemetry, after_telemetry} = TelemetryFromComment.extract_telemetry_from_comment(after_altitude)
    {dao, after_dao} = DAO.parse(after_telemetry)
    cleaned = if weather, do: after_weather, else: after_dao

    {weather, extension, altitude, telemetry, dao, cleaned |> strip_leading_delimiter() |> String.trim()}
  end

  # For the weather symbol the leading `NNN/NNN` field is wind, not course and
  # speed, and the weather scanner has already consumed it.
  @spec extract_weather(String.t() | nil, String.t()) :: {map() | nil, String.t()}
  defp extract_weather("_", comment), do: Weather.parse_weather_data_with_remainder(comment)
  defp extract_weather(_symbol_code, comment), do: {nil, comment}

  @spec extract_data_extension(boolean(), String.t()) :: {map(), String.t()}
  defp extract_data_extension(true, comment), do: extract_data_extension(comment)
  defp extract_data_extension(false, comment), do: {%{}, comment}

  ## APRS data extensions

  defguardp is_extension_byte(b) when is_digit(b) or b == ?\s or b == ?.

  # FAP.pm treats Course/Speed, PHG, RNG and DFS as mutually exclusive and
  # anchored to the start of the comment text.
  @spec extract_data_extension(String.t()) :: {map(), String.t()}
  defp extract_data_extension(<<c1, c2, c3, ?/, s1, s2, s3, rest::binary>>)
       when is_extension_byte(c1) and is_extension_byte(c2) and is_extension_byte(c3) and is_extension_byte(s1) and
              is_extension_byte(s2) and is_extension_byte(s3) do
    extension = %{course: course_value(c1, c2, c3), speed: speed_value(s1, s2, s3)}
    extract_df_report(extension, rest)
  end

  defp extract_data_extension(<<"PHG", p, h, g, d, rest::binary>>)
       when is_digit(p) and h in 0x30..0x7E and is_digit(g) and is_digit(d) do
    extract_phg_rate(%{phg: <<p, h, g, d>>}, rest)
  end

  defp extract_data_extension(<<"RNG", d1, d2, d3, d4, rest::binary>>)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_digit(d4) do
    {%{radiorange: digits_to_integer([d1, d2, d3, d4])}, rest}
  end

  defp extract_data_extension(<<"DFS", s, h, g, d, rest::binary>>)
       when is_digit(s) and is_digit(h) and is_digit(g) and is_digit(d) do
    {strength, _} = PHGHelpers.parse_df_strength(s)
    {height, _} = PHGHelpers.parse_phg_height(h)
    {gain, _} = PHGHelpers.parse_phg_gain(g)
    {directivity, _} = PHGHelpers.parse_phg_directivity(d)

    extension = %{
      dfs: <<s, h, g, d>>,
      df_strength: strength,
      df_height: height,
      df_gain: gain,
      df_directivity: directivity
    }

    {extension, rest}
  end

  defp extract_data_extension(comment), do: {%{}, comment}

  # PHGR: an extra packet-rate character followed by "/".
  @spec extract_phg_rate(map(), binary()) :: {map(), binary()}
  defp extract_phg_rate(extension, <<r, ?/, rest::binary>>) when is_digit(r) or r in ?A..?Z do
    {Map.put(extension, :phg_rate, <<r>>), rest}
  end

  defp extract_phg_rate(extension, rest), do: {extension, rest}

  # NRQ quality digit to bearing accuracy in degrees (APRS101 chapter 7).
  @df_quality %{0 => nil, 1 => 240, 2 => 120, 3 => 64, 4 => 32, 5 => 16, 6 => 8, 7 => 4, 8 => 2, 9 => 1}

  # CSE/SPD/BRG/NRQ: a course/speed pair followed by a DF bearing and NRQ.
  @spec extract_df_report(map(), binary()) :: {map(), binary()}
  defp extract_df_report(extension, <<?/, b1, b2, b3, ?/, n, r, q, rest::binary>>)
       when is_digit(b1) and is_digit(b2) and is_digit(b3) and is_digit(n) and is_digit(r) and is_digit(q) do
    df =
      Map.merge(extension, %{
        bearing: digits_to_integer([b1, b2, b3]),
        nrq: <<n, r, q>>,
        df_hits: n - ?0,
        df_range: 2 ** (r - ?0) * 1.0,
        df_quality: Map.get(@df_quality, q - ?0)
      })

    {df, rest}
  end

  defp extract_df_report(extension, rest), do: {extension, rest}

  @spec course_value(byte(), byte(), byte()) :: non_neg_integer()
  defp course_value(c1, c2, c3) when is_digit(c1) and is_digit(c2) and is_digit(c3) do
    clamp_course(digits_to_integer([c1, c2, c3]))
  end

  defp course_value(_, _, _), do: 0

  @spec clamp_course(integer()) :: non_neg_integer()
  defp clamp_course(c) when c >= 1 and c <= 360, do: c
  defp clamp_course(_), do: 0

  @spec speed_value(byte(), byte(), byte()) :: float() | nil
  defp speed_value(s1, s2, s3) when is_digit(s1) and is_digit(s2) and is_digit(s3) do
    digits_to_integer([s1, s2, s3]) * 1.0
  end

  defp speed_value(_, _, _), do: nil

  @spec digits_to_integer([byte()]) :: non_neg_integer()
  defp digits_to_integer(digits) do
    Enum.reduce(digits, 0, fn digit, acc -> acc * 10 + (digit - ?0) end)
  end

  ## Comment sub-fields

  # `/A=nnnnnn` anywhere in the comment. Uppercase `A` removes the field;
  # lowercase `a` leaves `a=nnnnnn` behind, matching reference parsers.
  @spec extract_altitude(String.t()) :: {float() | nil, String.t()}
  defp extract_altitude(comment), do: scan_altitude(comment, <<>>)

  @spec scan_altitude(binary(), binary()) :: {float() | nil, String.t()}
  defp scan_altitude(<<>>, acc), do: {nil, acc}

  defp scan_altitude(<<?/, a, ?=, rest::binary>>, acc) when a in [?A, ?a] do
    case take_altitude_digits(rest) do
      {:ok, digits, tail} -> {validate_altitude(digits), altitude_remainder(a, digits, acc, tail)}
      :error -> scan_altitude(<<a, ?=, rest::binary>>, <<acc::binary, ?/>>)
    end
  end

  defp scan_altitude(<<c, rest::binary>>, acc), do: scan_altitude(rest, <<acc::binary, c>>)

  @spec altitude_remainder(byte(), String.t(), binary(), binary()) :: String.t()
  defp altitude_remainder(?a, digits, acc, tail), do: acc <> "a=" <> digits <> tail
  defp altitude_remainder(_uppercase, _digits, acc, tail), do: acc <> tail

  @spec take_altitude_digits(binary()) :: {:ok, String.t(), binary()} | :error
  defp take_altitude_digits(<<?-, rest::binary>>), do: take_altitude_digits(rest, <<?->>)
  defp take_altitude_digits(rest), do: take_altitude_digits(rest, <<>>)

  @spec take_altitude_digits(binary(), binary()) :: {:ok, String.t(), binary()} | :error
  defp take_altitude_digits(<<d, rest::binary>>, acc) when is_digit(d) do
    take_altitude_digits(rest, <<acc::binary, d>>)
  end

  defp take_altitude_digits(rest, acc) do
    case digit_count(acc) do
      count when count in 5..6 -> {:ok, acc, rest}
      _ -> :error
    end
  end

  @spec digit_count(binary()) :: non_neg_integer()
  defp digit_count(<<?-, rest::binary>>), do: byte_size(rest)
  defp digit_count(acc), do: byte_size(acc)

  # Valid altitude range: -10,000 ft (Dead Sea) to 500,000 ft (high-altitude
  # balloons / low satellites). Anything outside is treated as garbage.
  @spec validate_altitude(String.t()) :: float() | nil
  defp validate_altitude(digits) do
    altitude = String.to_integer(digits) * 1.0

    if altitude < -10_000.0 or altitude > 500_000.0, do: nil, else: altitude
  end

  # PHG anywhere in a comment, used by the compressed path where the data
  # extension cannot be anchored to the comment start.
  @spec extract_phg(String.t()) :: {String.t() | nil, String.t()}
  defp extract_phg(comment), do: scan_phg(comment, <<>>)

  @spec scan_phg(binary(), binary()) :: {String.t() | nil, String.t()}
  defp scan_phg(<<>>, acc), do: {nil, acc}

  defp scan_phg(<<"PHG", p, h, g, d, rest::binary>>, acc)
       when is_digit(p) and is_digit(h) and is_digit(g) and is_digit(d) do
    {<<p, h, g, d>>, String.trim(acc <> strip_phg_rate(rest))}
  end

  defp scan_phg(<<c, rest::binary>>, acc), do: scan_phg(rest, <<acc::binary, c>>)

  @spec strip_phg_rate(binary()) :: binary()
  defp strip_phg_rate(<<r, ?/, rest::binary>>) when is_digit(r) or r in ?A..?Z, do: rest
  defp strip_phg_rate(rest), do: rest

  # Strip SSID from callsign (FAP.pm: $dstcallsign =~ s/-\d+$//)
  @spec strip_ssid(String.t() | nil) :: String.t() | nil
  defp strip_ssid(nil), do: nil

  defp strip_ssid(callsign) do
    case :binary.matches(callsign, "-") do
      [] -> callsign
      matches -> drop_ssid(callsign, matches |> List.last() |> elem(0))
    end
  end

  @spec drop_ssid(String.t(), non_neg_integer()) :: String.t()
  defp drop_ssid(callsign, pos) do
    tail = binary_part(callsign, pos + 1, byte_size(callsign) - pos - 1)

    if tail != "" and digits_only?(tail), do: binary_part(callsign, 0, pos), else: callsign
  end

  @spec digits_only?(binary()) :: boolean()
  defp digits_only?(<<>>), do: true
  defp digits_only?(<<d, rest::binary>>) when is_digit(d), do: digits_only?(rest)
  defp digits_only?(_), do: false

  # Strip leading / or space from comment (FAP.pm line 1211)
  @spec strip_leading_delimiter(String.t()) :: String.t()
  defp strip_leading_delimiter(<<"/", rest::binary>>), do: rest
  defp strip_leading_delimiter(<<" ", rest::binary>>), do: rest
  defp strip_leading_delimiter(comment), do: comment

  ## Timestamped positions

  @spec parse_position_with_message_without_timestamp(String.t()) :: map()
  def parse_position_with_message_without_timestamp(position_data) do
    position_data
    |> parse_position_without_timestamp()
    |> Map.put(:aprs_messaging?, true)
  end

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
    %{data_type: :timestamped_position_error, error: "Invalid timestamped position format"}
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

    case try_compressed_timestamped(position_data, aprs_messaging?, time, data_type) do
      {:ok, result} -> result
      :error -> try_regex_position_fallback(aprs_messaging?, time, position_data, data_type)
    end
  end

  @spec try_compressed_timestamped(binary(), boolean(), binary(), atom()) :: {:ok, map()} | :error
  defp try_compressed_timestamped(position_data, aprs_messaging?, time, data_type) do
    case try_parse_compressed(position_data) do
      %{latitude: lat, longitude: lon} = result when is_number(lat) and is_number(lon) ->
        unix_timestamp = UtilityHelpers.parse_timestamp(time)

        {:ok,
         result
         |> Map.put(:timestamp, unix_timestamp)
         |> Map.put(:time, unix_timestamp)
         |> Map.put(:aprs_messaging?, aprs_messaging?)
         |> Map.put(:data_type, data_type)
         |> Map.put(:messaging, if(aprs_messaging?, do: 1, else: 0))}

      _ ->
        :error
    end
  end

  @spec try_regex_position_fallback(boolean(), String.t(), String.t(), atom()) :: map()
  defp try_regex_position_fallback(aprs_messaging?, time, raw_data, data_type) do
    regex =
      ~r/^(?<lat>\d{4,5}\.\d+[NS])(?<sym_table>.)(?<lon>\d{5,6}\.\d+[EW])(?<sym_code>.)(?<comment>.*)$/

    case Regex.named_captures(regex, raw_data) do
      %{"lat" => lat, "lon" => lon, "sym_table" => sym_table, "sym_code" => sym_code, "comment" => comment} ->
        build_fallback_position_result(aprs_messaging?, lat, lon, time, sym_table, sym_code, comment, data_type)

      _ ->
        %{
          data_type: :timestamped_position_error,
          error: "Invalid timestamped position format",
          raw_data: time <> raw_data
        }
    end
  end

  @spec build_fallback_position_result(
          boolean(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          atom()
        ) :: map()
  defp build_fallback_position_result(aprs_messaging?, lat, lon, time, sym_table, sym_code, comment, data_type) do
    aprs_messaging?
    |> build_position_result(lat, lon, time, sym_table, sym_code, comment, data_type)
    |> Map.put(:timestamp, time)
    |> Map.put(:time, time)
  end

  @spec build_position_result(
          boolean(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          atom()
        ) :: map()
  defp build_position_result(aprs_messaging?, lat, lon, time, sym_table_id, symbol_code, comment, data_type) do
    position = parse_aprs_position(lat, lon)
    ambiguity = position.ambiguity
    unix_timestamp = UtilityHelpers.parse_timestamp(time)
    {weather, extension, altitude, telemetry, dao, cleaned_comment} = parse_position_comment(symbol_code, comment)
    {latitude, longitude} = DAO.apply_precision(position.latitude, position.longitude, dao, ambiguity)

    %{
      latitude: latitude,
      longitude: longitude,
      position: position,
      time: unix_timestamp,
      timestamp: unix_timestamp,
      symbol_table_id: sym_table_id,
      symbol_code: symbol_code,
      comment: cleaned_comment,
      aprs_messaging?: aprs_messaging?,
      compressed?: false,
      course: nil,
      speed: nil,
      radiorange: nil,
      altitude: altitude,
      phg: nil,
      dao: dao,
      data_type: data_type,
      format: :uncompressed,
      has_position: is_number(latitude) and is_number(longitude),
      messaging: if(aprs_messaging?, do: 1, else: 0),
      position_ambiguity: ambiguity,
      posambiguity: ambiguity,
      posresolution: UtilityHelpers.position_resolution(ambiguity)
    }
    |> Map.merge(extension)
    |> maybe_put(:telemetry, telemetry)
    |> maybe_put(:weather, weather)
    |> maybe_put(:wx, weather)
  end

  ## Status, capabilities, queries and user defined data

  # Station capabilities are a comma separated list of tokens, each either a
  # bare capability or `KEY=VALUE`.
  @spec parse_station_capabilities(String.t()) :: map()
  defp parse_station_capabilities(data) do
    capabilities =
      data
      |> String.split(",", trim: true)
      |> Map.new(&split_capability/1)

    %{capabilities: capabilities, raw_data: data, data_type: :station_capabilities}
  end

  @spec split_capability(String.t()) :: {String.t(), String.t() | nil}
  defp split_capability(token) do
    case String.split(token, "=", parts: 2) do
      [key, value] -> {String.trim(key), value}
      [key] -> {String.trim(key), nil}
    end
  end

  @spec parse_query(String.t()) :: map()
  defp parse_query(<<query_type::binary-size(1), query_data::binary>>) do
    %{query_type: query_type, query_data: query_data, data_type: :query}
  end

  defp parse_query(data) do
    %{query_type: nil, query_data: data, data_type: :query}
  end

  # Only `{{` is defined by the spec, as experimental data.
  @spec parse_user_defined(String.t()) :: map()
  defp parse_user_defined(<<?{, user_data::binary>>) do
    %{user_id: "{", experimental?: true, user_data: user_data, data_type: :user_defined}
  end

  defp parse_user_defined(<<user_id::binary-size(1), user_data::binary>>) do
    %{user_id: user_id, experimental?: false, user_data: user_data, data_type: :user_defined}
  end

  defp parse_user_defined(data) do
    %{user_id: nil, experimental?: false, user_data: data, data_type: :user_defined}
  end

  ## Maidenhead grid locator beacons

  @spec parse_maidenhead(String.t()) :: map()
  defp parse_maidenhead(<<f1, f2, s1, s2, r1, r2, rest::binary>>)
       when f1 in ?A..?R and f2 in ?A..?R and is_digit(s1) and is_digit(s2) and r1 in ?a..?x and r2 in ?a..?x do
    build_grid_beacon(<<f1, f2, s1, s2, r1, r2>>, grid_position(f1, f2, s1, s2, r1, r2), rest)
  end

  defp parse_maidenhead(<<f1, f2, s1, s2, rest::binary>>)
       when f1 in ?A..?R and f2 in ?A..?R and is_digit(s1) and is_digit(s2) do
    build_grid_beacon(<<f1, f2, s1, s2>>, grid_position(f1, f2, s1, s2), rest)
  end

  defp parse_maidenhead(data) do
    %{data_type: :maidenhead_grid, raw_data: data, has_position: false}
  end

  @spec build_grid_beacon(String.t(), {float(), float()}, String.t()) :: map()
  defp build_grid_beacon(grid, {lat, lon}, rest) do
    %{
      data_type: :maidenhead_grid,
      grid_locator: grid,
      latitude: lat,
      longitude: lon,
      comment: rest |> strip_grid_terminator() |> String.trim(),
      has_position: true,
      position_ambiguity: 0,
      format: :maidenhead
    }
  end

  @spec strip_grid_terminator(binary()) :: binary()
  defp strip_grid_terminator(<<?], rest::binary>>), do: rest
  defp strip_grid_terminator(rest), do: rest

  # Centre of the four-character grid square: 2 degrees of longitude by
  # 1 degree of latitude.
  @spec grid_position(byte(), byte(), byte(), byte()) :: {float(), float()}
  defp grid_position(f1, f2, s1, s2) do
    lon = (f1 - ?A) * 20 + (s1 - ?0) * 2 - 180 + 1
    lat = (f2 - ?A) * 10 + (s2 - ?0) - 90 + 0.5
    {lat / 1, lon / 1}
  end

  # Centre of the six-character subsquare: 5 minutes of longitude by
  # 2.5 minutes of latitude.
  @spec grid_position(byte(), byte(), byte(), byte(), byte(), byte()) :: {float(), float()}
  defp grid_position(f1, f2, s1, s2, r1, r2) do
    lon = (f1 - ?A) * 20 + (s1 - ?0) * 2 - 180 + (r1 - ?a) * (2 / 24) + 1 / 24
    lat = (f2 - ?A) * 10 + (s2 - ?0) - 90 + (r2 - ?a) * (1 / 24) + 1 / 48
    {lat / 1, lon / 1}
  end

  ## Third party traffic

  @spec parse_third_party_traffic(String.t()) :: map()
  defp parse_third_party_traffic(packet) do
    parse_third_party_with_depth_check(packet, UtilityHelpers.count_leading_braces(packet))
  end

  @spec parse_third_party_with_depth_check(String.t(), integer()) :: map()
  defp parse_third_party_with_depth_check(_packet, depth) when depth + 1 > 3 do
    %{error: "Maximum tunnel depth exceeded"}
  end

  defp parse_third_party_with_depth_check(packet, _depth) do
    case parse_tunneled_packet(packet) do
      {:ok, parsed_packet} -> build_third_party_traffic_result(packet, parsed_packet)
      {:error, reason} -> %{error: reason}
    end
  end

  @spec build_third_party_traffic_result(String.t(), map()) :: map()
  defp build_third_party_traffic_result(packet, parsed_packet) do
    inner =
      case parse_nested_tunnel(packet) do
        {:ok, nested_packet} -> nested_packet
        {:error, _} -> parsed_packet
      end

    %{third_party_packet: inner, data_type: :third_party_traffic, raw_data: packet}
  end

  @spec parse_tunneled_packet(String.t()) :: {:ok, map()} | {:error, String.t()}
  defp parse_tunneled_packet(packet) do
    case String.split(packet, ":", parts: 2) do
      [header, information] -> parse_tunneled_packet_with_header(header, information)
      _ -> {:error, "Invalid tunneled packet format"}
    end
  end

  @spec parse_tunneled_packet_with_header(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  defp parse_tunneled_packet_with_header(header, information) do
    case parse_tunneled_header(header) do
      {:ok, header_data} -> parse_tunneled_packet_with_information(header_data, information)
      {:error, reason} -> {:error, "Invalid header: #{reason}"}
    end
  end

  @spec parse_tunneled_packet_with_information(map(), String.t()) :: {:ok, map()}
  defp parse_tunneled_packet_with_information(header_data, information) do
    {data_type, data} = resolve_datatype(information)
    data_extended = parse_data(data_type, header_data.destination, prepare_data_for_parsing(data_type, data))

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
      [sender, path] -> parse_sender_and_path(sender, path)
      _ -> {:error, "Invalid header format"}
    end
  end

  @spec parse_sender_and_path(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  defp parse_sender_and_path(sender, path) do
    case parse_callsign(sender) do
      {:ok, callsign_parts} ->
        {:ok, [destination, digi_path]} = split_path(path)

        {:ok,
         %{
           sender: sender,
           base_callsign: List.first(callsign_parts),
           ssid: List.last(callsign_parts),
           destination: destination,
           digi_path: digi_path
         }}

      {:error, reason} ->
        {:error, "Invalid callsign: #{reason}"}
    end
  end

  @spec parse_network_tunnel(String.t()) :: {:ok, map()} | {:error, String.t()}
  defp parse_network_tunnel(packet) do
    tunneled_packet = String.slice(packet, 1..-1//1)

    case parse_tunneled_packet(tunneled_packet) do
      {:ok, parsed_packet} -> {:ok, Map.merge(parsed_packet, %{tunnel_type: :network, raw_data: packet})}
      {:error, reason} -> {:error, "Invalid tunneled packet: #{reason}"}
    end
  end

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

  @spec timestamp_now() :: DateTime.t()
  defp timestamp_now, do: DateTime.truncate(DateTime.utc_now(), :microsecond)
end
