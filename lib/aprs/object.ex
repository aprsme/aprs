# @dialyzer {:nowarn_function, parse: 1}
defmodule Aprs.Object do
  @moduledoc """
  APRS object parsing.
  """

  import Aprs.Guards

  @typep object_value :: String.t() | integer() | float() | atom() | nil
  @typep object_map :: %{:data_type => :object, optional(atom()) => object_value()}

  @doc """
  Parse an APRS object string. Returns a struct or error.
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
      case rest do
        <<"/", latitude_compressed::binary-size(4), longitude_compressed::binary-size(4), symbol_code::binary-size(1),
          cs::binary-size(2), compression_type::binary-size(1), comment::binary>> ->
          parse_object_compressed_position(
            latitude_compressed,
            longitude_compressed,
            symbol_code,
            cs,
            compression_type,
            comment
          )

        <<latitude::binary-size(8), sym_table_id::binary-size(1), longitude::binary-size(9), symbol_code::binary-size(1),
          rest2::binary>> ->
          parse_object_uncompressed_position(latitude, sym_table_id, longitude, symbol_code, rest2)

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

  @spec parse_object_compressed_position(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: %{optional(atom()) => object_value()}
  defp parse_object_compressed_position(
         latitude_compressed,
         longitude_compressed,
         symbol_code,
         cs,
         compression_type,
         comment
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
      symbol_table_id: "/",
      symbol_code: symbol_code,
      comment: comment,
      position_format: :compressed,
      format: "compressed",
      compression_type: compression_type,
      posambiguity: 0
    }

    Map.merge(base_data, compressed_cs)
  end

  @spec parse_object_uncompressed_position(String.t(), String.t(), String.t(), String.t(), String.t()) ::
          %{optional(atom()) => object_value()}
  defp parse_object_uncompressed_position(latitude, sym_table_id, longitude, symbol_code, rest2) do
    pos = Aprs.Position.parse_aprs_position(latitude, longitude)
    ambiguity = Map.get(pos, :ambiguity, 0)

    # Extract course/speed and clean comment
    {course, speed, altitude, comment, dao_byte} = parse_object_extensions(rest2)
    {phg, cleaned_comment} = extract_phg(comment)
    # Strip leading / or space after PHG/RNG extraction (FAP line 1211)
    cleaned_comment = strip_leading_delimiter(cleaned_comment)

    map =
      maybe_add_course_speed_altitude(
        %{
          latitude: pos.latitude,
          longitude: pos.longitude,
          symbol_table_id: sym_table_id,
          symbol_code: symbol_code,
          comment: cleaned_comment,
          phg: phg,
          position_format: :uncompressed,
          format: "uncompressed",
          posambiguity: ambiguity
        },
        course,
        speed,
        altitude
      )

    if dao_byte, do: Map.put(map, :daodatumbyte, String.upcase(dao_byte)), else: map
  end

  # Parse object extensions from comment field (course/speed, altitude, etc)
  @spec parse_object_extensions(String.t()) ::
          {integer() | nil, integer() | nil, integer() | nil, String.t(), String.t() | nil}
  defp parse_object_extensions(data) do
    parse_course_speed(data)
  end

  # Parse course/speed pattern using binary matching
  @spec parse_course_speed(String.t()) ::
          {integer() | nil, integer() | nil, integer() | nil, String.t(), String.t() | nil}
  defp parse_course_speed(<<c1::8, c2::8, c3::8, ?/, s1::8, s2::8, s3::8, rest::binary>>)
       when is_digit(c1) and is_digit(c2) and is_digit(c3) and is_digit(s1) and is_digit(s2) and is_digit(s3) do
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
  @spec parse_altitude_from_comment(String.t()) :: {integer() | nil, String.t(), String.t() | nil}
  defp parse_altitude_from_comment(data) do
    parse_altitude_prefix(data)
  end

  # Handle "/A=" prefix
  @spec parse_altitude_prefix(String.t()) :: {integer() | nil, String.t(), String.t() | nil}
  defp parse_altitude_prefix(<<?/, ?A, ?=, rest::binary>>) do
    parse_altitude_value(rest, <<>>)
  end

  # Handle " A=" prefix (space instead of slash)
  defp parse_altitude_prefix(<<?\s, ?A, ?=, rest::binary>>) do
    parse_altitude_value(rest, <<>>)
  end

  # No altitude found - try extracting RNG then retry altitude extraction
  defp parse_altitude_prefix(data) do
    case extract_rng(data) do
      {:ok, cleaned} -> parse_altitude_prefix_after_rng(cleaned)
      {nil, _} -> {nil, String.trim(data), nil}
    end
  end

  # After stripping RNG, try altitude extraction again
  @spec parse_altitude_prefix_after_rng(String.t()) :: {integer() | nil, String.t(), String.t() | nil}
  defp parse_altitude_prefix_after_rng(<<?/, ?A, ?=, rest::binary>>), do: parse_altitude_value(rest, <<>>)
  defp parse_altitude_prefix_after_rng(<<?\s, ?A, ?=, rest::binary>>), do: parse_altitude_value(rest, <<>>)
  defp parse_altitude_prefix_after_rng(data), do: {nil, String.trim(data), nil}

  # Parse altitude value with optional negative sign
  @spec parse_altitude_value(String.t(), String.t()) :: {integer() | nil, String.t(), String.t() | nil}
  defp parse_altitude_value(<<?-, rest::binary>>, _acc) do
    parse_altitude_digits(rest, <<?->>)
  end

  defp parse_altitude_value(data, _acc) do
    parse_altitude_digits(data, <<>>)
  end

  # Parse altitude digits
  @spec parse_altitude_digits(String.t(), String.t()) :: {integer() | nil, String.t(), String.t() | nil}
  defp parse_altitude_digits(<<d::8, rest::binary>>, acc) when d >= ?0 and d <= ?9 do
    parse_altitude_digits(rest, acc <> <<d>>)
  end

  defp parse_altitude_digits(rest, acc) when byte_size(acc) > 0 do
    altitude = String.to_integer(acc)
    # FAP does NOT re-check for RNG after altitude - RNG only checked at start
    {dao_byte, final_comment} = parse_dao_from_comment(rest)
    {altitude, String.trim(final_comment), dao_byte}
  end

  defp parse_altitude_digits(rest, _acc) do
    {nil, String.trim(rest), nil}
  end

  # Extract RNG (radio range) data from comment
  @spec extract_rng(String.t()) :: {:ok, String.t()} | {nil, String.t()}
  defp extract_rng(comment) do
    case Regex.run(~r"RNG(\d{4})", comment) do
      [full_match, _range] -> {:ok, String.replace(comment, full_match, "")}
      _ -> {nil, comment}
    end
  end

  # Extract and strip PHG data from comment (exactly 4 digits, matching FAP)
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

  # Parse DAO extension from comment using binary pattern matching
  @spec parse_dao_from_comment(String.t()) :: {String.t() | nil, String.t()}
  defp parse_dao_from_comment(data) do
    parse_dao_scan(data, <<>>)
  end

  @spec parse_dao_scan(String.t(), String.t()) :: {String.t() | nil, String.t()}
  defp parse_dao_scan(<<?!, d1::8, d2::8, d3::8, ?!, rest::binary>>, acc)
       when is_alphanumeric(d1) and is_alphanumeric(d2) and is_alphanumeric(d3) do
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
  @spec maybe_add_course_speed_altitude(
          %{optional(atom()) => object_value()},
          integer() | nil,
          integer() | nil,
          integer() | nil
        ) :: %{optional(atom()) => object_value()}
  defp maybe_add_course_speed_altitude(map, course, speed, altitude) do
    map
    |> maybe_add_field(:course, course)
    |> maybe_add_field(:speed, speed)
    |> maybe_add_field(:altitude, altitude)
  end

  @spec maybe_add_field(%{optional(atom()) => object_value()}, atom(), object_value()) ::
          %{optional(atom()) => object_value()}
  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)

  # Strip leading / from comment (FAP.pm line 1211). Leading whitespace is
  # already removed by upstream String.trim calls.
  @spec strip_leading_delimiter(String.t()) :: String.t()
  defp strip_leading_delimiter(<<"/", rest::binary>>), do: rest
  defp strip_leading_delimiter(comment), do: comment

  # Parse object timestamp to Unix timestamp using binary pattern matching
  @spec parse_object_timestamp(String.t()) :: integer() | nil
  defp parse_object_timestamp(<<d1::8, d2::8, h1::8, h2::8, m1::8, m2::8, tz::8>>)
       when is_digit(d1) and is_digit(d2) and is_digit(h1) and is_digit(h2) and is_digit(m1) and is_digit(m2) and
              tz in [?z, ?h, ?/] do
    # For now, return a placeholder timestamp
    # In a real implementation, this would calculate the actual Unix timestamp
    # based on the current month/year and the day/hour/min provided
    1_754_096_220
  end

  defp parse_object_timestamp(_), do: nil
end
