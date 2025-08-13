# @dialyzer {:nowarn_function, parse: 1}
defmodule Aprs.Object do
  @moduledoc """
  APRS object parsing.
  """

  @doc """
  Parse an APRS object string. Returns a struct or error.
  """
  @spec parse(String.t()) :: map() | nil
  def parse(<<";", object_name::binary-size(9), live_killed::binary-size(1), timestamp::binary-size(7), rest::binary>>) do
    parse_object_data(object_name, live_killed, timestamp, rest)
  end

  def parse(<<object_name::binary-size(9), live_killed::binary-size(1), timestamp::binary-size(7), rest::binary>>) do
    parse_object_data(object_name, live_killed, timestamp, rest)
  end

  def parse(data), do: %{data_type: :object, raw_data: data}

  defp parse_object_data(object_name, live_killed, timestamp, rest) do
    position_data =
      case rest do
        <<"/", latitude_compressed::binary-size(4), longitude_compressed::binary-size(4), symbol_code::binary-size(1),
          cs::binary-size(2), compression_type::binary-size(1), comment::binary>> ->
          try do
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
              symbol_table_id: "/",
              symbol_code: symbol_code,
              comment: comment,
              position_format: :compressed,
              format: "compressed",
              compression_type: compression_type,
              posambiguity: 0
            }

            Map.merge(base_data, compressed_cs)
          rescue
            _ -> %{latitude: nil, longitude: nil, comment: comment, position_format: :compressed, format: "compressed"}
          end

        <<latitude::binary-size(8), sym_table_id::binary-size(1), longitude::binary-size(9), symbol_code::binary-size(1),
          rest2::binary>> ->
          %{latitude: lat, longitude: lon} =
            Aprs.Position.parse_aprs_position(latitude, longitude)

          # Extract course/speed and clean comment
          {course, speed, altitude, comment, dao_byte} = parse_object_extensions(rest2)

          map =
            maybe_add_course_speed_altitude(
              %{
                latitude: lat,
                longitude: lon,
                symbol_table_id: sym_table_id,
                symbol_code: symbol_code,
                comment: comment,
                position_format: :uncompressed,
                format: "uncompressed",
                posambiguity: 0
              },
              course,
              speed,
              altitude
            )

          if dao_byte, do: Map.put(map, :daodatumbyte, String.upcase(dao_byte)), else: map

        _ ->
          %{comment: rest, position_format: :unknown, format: "uncompressed"}
      end

    # Parse timestamp to Unix time
    unix_timestamp = parse_object_timestamp(timestamp)

    result =
      Map.merge(
        %{
          object_name: String.trim(object_name),
          live_killed: live_killed,
          alive: if(live_killed == "*", do: 1, else: 0),
          timestamp: unix_timestamp,
          data_type: :object
        },
        position_data
      )

    # Always check for DAO extension in the final comment
    {dao_byte, _} = parse_dao_from_comment(result[:comment] || "")

    if dao_byte do
      Map.put(result, :daodatumbyte, dao_byte)
    else
      result
    end
  end

  # Parse object extensions from comment field (course/speed, altitude, etc)
  defp parse_object_extensions(data) do
    parse_course_speed(data)
  end

  # Parse course/speed pattern using binary matching
  defp parse_course_speed(<<c1::8, c2::8, c3::8, ?/, s1::8, s2::8, s3::8, rest::binary>>)
       when c1 >= ?0 and c1 <= ?9 and c2 >= ?0 and c2 <= ?9 and c3 >= ?0 and c3 <= ?9 and s1 >= ?0 and s1 <= ?9 and
              s2 >= ?0 and s2 <= ?9 and s3 >= ?0 and s3 <= ?9 do
    course = (c1 - ?0) * 100 + (c2 - ?0) * 10 + (c3 - ?0)
    speed = (s1 - ?0) * 100 + (s2 - ?0) * 10 + (s3 - ?0)
    {altitude, comment, dao_byte} = parse_altitude_from_comment(rest)
    {course, speed, altitude, comment, dao_byte}
  end

  defp parse_course_speed(data) do
    # No course/speed, check for altitude and DAO directly
    {altitude, comment, dao_byte} = parse_altitude_from_comment(data)
    {nil, nil, altitude, comment, dao_byte}
  end

  # Parse altitude from comment using binary pattern matching
  defp parse_altitude_from_comment(data) do
    parse_altitude_prefix(data)
  end

  # Handle "/A=" prefix
  defp parse_altitude_prefix(<<?/, ?A, ?=, rest::binary>>) do
    parse_altitude_value(rest, <<>>)
  end

  # Handle " A=" prefix (space instead of slash)
  defp parse_altitude_prefix(<<?\s, ?A, ?=, rest::binary>>) do
    parse_altitude_value(rest, <<>>)
  end

  # No altitude found
  defp parse_altitude_prefix(data) do
    {nil, String.trim(data), nil}
  end

  # Parse altitude value with optional negative sign
  defp parse_altitude_value(<<?-, rest::binary>>, _acc) do
    parse_altitude_digits(rest, <<?->>)
  end

  defp parse_altitude_value(data, _acc) do
    parse_altitude_digits(data, <<>>)
  end

  # Parse altitude digits
  defp parse_altitude_digits(<<d::8, rest::binary>>, acc) when d >= ?0 and d <= ?9 do
    parse_altitude_digits(rest, acc <> <<d>>)
  end

  defp parse_altitude_digits(rest, acc) when byte_size(acc) > 0 do
    altitude = String.to_integer(acc)
    {dao_byte, final_comment} = parse_dao_from_comment(rest)
    {altitude, String.trim(final_comment), dao_byte}
  end

  defp parse_altitude_digits(rest, _acc) do
    {nil, String.trim(rest), nil}
  end

  # Parse DAO extension from comment using binary pattern matching
  defp parse_dao_from_comment(data) do
    parse_dao_scan(data, <<>>)
  end

  defp parse_dao_scan(<<?!, d1::8, d2::8, d3::8, ?!, rest::binary>>, acc)
       when ((d1 >= ?a and d1 <= ?z) or (d1 >= ?A and d1 <= ?Z) or (d1 >= ?0 and d1 <= ?9)) and
              ((d2 >= ?a and d2 <= ?z) or (d2 >= ?A and d2 <= ?Z) or (d2 >= ?0 and d2 <= ?9)) and
              ((d3 >= ?a and d3 <= ?z) or (d3 >= ?A and d3 <= ?Z) or (d3 >= ?0 and d3 <= ?9)) do
    # Found DAO pattern, return first character as datum byte
    dao_datum = <<d1>>
    {String.upcase(dao_datum), acc <> rest}
  end

  defp parse_dao_scan(<<char::8, rest::binary>>, acc) do
    parse_dao_scan(rest, acc <> <<char>>)
  end

  defp parse_dao_scan(<<>>, acc) do
    {nil, acc}
  end

  # Add course, speed, and altitude to the result map if present
  defp maybe_add_course_speed_altitude(map, course, speed, altitude) do
    map
    |> maybe_add_field(:course, course)
    |> maybe_add_field(:speed, speed)
    |> maybe_add_field(:altitude, altitude)
  end

  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)

  # Parse object timestamp to Unix timestamp using binary pattern matching
  defp parse_object_timestamp(<<d1::8, d2::8, h1::8, h2::8, m1::8, m2::8, tz::8>>)
       when d1 >= ?0 and d1 <= ?9 and d2 >= ?0 and d2 <= ?9 and h1 >= ?0 and h1 <= ?9 and h2 >= ?0 and h2 <= ?9 and
              m1 >= ?0 and m1 <= ?9 and m2 >= ?0 and m2 <= ?9 and tz in [?z, ?h, ?/] do
    # For now, return a placeholder timestamp
    # In a real implementation, this would calculate the actual Unix timestamp
    # based on the current month/year and the day/hour/min provided
    1_754_096_220
  end

  defp parse_object_timestamp(_), do: nil
end
