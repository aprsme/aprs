defmodule Aprs.MicE do
  @moduledoc """
  Parses Mic-E encoded APRS packets.
  """
  @metres_to_feet 3.280839895

  @typep digit_info :: %{
           digit: non_neg_integer(),
           msg_bit: 0 | 1,
           msg_type: nil | :custom | :standard,
           ambiguous: boolean()
         }

  @typep lat_direction :: :north | :south | :unknown
  @typep lon_direction :: :east | :west | :unknown

  @typep lat_info :: %{
           lat_degrees: non_neg_integer(),
           lat_minutes: non_neg_integer(),
           lat_hundredths: non_neg_integer(),
           lat_direction: lat_direction(),
           position_ambiguity: non_neg_integer()
         }

  @typep lon_info :: %{
           lon_direction: lon_direction(),
           longitude_offset: 0 | 100
         }

  @typep message_info :: %{
           message_bits: {0 | 1, 0 | 1, 0 | 1},
           message_type: nil | :custom | :standard
         }

  @typep dest_info :: %{
           lat_degrees: non_neg_integer(),
           lat_minutes: non_neg_integer(),
           lat_hundredths: non_neg_integer(),
           lat_direction: lat_direction(),
           position_ambiguity: non_neg_integer(),
           lon_direction: lon_direction(),
           longitude_offset: 0 | 100,
           message_bits: {0 | 1, 0 | 1, 0 | 1},
           message_type: nil | :custom | :standard
         }

  @typep info_field :: %{
           lon_degrees: integer(),
           lon_minutes: non_neg_integer(),
           lon_hundredths: integer(),
           speed: float(),
           course: non_neg_integer(),
           symbol_code: String.t(),
           symbol_table_id: String.t(),
           comment: String.t(),
           altitude: float() | nil,
           dao: Aprs.DAO.t() | nil,
           telemetry: map() | nil
         }

  @doc """
  Parse a Mic-E information field against its destination callsign.

  The destination carries the latitude, the message bits, the longitude offset
  and the hemispheres, so it is required; a `nil` destination gives a map with
  `data_type: :mic_e_error`. The information field supplies the longitude,
  speed, course and symbol, and the comment supplies the altitude, the device
  identifier, a DAO extension and base-91 telemetry.
  """
  @spec parse(binary(), String.t() | nil, :mic_e | :mic_e_old) :: map()
  def parse(data, destination, data_type \\ :mic_e)

  def parse(_data, nil, _data_type) do
    %{
      latitude: nil,
      longitude: nil,
      has_position: false,
      error: "Destination is nil",
      data_type: :mic_e_error
    }
  end

  def parse(data, destination, data_type) do
    with {:ok, dest_info} <- parse_destination(destination),
         {:ok, info_info} <- parse_information(data, dest_info.longitude_offset) do
      ambiguity = dest_info.position_ambiguity

      lat =
        dest_info.lat_degrees +
          (dest_info.lat_minutes + dest_info.lat_hundredths / 100) / 60

      lat = apply_lat_direction(lat, dest_info.lat_direction)

      {lon_min, lon_hmin} = apply_lon_centering(info_info.lon_minutes, info_info.lon_hundredths, ambiguity)

      lon =
        info_info.lon_degrees + (lon_min + lon_hmin / 100) / 60

      lon = apply_lon_direction(lon, dest_info.lon_direction)
      {lat, lon} = Aprs.DAO.apply_precision(lat, lon, info_info.dao, ambiguity)

      %{
        latitude: lat,
        longitude: lon,
        has_position: is_number(lat) and is_number(lon),
        message_bits: dest_info.message_bits,
        message_type: dest_info.message_type,
        speed: info_info.speed,
        course: info_info.course,
        symbol_code: info_info.symbol_code,
        symbol_table_id: info_info.symbol_table_id,
        comment: info_info.comment,
        altitude: info_info.altitude,
        data_type: data_type,
        format: :mice,
        messaging: 0,
        position_ambiguity: ambiguity,
        posresolution: Aprs.UtilityHelpers.position_resolution(ambiguity)
      }
      |> put_optional(:dao, info_info.dao)
      |> put_optional(:daodatumbyte, info_info.dao && info_info.dao.datum)
      |> put_optional(:telemetry, info_info.telemetry)
    else
      _error ->
        %{
          latitude: nil,
          longitude: nil,
          has_position: false,
          error: "Failed to parse Mic-E packet",
          data_type: :mic_e_error
        }
    end
  end

  @spec put_optional(map(), atom(), term()) :: map()
  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  @spec parse_destination(binary()) :: {:ok, dest_info()} | {:error, atom()}
  defp parse_destination(destination) do
    parse_destination_by_size(destination, byte_size(destination))
  end

  @spec parse_destination_by_size(binary(), integer()) :: {:ok, map()} | {:error, atom()}
  defp parse_destination_by_size(<<c1, c2, c3, c4, c5, c6>>, 6) do
    digits = decode_destination_digits([c1, c2, c3, c4, c5, c6])
    lat_info = calculate_latitude_info(digits, c4)
    lon_info = calculate_longitude_info(c5, c6)
    message_info = extract_message_info(digits)

    {:ok, Map.merge(lat_info, Map.merge(lon_info, message_info))}
  rescue
    _ -> {:error, :invalid_character_in_destination}
  end

  defp parse_destination_by_size(_, _), do: {:error, :invalid_destination_length}

  @spec decode_destination_digits([byte()]) :: [digit_info()]
  defp decode_destination_digits([c1, c2, c3, d4, d5, d6]) do
    [
      decode_digit(c1),
      decode_digit(c2),
      decode_digit(c3),
      decode_digit(d4),
      decode_digit(d5),
      decode_digit(d6)
    ]
  end

  @spec calculate_latitude_info([digit_info()], byte()) :: lat_info()
  defp calculate_latitude_info([d1, d2, d3, d4, d5, d6], c4) do
    lat_degrees = d1.digit * 10 + d2.digit
    lat_minutes = d3.digit * 10 + d4.digit
    lat_hundredths = d5.digit * 10 + d6.digit
    lat_direction = determine_lat_direction(c4)
    ambiguity = count_ambiguity([d1, d2, d3, d4, d5, d6])

    {lat_minutes, lat_hundredths} = apply_lat_centering(lat_minutes, lat_hundredths, d3.digit, d5.digit, ambiguity)

    %{
      lat_degrees: lat_degrees,
      lat_minutes: lat_minutes,
      lat_hundredths: lat_hundredths,
      lat_direction: lat_direction,
      position_ambiguity: ambiguity
    }
  end

  @spec count_ambiguity([digit_info()]) :: non_neg_integer()
  defp count_ambiguity(digits) do
    Enum.count(digits, & &1.ambiguous)
  end

  # FAP centering: adjust latitude minutes/hundredths based on ambiguity level
  @spec apply_lat_centering(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {non_neg_integer(), non_neg_integer()}
  defp apply_lat_centering(minutes, hundredths, _d3_digit, _d5_digit, 0), do: {minutes, hundredths}
  defp apply_lat_centering(minutes, _hundredths, _d3_digit, d5_digit, 1), do: {minutes, d5_digit * 10 + 5}
  defp apply_lat_centering(minutes, _hundredths, _d3_digit, _d5_digit, 2), do: {minutes, 50}
  defp apply_lat_centering(_minutes, _hundredths, d3_digit, _d5_digit, 3), do: {d3_digit * 10 + 5, 0}
  defp apply_lat_centering(_minutes, _hundredths, _d3_digit, _d5_digit, _), do: {30, 0}

  # FAP centering: adjust longitude minutes/hundredths based on ambiguity level
  @spec apply_lon_centering(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  defp apply_lon_centering(minutes, hundredths, 0), do: {minutes, hundredths}
  defp apply_lon_centering(minutes, hundredths, 1), do: {minutes, div(hundredths, 10) * 10 + 5}
  defp apply_lon_centering(minutes, _hundredths, 2), do: {minutes, 50}
  defp apply_lon_centering(minutes, _hundredths, 3), do: {div(minutes, 10) * 10 + 5, 0}
  defp apply_lon_centering(_minutes, _hundredths, _), do: {30, 0}

  @spec determine_lat_direction(byte()) :: lat_direction()
  defp determine_lat_direction(c) when c in ?0..?9, do: :south
  defp determine_lat_direction(?L), do: :south
  defp determine_lat_direction(c) when c in ?P..?Z, do: :north
  defp determine_lat_direction(_), do: :unknown

  @spec calculate_longitude_info(byte(), byte()) :: lon_info()
  defp calculate_longitude_info(c5, c6) do
    longitude_offset = determine_longitude_offset(c5)
    lon_direction = determine_lon_direction(c6)

    %{
      lon_direction: lon_direction,
      longitude_offset: longitude_offset
    }
  end

  @spec determine_longitude_offset(byte()) :: 0 | 100
  defp determine_longitude_offset(c) when c in ?P..?Z, do: 100
  defp determine_longitude_offset(_), do: 0

  @spec determine_lon_direction(byte()) :: lon_direction()
  defp determine_lon_direction(c) when c in ?0..?9, do: :east
  defp determine_lon_direction(?L), do: :east
  defp determine_lon_direction(c) when c in ?P..?Z, do: :west
  defp determine_lon_direction(_), do: :unknown

  @spec extract_message_info([digit_info()]) :: message_info()
  defp extract_message_info([d1, d2, d3, _d4, _d5, _d6]) do
    message_bits = {d1.msg_bit, d2.msg_bit, d3.msg_bit}
    message_type = determine_message_type([d1, d2, d3])

    %{
      message_bits: message_bits,
      message_type: message_type
    }
  end

  @spec determine_message_type([digit_info()]) :: nil | :custom | :standard
  defp determine_message_type([d1, d2, d3]) do
    Enum.find_value([d1, d2, d3], fn d -> d.msg_type end)
  end

  @spec decode_digit(byte()) :: digit_info()
  defp decode_digit(c) when c in ?0..?9, do: %{digit: c - ?0, msg_bit: 0, msg_type: nil, ambiguous: false}
  defp decode_digit(c) when c in ?A..?J, do: %{digit: c - ?A, msg_bit: 1, msg_type: :custom, ambiguous: false}
  defp decode_digit(?K), do: %{digit: 0, msg_bit: 1, msg_type: :custom, ambiguous: true}
  defp decode_digit(?L), do: %{digit: 0, msg_bit: 0, msg_type: nil, ambiguous: true}
  defp decode_digit(c) when c in ?P..?Y, do: %{digit: c - ?P, msg_bit: 1, msg_type: :standard, ambiguous: false}
  defp decode_digit(?Z), do: %{digit: 0, msg_bit: 1, msg_type: :standard, ambiguous: true}

  @spec parse_information(binary(), non_neg_integer()) :: {:ok, info_field()} | {:error, atom()}
  defp parse_information(data, _lon_offset) when byte_size(data) < 8 do
    {:error, :invalid_information_field_length}
  end

  defp parse_information(
         <<lon_deg_c, lon_min_c, lon_hmin_c, sp_c, dc_c, se_c, symbol_code, symbol_table_id, comment::binary>>,
         lon_offset
       ) do
    comment_info = parse_comment(comment)

    {:ok,
     %{
       lon_degrees: decode_lon_deg(lon_deg_c, lon_offset),
       lon_minutes: decode_lon_min(lon_min_c),
       lon_hundredths: lon_hmin_c - 28,
       speed: decode_speed(sp_c, dc_c),
       course: decode_course(dc_c, se_c),
       symbol_code: <<symbol_code>>,
       symbol_table_id: <<symbol_table_id>>,
       comment: comment_info.comment,
       altitude: comment_info.altitude,
       dao: comment_info.dao,
       telemetry: comment_info.telemetry
     }}
  end

  @spec decode_lon_deg(byte(), non_neg_integer()) :: integer()
  defp decode_lon_deg(lon_deg_c, lon_offset) do
    # Start with base longitude from the character
    (lon_deg_c - 28)
    |> add_longitude_offset(lon_offset)
    |> apply_longitude_adjustment()
  end

  @spec add_longitude_offset(integer(), non_neg_integer()) :: integer()
  defp add_longitude_offset(longitude, 100), do: longitude + 100
  defp add_longitude_offset(longitude, _), do: longitude

  @spec apply_longitude_adjustment(integer()) :: integer()
  defp apply_longitude_adjustment(longitude) when longitude >= 180 and longitude <= 189, do: longitude - 80
  defp apply_longitude_adjustment(longitude) when longitude >= 190 and longitude <= 199, do: longitude - 190
  defp apply_longitude_adjustment(longitude), do: longitude

  @spec decode_lon_min(byte()) :: non_neg_integer()
  defp decode_lon_min(lon_min_c) do
    normalize_minutes(lon_min_c - 28)
  end

  @spec normalize_minutes(integer()) :: integer()
  defp normalize_minutes(m) when m >= 60, do: m - 60
  defp normalize_minutes(m), do: m

  @spec decode_speed(byte(), byte()) :: float()
  defp decode_speed(sp_c, dc_c) do
    sp = sp_c - 28
    dc = dc_c - 28
    speed = div(sp, 10) * 100 + rem(sp, 10) * 10 + div(dc, 10)

    normalize_speed(speed) * 1.0
  end

  @spec decode_course(byte(), byte()) :: non_neg_integer()
  defp decode_course(dc_c, se_c) do
    dc = dc_c - 28
    se = se_c - 28
    course = rem(dc, 10) * 100 + se
    normalize_course(course)
  end

  @spec apply_lat_direction(float(), lat_direction()) :: float()
  defp apply_lat_direction(lat, :south), do: -lat
  defp apply_lat_direction(lat, _), do: lat

  @spec apply_lon_direction(float(), lon_direction()) :: float()
  defp apply_lon_direction(lon, :west), do: -lon
  defp apply_lon_direction(lon, _), do: lon

  @spec normalize_speed(non_neg_integer()) :: non_neg_integer()
  defp normalize_speed(speed) when speed >= 800, do: speed - 800
  defp normalize_speed(speed), do: speed

  @spec normalize_course(integer()) :: non_neg_integer()
  defp normalize_course(course) when course >= 400 do
    normalized = course - 400
    if normalized >= 0 and normalized <= 360, do: normalized, else: 0
  end

  defp normalize_course(course) when course >= 0 and course <= 360, do: course
  defp normalize_course(_invalid_course), do: 0

  @new_type_codes [?>, ?]]
  @old_type_codes [?`, ?']

  @spec parse_comment(binary()) :: %{
          altitude: float() | nil,
          comment: String.t(),
          dao: Aprs.DAO.t() | nil,
          telemetry: map() | nil
        }
  defp parse_comment(comment) do
    {device_type, rest} = extract_new_type_code(comment)
    rest = strip_old_type_code(rest)
    {altitude, rest} = extract_mic_e_altitude(rest)
    {telemetry, rest} = Aprs.TelemetryFromComment.extract_telemetry_from_comment(rest)
    {dao, rest} = Aprs.DAO.parse(rest)

    cleaned_comment = prepend_type_code(device_type, clean_trailing_markers(rest))

    %{
      altitude: altitude,
      comment: cleaned_comment,
      dao: dao,
      telemetry: telemetry
    }
  end

  @spec extract_new_type_code(binary()) :: {String.t() | nil, binary()}
  defp extract_new_type_code(<<code, rest::binary>>) when code in @new_type_codes do
    {<<code>>, rest}
  end

  defp extract_new_type_code(<<code, rest::binary>>) when code in @old_type_codes do
    {<<code>>, rest}
  end

  defp extract_new_type_code(comment), do: {nil, comment}

  @spec strip_old_type_code(binary()) :: binary()
  defp strip_old_type_code(<<code, rest::binary>>) when code in @old_type_codes, do: rest
  defp strip_old_type_code(rest), do: rest

  @spec extract_mic_e_altitude(binary()) :: {float() | nil, binary()}
  defp extract_mic_e_altitude(<<a1, a2, a3, ?}, rest::binary>>) when a1 in 33..123 and a2 in 33..123 and a3 in 33..123 do
    altitude_metres = (a1 - 33) * 91 * 91 + (a2 - 33) * 91 + (a3 - 33) - 10_000
    {altitude_metres * @metres_to_feet, rest}
  end

  defp extract_mic_e_altitude(rest), do: {nil, rest}

  # Prepend device type code to cleaned comment
  @spec prepend_type_code(String.t() | nil, String.t()) :: String.t()
  defp prepend_type_code(nil, cleaned), do: String.trim(cleaned)
  defp prepend_type_code(code, cleaned), do: String.trim_trailing(code <> cleaned)

  # Clean up common trailing markers from comments (FAP only strips ^ -- and  --)
  @spec clean_trailing_markers(String.t()) :: String.t()
  defp clean_trailing_markers(str) do
    str
    |> String.replace(~r/\^ --$/u, "")
    |> String.replace(~r/ --$/u, "")
  end
end
