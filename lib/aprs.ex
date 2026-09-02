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

  alias Aprs.Clock
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

  # Kept in step with mix.exs so `version/0` cannot drift from the released
  # package version.
  @version Mix.Project.config()[:version]

  @max_packet_size 8192

  # APRS101: the `!` data type indicator may appear anywhere in the first 40
  # bytes of the information field, preceded by free text from old TNCs.
  @legacy_position_scan_limit 40

  @doc """
  Returns the version of the library, the same string `mix.exs` declares.

  ## Examples

      iex> [major, minor, patch] = String.split(Aprs.version(), ".")
      iex> Enum.all?([major, minor, patch], &match?({_, ""}, Integer.parse(&1)))
      true
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

  @doc """
  Parse a TNC2-format packet (`SRC>DST,PATH:information`).

  Returns `{:ok, packet}`, or `{:error, reason}` for a packet that is not
  parseable at all - a malformed header, an invalid callsign or path, or a
  body larger than 8192 bytes. A packet whose header is well formed but whose
  information field is not always parses; the trouble is reported in
  `data_type` (`:unknown_datatype`, `:malformed_position`, `:mic_e_error`, and
  so on) rather than as an error.

  The returned map carries the packet envelope, the type-specific fields under
  `data_extended`, those same fields flattened into the top level, and the
  reference-parser field names (`srccallsign`, `symboltable`, `posambiguity`,
  ...). See the README for the full field list.

  ## Examples

      iex> {:ok, packet} = Aprs.parse("N0CALL>APRS,TCPIP*,qAC,T2TEST:=4903.50N/07201.75W-Hi")
      iex> {packet.data_type, packet.latitude, packet.comment}
      {:position_with_message, 49.05833333333333, "Hi"}

      iex> Aprs.parse("not a packet")
      {:error, :invalid_packet}
  """
  @spec parse(term()) :: parse_result()
  def parse(message) when is_binary(message) and byte_size(message) <= @max_packet_size do
    message |> scrub_encoding() |> do_parse()
  end

  def parse(message) when is_binary(message), do: {:error, :packet_too_large}
  def parse(_), do: {:error, :invalid_packet}

  # A packet is normally valid UTF-8. When it is not, the bad bytes are nearly
  # always Latin-1 from a radio, so decode them as Latin-1 rather than replacing
  # every non-ASCII byte in the packet. `:unicode.characters_to_binary/1`
  # validates in C and hands back the offset of the first bad byte, so a well
  # formed packet is never walked byte by byte.
  @spec scrub_encoding(binary()) :: String.t()
  defp scrub_encoding(message) do
    case :unicode.characters_to_binary(message) do
      valid when is_binary(valid) -> valid
      {:error, valid, invalid} -> scrub(invalid, valid)
      {:incomplete, valid, invalid} -> scrub(invalid, valid)
    end
  end

  # `invalid` always starts on the offending byte: promote it from Latin-1 and
  # hand the remainder back to the validator.
  @spec scrub(binary(), binary()) :: String.t()
  defp scrub(<<>>, acc), do: acc
  defp scrub(<<b, rest::binary>>, acc), do: scrub_valid(rest, <<acc::binary, b::utf8>>)

  @spec scrub_valid(binary(), binary()) :: String.t()
  defp scrub_valid(rest, acc) do
    case :unicode.characters_to_binary(rest) do
      valid when is_binary(valid) -> <<acc::binary, valid::binary>>
      {:error, valid, invalid} -> scrub(invalid, <<acc::binary, valid::binary>>)
      {:incomplete, valid, invalid} -> scrub(invalid, <<acc::binary, valid::binary>>)
    end
  end

  @spec do_parse(String.t()) :: parse_result()
  defp do_parse(message) do
    with {:ok, [sender, path, data]} <- split_packet(message),
         {:ok, callsign_parts} <- parse_callsign(sender),
         {:ok, [destination, digi_path]} <- split_path(path),
         {:ok, digipeaters} <- parse_digi_path(digi_path),
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
          callsign_parts,
          digipeaters
        )

      {:ok, packet_data}
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

  @spec build_packet_data(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          atom(),
          String.t(),
          [String.t()],
          [map()]
        ) :: packet()
  defp build_packet_data(sender, path, destination, data, data_type, data_for_parsing, callsign_parts, digipeaters) do
    data_extended = parse_data(data_type, destination, prepare_data_for_parsing(data_type, data_for_parsing))
    final_data_type = determine_final_data_type(data_extended, data_type)
    header = build_header(sender, destination, path)

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
      received_at: Clock.utc_now(),
      # Standard APRS parser fields
      srccallsign: sender,
      dstcallsign: destination,
      body: data,
      origpacket: <<header::binary, ?:, data::binary>>,
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
      itemname: nil,
      symbolcode: nil,
      symboltable: nil,
      resultcode: "success",
      resultmsg: "OK"
    }

    base_packet
    |> merge_data_extended(data_extended)
    |> map_fields_to_reference_format(data_extended)
  end

  # Built as one bitstring so the header is copied once, not once per `<>`.
  @spec build_header(String.t(), String.t(), String.t()) :: String.t()
  defp build_header(sender, destination, ""), do: <<sender::binary, ?>, destination::binary>>

  defp build_header(sender, destination, path) do
    <<sender::binary, ?>, destination::binary, ?,, path::binary>>
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
  # `WIDE1-1,WIDE2*` means WIDE1-1 was used too. The list is built on the way
  # back out of the recursion, so the "was a `*` seen later?" answer is already
  # known when each element is built and the path is walked once.
  # An empty digipeater element (`APRS,,WIDE1-1`) is not a legal AX.25 path, so
  # the path is validated while it is split rather than in a separate scan.
  @spec parse_digi_path(String.t()) :: {:ok, [map()]} | {:error, :invalid_packet}
  defp parse_digi_path(""), do: {:ok, []}

  defp parse_digi_path(path) do
    case path |> :binary.split(",", [:global]) |> mark_digipeaters() do
      {digipeaters, _used} -> {:ok, digipeaters}
      :error -> {:error, :invalid_packet}
    end
  end

  @spec mark_digipeaters([String.t()]) :: {[map()], boolean()} | :error
  defp mark_digipeaters([]), do: {[], false}
  defp mark_digipeaters([<<>> | _rest]), do: :error

  defp mark_digipeaters([digi | rest]) do
    case mark_digipeaters(rest) do
      {parsed, used_later} ->
        used = used_later or used_marker?(digi)
        {[parse_single_digipeater(digi, used) | parsed], used}

      :error ->
        :error
    end
  end

  @spec used_marker?(String.t()) :: boolean()
  defp used_marker?(<<>>), do: false
  defp used_marker?(digi), do: :binary.last(digi) == ?*

  @spec parse_single_digipeater(String.t(), boolean()) :: map()
  defp parse_single_digipeater(<<"q", _::binary-size(2)>> = digi, _used) do
    %{call: digi, wasdigied: 0}
  end

  defp parse_single_digipeater(digi, true) do
    %{call: strip_used_markers(digi), wasdigied: 1}
  end

  defp parse_single_digipeater(digi, false) do
    %{call: digi, wasdigied: 0}
  end

  @spec strip_used_markers(String.t()) :: String.t()
  defp strip_used_markers(<<>>), do: <<>>

  defp strip_used_markers(digi) do
    head_size = byte_size(digi) - 1

    case digi do
      <<head::binary-size(^head_size), ?*>> -> strip_used_markers(head)
      _ -> digi
    end
  end

  # Map internal field names to reference parser format. Every alias is derived
  # from `data_extended` alone, so the aliases are read off the small map rather
  # than the merged packet.
  @spec map_fields_to_reference_format(map(), map() | nil) :: map()
  defp map_fields_to_reference_format(packet, nil), do: packet

  defp map_fields_to_reference_format(packet, data_extended) do
    packet
    |> map_position_ambiguity(data_extended)
    |> map_dao_data(data_extended)
    |> map_weather_data(data_extended)
    |> map_telemetry_data(data_extended)
    |> map_format_field(data_extended)
    |> map_symbol_fields(data_extended)
    |> map_messaging(data_extended)
  end

  @spec map_messaging(map(), map()) :: map()
  defp map_messaging(packet, %{aprs_messaging?: true}), do: Map.put(packet, :messaging, 1)
  defp map_messaging(packet, _data_extended), do: packet

  @spec merge_data_extended(map(), map() | nil) :: map()
  defp merge_data_extended(base_packet, data_extended) when is_map(data_extended) do
    merge_extension(base_packet, data_extended)
  end

  defp merge_data_extended(base_packet, _), do: base_packet

  # An APRS data extension is absent from most comments, and merging an empty
  # map is pure overhead.
  @spec merge_extension(map(), map()) :: map()
  defp merge_extension(map, extension) when map_size(extension) == 0, do: map
  defp merge_extension(map, extension), do: Map.merge(map, extension)

  @spec map_position_ambiguity(map(), map()) :: map()
  defp map_position_ambiguity(packet, %{position_ambiguity: ambiguity}) do
    Map.put(packet, :posambiguity, ambiguity)
  end

  defp map_position_ambiguity(packet, _data_extended), do: packet

  @spec map_dao_data(map(), map()) :: map()
  defp map_dao_data(packet, %{dao: %{datum: datum}}), do: Map.put(packet, :daodatumbyte, datum)
  defp map_dao_data(packet, _data_extended), do: packet

  @spec map_weather_data(map(), map()) :: map()
  defp map_weather_data(packet, %{weather: weather_data}) when is_map(weather_data) do
    Map.put(packet, :wx, weather_data)
  end

  defp map_weather_data(packet, _data_extended), do: packet

  @spec map_telemetry_data(map(), map()) :: map()
  defp map_telemetry_data(packet, %{telemetry: telemetry_data}) when is_map(telemetry_data) do
    Map.put(packet, :mbits, telemetry_data[:bits])
  end

  defp map_telemetry_data(packet, _data_extended), do: packet

  @spec map_format_field(map(), map()) :: map()
  defp map_format_field(packet, %{format: format}), do: Map.put(packet, :format, format)
  defp map_format_field(packet, _data_extended), do: packet

  @spec map_symbol_fields(map(), map()) :: map()
  defp map_symbol_fields(packet, %{symbol_code: code, symbol_table_id: table}) do
    packet |> maybe_put(:symbolcode, code) |> maybe_put(:symboltable, table)
  end

  defp map_symbol_fields(packet, %{symbol_code: code}), do: maybe_put(packet, :symbolcode, code)
  defp map_symbol_fields(packet, %{symbol_table_id: table}), do: maybe_put(packet, :symboltable, table)
  defp map_symbol_fields(packet, _data_extended), do: packet

  @doc """
  Split a packet into `[sender, path, information_field]`.

  `path` is everything between `>` and the first `:`, destination included.

  ## Examples

      iex> Aprs.split_packet("N0CALL>APRS,TCPIP*:>Hello")
      {:ok, ["N0CALL", "APRS,TCPIP*", ">Hello"]}

      iex> Aprs.split_packet("N0CALL")
      {:error, :invalid_packet}
  """
  @spec split_packet(String.t()) :: {:ok, [String.t()]} | {:error, :invalid_packet}
  def split_packet(message) do
    with {:ok, sender, rest} <- find_delimiter(message, ">"),
         {:ok, path, data} <- find_delimiter(rest, ":") do
      {:ok, [sender, path, data]}
    else
      :error -> {:error, :invalid_packet}
    end
  end

  # `:binary.match/2` scans in C, which beats walking the header a byte at a
  # time from Elixir.
  @spec find_delimiter(binary(), binary()) :: {:ok, binary(), binary()} | :error
  defp find_delimiter(binary, delimiter) do
    case :binary.match(binary, delimiter) do
      {position, 1} ->
        rest_start = position + 1
        {:ok, binary_part(binary, 0, position), binary_part(binary, rest_start, byte_size(binary) - rest_start)}

      :nomatch ->
        :error
    end
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

  @doc """
  Split the path into `[destination, digipeater_path]`.

  The digipeater path is `""` when the packet has no digipeaters.

  ## Examples

      iex> Aprs.split_path("APRS,WIDE1-1,WIDE2-1")
      {:ok, ["APRS", "WIDE1-1,WIDE2-1"]}

      iex> Aprs.split_path("APRS")
      {:ok, ["APRS", ""]}
  """
  @spec split_path(String.t()) :: {:ok, [String.t()]}
  def split_path(path) when is_binary(path) do
    case :binary.match(path, ",") do
      {position, 1} ->
        digi_start = position + 1

        {:ok, [binary_part(path, 0, position), binary_part(path, digi_start, byte_size(path) - digi_start)]}

      :nomatch ->
        {:ok, [path, ""]}
    end
  end

  @doc """
  `parse_datatype/1` wrapped in an `:ok` tuple, for use in a `with` chain.

  ## Examples

      iex> Aprs.parse_datatype_safe("!4903.50N/07201.75W-")
      {:ok, :position}
  """
  @spec parse_datatype_safe(String.t()) :: {:ok, atom()}
  def parse_datatype_safe(data), do: {:ok, parse_datatype(data)}

  @doc """
  Split a callsign into `[base_callsign, ssid]`, validating it as AX.25.

  The SSID is `"0"` when the callsign carries none.

  ## Examples

      iex> Aprs.parse_callsign("N0CALL-9")
      {:ok, ["N0CALL", "9"]}

      iex> Aprs.parse_callsign("N0CALL")
      {:ok, ["N0CALL", "0"]}
  """
  @spec parse_callsign(String.t()) :: {:ok, [String.t()]} | {:error, String.t() | atom()}
  def parse_callsign(callsign) do
    case Aprs.AX25.parse_callsign(callsign) do
      {:ok, {base, ssid}} -> {:ok, [base, ssid]}
      {:error, reason} -> {:error, reason}
    end
  end

  # Map of data type indicators to their corresponding atom types. The table is
  # unrolled into `datatype_for/1` clauses below, so the lookup compiles to a
  # jump table on the indicator byte instead of a map lookup.
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

  @spec datatype_for(byte()) :: atom() | nil
  for {<<indicator>>, data_type} <- @datatype_map do
    defp datatype_for(unquote(indicator)), do: unquote(data_type)
  end

  defp datatype_for(_indicator), do: nil

  @doc """
  Determine the data type of an information field.

  Returns the atom for the data type indicator, `:empty` for an empty field,
  or `:unknown_datatype` for an indicator that is not recognised and holds no
  `!` within its first 40 bytes.

  ## Examples

      iex> Aprs.parse_datatype("=4903.50N/07201.75W-")
      :position_with_message

      iex> Aprs.parse_datatype("T#005,199,000,255,073,123,01101001")
      :telemetry

      iex> Aprs.parse_datatype("~nonsense")
      :unknown_datatype
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

  defp resolve_datatype(<<indicator, _::binary>> = data) do
    case datatype_for(indicator) do
      nil -> legacy_position_datatype(data)
      data_type -> {data_type, data}
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

  @doc """
  Parse an information field that has already been classified by
  `parse_datatype/1`.

  `destination` is the TOCALL, which Mic-E packets need for the latitude. The
  returned map always carries a `data_type`, which may be more specific than
  the one passed in (a `:weather` position, a `:message_ack`, a
  `:mic_e_error`). Returns `nil` when the field cannot be parsed at all.
  """
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

  defp split_addressee(rest), do: find_delimiter(rest, ":")

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

  @doc """
  Parse the body of an untimestamped position report (`!` or `=`), compressed
  or uncompressed, with the data type indicator already removed.

  Returns the position fields plus everything the comment carried: a data
  extension, altitude, telemetry, DAO and, on the weather symbol, a weather
  report. Coordinates that do not decode give `data_type: :malformed_position`
  and `has_position: false` rather than an error.
  """
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
    |> merge_extension(extension)
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
    |> merge_extension(compressed_cs)
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
    cleaned = cleaned_comment(weather, after_weather, after_dao)

    {weather, extension, altitude, telemetry, dao, clean_comment_text(cleaned)}
  end

  # A weather report keeps the weather scanner's remainder, not the remainder
  # left by the extensions that were pulled out of it afterwards.
  @spec cleaned_comment(map() | nil, String.t(), String.t()) :: String.t()
  defp cleaned_comment(nil, _after_weather, after_dao), do: after_dao
  defp cleaned_comment(_weather, after_weather, _after_dao), do: after_weather

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
    {%{radiorange: four_digits(d1, d2, d3, d4)}, rest}
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
        bearing: three_digits(b1, b2, b3),
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
    clamp_course(three_digits(c1, c2, c3))
  end

  defp course_value(_, _, _), do: 0

  @spec clamp_course(integer()) :: non_neg_integer()
  defp clamp_course(c) when c >= 1 and c <= 360, do: c
  defp clamp_course(_), do: 0

  @spec speed_value(byte(), byte(), byte()) :: float() | nil
  defp speed_value(s1, s2, s3) when is_digit(s1) and is_digit(s2) and is_digit(s3) do
    three_digits(s1, s2, s3) * 1.0
  end

  defp speed_value(_, _, _), do: nil

  @spec three_digits(byte(), byte(), byte()) :: non_neg_integer()
  defp three_digits(d1, d2, d3), do: (d1 - ?0) * 100 + (d2 - ?0) * 10 + d3 - ?0

  @spec four_digits(byte(), byte(), byte(), byte()) :: non_neg_integer()
  defp four_digits(d1, d2, d3, d4), do: (d1 - ?0) * 1000 + (d2 - ?0) * 100 + (d3 - ?0) * 10 + d4 - ?0

  ## Comment sub-fields

  # `/A=nnnnnn` anywhere in the comment. Uppercase `A` removes the field;
  # lowercase `a` leaves `a=nnnnnn` behind, matching reference parsers.
  # `:binary.match/3` finds the marker in C, so a comment without one is never
  # copied byte by byte.
  @spec extract_altitude(String.t()) :: {float() | nil, String.t()}
  defp extract_altitude(comment), do: scan_altitude(comment, 0)

  @spec scan_altitude(binary(), non_neg_integer()) :: {float() | nil, String.t()}
  defp scan_altitude(comment, offset) when offset <= byte_size(comment) - 3 do
    case :binary.match(comment, ["/A=", "/a="], scope: {offset, byte_size(comment) - offset}) do
      {index, 3} -> altitude_at(comment, index)
      :nomatch -> {nil, comment}
    end
  end

  defp scan_altitude(comment, _offset), do: {nil, comment}

  @spec altitude_at(binary(), non_neg_integer()) :: {float() | nil, String.t()}
  defp altitude_at(comment, index) do
    <<?/, marker, ?=, value::binary>> = binary_part(comment, index, byte_size(comment) - index)

    case take_altitude_digits(value) do
      {:ok, digits, tail} ->
        {validate_altitude(digits), altitude_remainder(marker, digits, binary_part(comment, 0, index), tail)}

      :error ->
        scan_altitude(comment, index + 1)
    end
  end

  @spec altitude_remainder(byte(), String.t(), binary(), binary()) :: String.t()
  defp altitude_remainder(?a, digits, prefix, tail), do: prefix <> "a=" <> digits <> tail
  defp altitude_remainder(_uppercase, _digits, prefix, tail), do: prefix <> tail

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
  defp validate_altitude(digits), do: digits |> String.to_integer() |> altitude_in_range()

  @spec altitude_in_range(integer()) :: float() | nil
  defp altitude_in_range(altitude) when altitude >= -10_000 and altitude <= 500_000, do: altitude * 1.0
  defp altitude_in_range(_altitude), do: nil

  # PHG anywhere in a comment, used by the compressed path where the data
  # extension cannot be anchored to the comment start.
  @spec extract_phg(String.t()) :: {String.t() | nil, String.t()}
  defp extract_phg(comment), do: scan_phg(comment, 0)

  @spec scan_phg(binary(), non_neg_integer()) :: {String.t() | nil, String.t()}
  defp scan_phg(comment, offset) when offset <= byte_size(comment) - 7 do
    case :binary.match(comment, "PHG", scope: {offset, byte_size(comment) - offset}) do
      {index, 3} -> phg_at(comment, index)
      :nomatch -> {nil, comment}
    end
  end

  defp scan_phg(comment, _offset), do: {nil, comment}

  @spec phg_at(binary(), non_neg_integer()) :: {String.t() | nil, String.t()}
  defp phg_at(comment, index) do
    value_start = index + 3

    case binary_part(comment, value_start, byte_size(comment) - value_start) do
      <<p, h, g, d, rest::binary>> when is_digit(p) and is_digit(h) and is_digit(g) and is_digit(d) ->
        {<<p, h, g, d>>, String.trim(binary_part(comment, 0, index) <> strip_phg_rate(rest))}

      _value ->
        scan_phg(comment, index + 1)
    end
  end

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

    drop_ssid_suffix(callsign, pos, tail)
  end

  # Only an all-digit tail is an SSID; `N0CALL-XYZ` keeps its suffix.
  @spec drop_ssid_suffix(String.t(), non_neg_integer(), binary()) :: String.t()
  defp drop_ssid_suffix(callsign, _pos, <<>>), do: callsign

  defp drop_ssid_suffix(callsign, pos, tail) do
    if digits_only?(tail) do
      binary_part(callsign, 0, pos)
    else
      callsign
    end
  end

  @spec digits_only?(binary()) :: boolean()
  defp digits_only?(<<>>), do: true
  defp digits_only?(<<d, rest::binary>>) when is_digit(d), do: digits_only?(rest)
  defp digits_only?(_), do: false

  # Strip the leading delimiter in front of the comment text (FAP.pm line 1211).
  # A leading space is trimmed anyway, so only `/` needs cutting first.
  @spec clean_comment_text(String.t()) :: String.t()
  defp clean_comment_text(<<"/", rest::binary>>), do: String.trim(rest)
  defp clean_comment_text(comment), do: String.trim(comment)

  ## Timestamped positions

  @doc """
  `parse_position_without_timestamp/1` with the messaging flag set, for the `=`
  data type indicator.
  """
  @spec parse_position_with_message_without_timestamp(String.t()) :: map()
  def parse_position_with_message_without_timestamp(position_data) do
    position_data
    |> parse_position_without_timestamp()
    |> Map.put(:aprs_messaging?, true)
  end

  @doc """
  Parse the body of a timestamped position report (`/` or `@`), with the data
  type indicator already removed.

  The leading seven bytes are the timestamp; the rest is parsed as an
  untimestamped position. `aprs_messaging?` is `true` for `@`.
  """
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
      :error -> try_loose_position_fallback(aprs_messaging?, time, position_data, data_type)
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
         |> Map.put(:messaging, messaging_flag(aprs_messaging?))}

      _ ->
        :error
    end
  end

  @spec try_loose_position_fallback(boolean(), String.t(), String.t(), atom()) :: map()
  defp try_loose_position_fallback(aprs_messaging?, time, raw_data, data_type) do
    case loose_position(raw_data) do
      {:ok, lat, sym_table, lon, sym_code, comment} ->
        build_fallback_position_result(aprs_messaging?, lat, lon, time, sym_table, sym_code, comment, data_type)

      :error ->
        %{
          data_type: :timestamped_position_error,
          error: "Invalid timestamped position format",
          raw_data: time <> raw_data
        }
    end
  end

  # A position whose degree or minute fields are not the spec widths, anchored
  # at the start of the field: `\d{4,5}\.\d+[NS].\d{5,6}\.\d+[EW].` followed by
  # the comment. A comment holding a line feed is rejected, as it is by the
  # reference parser's anchored regex.
  @spec loose_position(binary()) :: {:ok, binary(), binary(), binary(), binary(), binary()} | :error
  defp loose_position(data) do
    with {:ok, lat, <<sym_table, after_table::binary>>} when sym_table != ?\n <- take_loose_latitude(data),
         {:ok, lon, <<sym_code, comment::binary>>} when sym_code != ?\n <- take_loose_longitude(after_table),
         :nomatch <- :binary.match(comment, "\n") do
      {:ok, lat, <<sym_table>>, lon, <<sym_code>>, comment}
    else
      _ -> :error
    end
  end

  @spec take_loose_latitude(binary()) :: {:ok, binary(), binary()} | :error
  defp take_loose_latitude(<<d1, d2, d3, d4, d5, ?., rest::binary>>)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_digit(d4) and is_digit(d5) do
    take_loose_minutes(<<d1, d2, d3, d4, d5, ?.>>, rest, ?N, ?S)
  end

  defp take_loose_latitude(<<d1, d2, d3, d4, ?., rest::binary>>)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_digit(d4) do
    take_loose_minutes(<<d1, d2, d3, d4, ?.>>, rest, ?N, ?S)
  end

  defp take_loose_latitude(_data), do: :error

  @spec take_loose_longitude(binary()) :: {:ok, binary(), binary()} | :error
  defp take_loose_longitude(<<d1, d2, d3, d4, d5, d6, ?., rest::binary>>)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_digit(d4) and is_digit(d5) and is_digit(d6) do
    take_loose_minutes(<<d1, d2, d3, d4, d5, d6, ?.>>, rest, ?E, ?W)
  end

  defp take_loose_longitude(<<d1, d2, d3, d4, d5, ?., rest::binary>>)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_digit(d4) and is_digit(d5) do
    take_loose_minutes(<<d1, d2, d3, d4, d5, ?.>>, rest, ?E, ?W)
  end

  defp take_loose_longitude(_data), do: :error

  # At least one fraction digit, then the hemisphere byte.
  @spec take_loose_minutes(binary(), binary(), byte(), byte()) :: {:ok, binary(), binary()} | :error
  defp take_loose_minutes(acc, <<d, rest::binary>>, h1, h2) when is_digit(d) do
    take_loose_hemisphere(<<acc::binary, d>>, rest, h1, h2)
  end

  defp take_loose_minutes(_acc, _data, _h1, _h2), do: :error

  @spec take_loose_hemisphere(binary(), binary(), byte(), byte()) :: {:ok, binary(), binary()} | :error
  defp take_loose_hemisphere(acc, <<d, rest::binary>>, h1, h2) when is_digit(d) do
    take_loose_hemisphere(<<acc::binary, d>>, rest, h1, h2)
  end

  defp take_loose_hemisphere(acc, <<h, rest::binary>>, h1, h2) when h == h1 or h == h2 do
    {:ok, <<acc::binary, h>>, rest}
  end

  defp take_loose_hemisphere(_acc, _data, _h1, _h2), do: :error

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
      messaging: messaging_flag(aprs_messaging?),
      position_ambiguity: ambiguity,
      posambiguity: ambiguity,
      posresolution: UtilityHelpers.position_resolution(ambiguity)
    }
    |> merge_extension(extension)
    |> maybe_put(:telemetry, telemetry)
    |> maybe_put(:weather, weather)
    |> maybe_put(:wx, weather)
  end

  @spec messaging_flag(boolean()) :: 0 | 1
  defp messaging_flag(true), do: 1
  defp messaging_flag(false), do: 0

  ## Status, capabilities, queries and user defined data

  # Station capabilities are a comma separated list of tokens, each either a
  # bare capability or `KEY=VALUE`.
  @spec parse_station_capabilities(String.t()) :: map()
  defp parse_station_capabilities(data) do
    capabilities =
      data
      |> :binary.split(",", [:global, :trim_all])
      |> Map.new(&split_capability/1)

    %{capabilities: capabilities, raw_data: data, data_type: :station_capabilities}
  end

  @spec split_capability(String.t()) :: {String.t(), String.t() | nil}
  defp split_capability(token) do
    case :binary.split(token, "=") do
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
    case :binary.split(packet, ":") do
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
    case :binary.split(header, ">") do
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
  defp parse_network_tunnel(<<?}, tunneled_packet::binary>> = packet) do
    case parse_tunneled_packet(tunneled_packet) do
      {:ok, parsed_packet} -> {:ok, Map.merge(parsed_packet, %{tunnel_type: :network, raw_data: packet})}
      {:error, reason} -> {:error, "Invalid tunneled packet: #{reason}"}
    end
  end

  @spec parse_nested_tunnel(String.t(), non_neg_integer()) :: {:ok, map()} | {:error, String.t()}
  defp parse_nested_tunnel(packet, depth \\ 0)

  defp parse_nested_tunnel(_packet, depth) when depth > 3, do: {:error, "Maximum tunnel depth exceeded"}

  defp parse_nested_tunnel(<<?}, _::binary>> = packet, depth) do
    case parse_network_tunnel(packet) do
      {:ok, parsed_packet} -> handle_parsed_network_tunnel(parsed_packet, depth)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_nested_tunnel(_packet, _depth), do: {:error, "Not a tunneled packet"}

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
end
