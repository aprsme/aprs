defmodule Aprs.MicE do
  @moduledoc """
  Parses Mic-E encoded APRS packets.
  """

  @spec parse(binary(), String.t()) :: map()
  def parse(_data, nil) do
    %{
      latitude: nil,
      longitude: nil,
      error: "Destination is nil",
      data_type: :mic_e_error
    }
  end

  def parse(data, destination) do
    with {:ok, dest_info} <- parse_destination(destination),
         {:ok, _info_info} <- parse_information(data, dest_info.longitude_offset) do
      lat =
        Decimal.add(
          Decimal.new(dest_info.lat_degrees),
          Decimal.div(
            Decimal.add(
              Decimal.new(dest_info.lat_minutes),
              dest_info.lat_hundredths |> Decimal.new() |> Decimal.div(100)
            ),
            60
          )
        )

      lat = apply_lat_direction(lat, dest_info.lat_direction)

      # Don't need special Europe handling - use the offset from destination
      {:ok, info_info} = parse_information(data, dest_info.longitude_offset)

      lon =
        Decimal.add(
          Decimal.new(info_info.lon_degrees),
          Decimal.div(
            Decimal.add(
              Decimal.new(info_info.lon_minutes),
              info_info.lon_hundredths |> Decimal.new() |> Decimal.div(100)
            ),
            60
          )
        )

      lon = apply_lon_direction(lon, dest_info.lon_direction)

      %{
        latitude: lat,
        longitude: lon,
        message_bits: dest_info.message_bits,
        message_type: dest_info.message_type,
        speed: info_info.speed,
        course: info_info.course,
        symbol_code: info_info.symbol_code,
        symbol_table_id: info_info.symbol_table_id,
        comment: info_info.comment,
        altitude: info_info.altitude,
        data_type: :mic_e
      }
    else
      _error ->
        %{
          latitude: nil,
          longitude: nil,
          error: "Failed to parse Mic-E packet",
          data_type: :mic_e_error
        }
    end
  end

  defp parse_destination(destination) do
    if byte_size(destination) == 6 do
      try do
        <<c1, c2, c3, c4, c5, c6>> = destination

        digits = decode_destination_digits([c1, c2, c3, c4, c5, c6])
        lat_info = calculate_latitude_info(digits, c4)
        lon_info = calculate_longitude_info(c5, c6)
        message_info = extract_message_info(digits)

        {:ok, Map.merge(lat_info, Map.merge(lon_info, message_info))}
      rescue
        _ -> {:error, :invalid_character_in_destination}
      end
    else
      {:error, :invalid_destination_length}
    end
  end

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

  defp calculate_latitude_info([d1, d2, d3, d4, d5, d6], c4) do
    lat_degrees = d1.digit * 10 + d2.digit
    lat_minutes = d3.digit * 10 + d4.digit
    lat_hundredths = d5.digit * 10 + d6.digit
    lat_direction = determine_lat_direction(c4)

    %{
      lat_degrees: lat_degrees,
      lat_minutes: lat_minutes,
      lat_hundredths: lat_hundredths,
      lat_direction: lat_direction
    }
  end

  defp determine_lat_direction(c4) do
    case c4 do
      c when c in ?0..?9 -> :south
      ?L -> :south
      c when c in ?P..?Z -> :north
      _ -> :unknown
    end
  end

  defp calculate_longitude_info(c5, c6) do
    longitude_offset = determine_longitude_offset(c5)
    lon_direction = determine_lon_direction(c6)

    %{
      lon_direction: lon_direction,
      longitude_offset: longitude_offset
    }
  end

  defp determine_longitude_offset(c5) do
    case c5 do
      c when c in ?0..?9 -> 0
      ?L -> 0
      c when c in ?P..?Z -> 100
      _ -> 0
    end
  end

  defp determine_lon_direction(c6) do
    case c6 do
      c when c in ?0..?9 -> :east
      ?L -> :east
      c when c in ?P..?Z -> :west
      _ -> :unknown
    end
  end

  defp extract_message_info([d1, d2, d3, _d4, _d5, _d6]) do
    message_bits = {d1.msg_bit, d2.msg_bit, d3.msg_bit}
    message_type = determine_message_type([d1, d2, d3])

    %{
      message_bits: message_bits,
      message_type: message_type
    }
  end

  defp determine_message_type([d1, d2, d3]) do
    cond do
      d1.msg_type != nil -> d1.msg_type
      d2.msg_type != nil -> d2.msg_type
      d3.msg_type != nil -> d3.msg_type
      true -> nil
    end
  end

  defp decode_digit(char) do
    case char do
      c when c in ?0..?9 -> %{digit: c - ?0, msg_bit: 0, msg_type: nil}
      c when c in ?A..?K -> %{digit: c - ?A, msg_bit: 1, msg_type: :custom}
      ?L -> %{digit: 0, msg_bit: 0, msg_type: nil}
      c when c in ?P..?Z -> %{digit: c - ?P, msg_bit: 1, msg_type: :standard}
    end
  end

  defp parse_information(data, lon_offset) do
    if byte_size(data) < 8 do
      {:error, :invalid_information_field_length}
    else
      <<lon_deg_c, lon_min_c, lon_hmin_c, sp_c, dc_c, se_c, symbol_code, symbol_table_id, comment::binary>> = data

      lon_deg = decode_lon_deg(lon_deg_c, lon_offset)
      lon_min = decode_lon_min(lon_min_c)
      lon_hmin = lon_hmin_c - 28
      speed = decode_speed(sp_c, dc_c)
      course = decode_course(dc_c, se_c)

      # Parse altitude and clean up comment
      {altitude, cleaned_comment} = parse_altitude_and_clean_comment(comment)

      {:ok,
       %{
         lon_degrees: lon_deg,
         lon_minutes: lon_min,
         lon_hundredths: lon_hmin,
         speed: speed,
         course: course,
         symbol_code: <<symbol_code>>,
         symbol_table_id: <<symbol_table_id>>,
         comment: cleaned_comment,
         altitude: altitude
       }}
    end
  end

  defp decode_lon_deg(lon_deg_c, lon_offset) do
    # Start with base longitude from the character
    longitude = lon_deg_c - 28

    # Add offset if character 5 of destination is >= 'P' (0x50)
    longitude =
      if lon_offset == 100 do
        longitude + 100
      else
        longitude
      end

    # Apply standard adjustments
    cond do
      longitude >= 180 and longitude <= 189 ->
        longitude - 80

      longitude >= 190 and longitude <= 199 ->
        longitude - 190

      true ->
        longitude
    end
  end

  defp decode_lon_min(lon_min_c) do
    case lon_min_c - 28 do
      m when m >= 60 -> m - 60
      m -> m
    end
  end

  defp decode_speed(sp_c, dc_c) do
    sp = sp_c - 28
    dc = dc_c - 28
    speed = div(sp, 10) * 100 + rem(sp, 10) * 10 + div(dc, 10)
    speed = normalize_speed(speed)
    speed * 0.868976
  end

  defp decode_course(dc_c, se_c) do
    dc = dc_c - 28
    se = se_c - 28
    course = rem(dc, 10) * 100 + se
    normalize_course(course)
  end

  defp apply_lat_direction(lat, :south), do: Decimal.negate(lat)
  defp apply_lat_direction(lat, _), do: lat

  defp apply_lon_direction(lon, :west), do: Decimal.negate(lon)
  defp apply_lon_direction(lon, _), do: lon

  defp normalize_speed(speed) when speed >= 800, do: speed - 800
  defp normalize_speed(speed), do: speed

  defp normalize_course(course) when course >= 400, do: course - 400
  defp normalize_course(course), do: course

  @doc false
  # Parse altitude from Mic-E comment and clean up the comment
  defp parse_altitude_and_clean_comment(comment) do
    # First, remove telemetry marker and data (_%...)
    cleaned = String.replace(comment, ~r/_%.*/u, "")

    # Check for various Mic-E data extensions
    {altitude, cleaned} =
      case cleaned do
        # Standard altitude encoding: 3 chars + "}"
        <<a1, a2, a3, "}", rest::binary>> when a1 >= 33 and a1 <= 124 ->
          alt = (a1 - 33) * 91 * 91 + (a2 - 33) * 91 + (a3 - 33) - 10_000
          {alt, rest}

        # Data extension with "]" prefix followed by altitude
        <<"]", a1, a2, a3, "}", rest::binary>> when a1 >= 33 and a1 <= 124 ->
          alt = (a1 - 33) * 91 * 91 + (a2 - 33) * 91 + (a3 - 33) - 10_000
          {alt, rest}

        _ ->
          {nil, cleaned}
      end

    # If the remaining "comment" is just encoded data (no readable text), 
    # return empty string instead
    final_comment =
      if is_encoded_data_only?(cleaned) do
        ""
      else
        String.trim(cleaned)
      end

    {altitude, final_comment}
  end

  # Check if a string appears to be only encoded data (not human-readable)
  defp is_encoded_data_only?(str) do
    # Empty or very short strings
    if String.length(str) <= 1 do
      true
    else
      # Check if it starts with data indicators or contains mostly non-printable/special chars
      case str do
        <<"]", _rest::binary>> ->
          true

        <<"=", _rest::binary>> ->
          true

        _ ->
          # Check if it's mostly special characters and no spaces or readable text
          # A real comment would typically have spaces and alphanumeric characters
          printable_chars = String.replace(str, ~r/[^a-zA-Z0-9 .,!?-]/u, "")
          String.length(printable_chars) < String.length(str) / 2
      end
    end
  end
end
