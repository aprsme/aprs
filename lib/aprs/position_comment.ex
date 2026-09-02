defmodule Aprs.PositionComment do
  @moduledoc """
  Shared comment pipeline for object and item reports.

  Objects and items carry the same trailing data as a position report: a
  course/speed extension, `/A=` altitude, `RNG` radio range, `PHG`, a DAO
  extension and, for the weather symbol, a weather report.
  """

  import Aprs.Guards

  @minimum_altitude -10_000.0
  @maximum_altitude 500_000.0

  @doc """
  Run the comment pipeline over a parsed object or item position.

  Takes the position map with its raw `:comment`, pulls out each extension in
  the order the reference parser uses, and returns the map with `:comment`
  cleaned and `:course`, `:speed`, `:altitude`, `:radiorange`, `:phg`, `:dao`
  and `:weather` filled in where the comment carried them. Any DAO precision is
  applied to `:latitude` and `:longitude`.
  """
  @spec parse(map()) :: map()
  def parse(%{comment: comment} = position) when is_binary(comment) do
    {course, speed, comment} = extract_course_speed(position, comment)
    {altitude, comment, preserve_leading_delimiter?} = extract_altitude(comment)
    {radiorange, comment} = extract_rng(comment)
    {phg, comment} = extract_phg(comment)
    {dao, comment} = Aprs.DAO.parse(comment)

    {latitude, longitude} =
      Aprs.DAO.apply_precision(
        Map.get(position, :latitude),
        Map.get(position, :longitude),
        dao,
        Map.get(position, :posambiguity, 0)
      )

    {weather, comment} = extract_weather(Map.get(position, :symbol_code), comment)

    position
    |> Map.put(:latitude, latitude)
    |> Map.put(:longitude, longitude)
    |> Map.put(:has_position, is_number(latitude) and is_number(longitude))
    |> Map.put(:comment, clean_comment(comment, preserve_leading_delimiter?))
    |> Map.put(:phg, phg)
    |> maybe_put(:course, course)
    |> maybe_put(:speed, speed)
    |> maybe_put(:altitude, altitude)
    |> maybe_put(:radiorange, radiorange)
    |> maybe_put(:daodatumbyte, dao && dao.datum)
    |> maybe_put(:weather, weather)
  end

  def parse(position), do: position

  @spec extract_course_speed(map(), String.t()) :: {integer() | nil, float() | nil, String.t()}
  defp extract_course_speed(%{position_format: :uncompressed, symbol_code: symbol_code}, comment)
       when symbol_code != "_" do
    parse_course_speed(comment)
  end

  defp extract_course_speed(_position, comment), do: {nil, nil, comment}

  @spec parse_course_speed(String.t()) :: {integer() | nil, float() | nil, String.t()}
  defp parse_course_speed(<<c1, c2, c3, ?/, s1, s2, s3, rest::binary>>)
       when is_digit(c1) and is_digit(c2) and is_digit(c3) and is_digit(s1) and is_digit(s2) and is_digit(s3) do
    course = decimal_value(c1, c2, c3)

    if course <= 360 do
      normalized_course = if course == 0, do: 360, else: course
      {normalized_course, decimal_value(s1, s2, s3) * 1.0, rest}
    else
      {nil, nil, <<c1, c2, c3, ?/, s1, s2, s3, rest::binary>>}
    end
  end

  defp parse_course_speed(comment), do: {nil, nil, comment}

  @spec decimal_value(byte(), byte(), byte()) :: non_neg_integer()
  defp decimal_value(d1, d2, d3), do: (d1 - ?0) * 100 + (d2 - ?0) * 10 + d3 - ?0

  @spec extract_altitude(String.t()) :: {float() | nil, String.t(), boolean()}
  defp extract_altitude(comment), do: scan_altitude(comment, 0)

  @spec scan_altitude(String.t(), non_neg_integer()) :: {float() | nil, String.t(), boolean()}
  defp scan_altitude(comment, offset) when offset <= byte_size(comment) - 3 do
    scope = {offset, byte_size(comment) - offset}

    case :binary.match(comment, "/A=", scope: scope) do
      {index, 3} ->
        value_start = index + 3
        value_data = binary_part(comment, value_start, byte_size(comment) - value_start)
        altitude_at(comment, index, parse_altitude_value(value_data))

      :nomatch ->
        {nil, comment, false}
    end
  end

  defp scan_altitude(comment, _offset), do: {nil, comment, false}

  # An out-of-range altitude is not an altitude; the text stays in the comment.
  @spec altitude_at(String.t(), non_neg_integer(), {:ok, float(), String.t()} | :error) ::
          {float() | nil, String.t(), boolean()}
  defp altitude_at(comment, index, {:ok, altitude, remainder})
       when altitude >= @minimum_altitude and altitude <= @maximum_altitude do
    {altitude, remove_slice(comment, index, remainder), false}
  end

  defp altitude_at(comment, _index, {:ok, _altitude, _remainder}), do: {nil, comment, true}
  defp altitude_at(comment, index, :error), do: scan_altitude(comment, index + 1)

  @spec parse_altitude_value(String.t()) :: {:ok, float(), String.t()} | :error
  defp parse_altitude_value(<<"-", rest::binary>>) do
    parse_altitude_digits(rest, -1, 0, 0)
  end

  defp parse_altitude_value(data), do: parse_altitude_digits(data, 1, 0, 0)

  @spec parse_altitude_digits(String.t(), -1 | 1, non_neg_integer(), non_neg_integer()) ::
          {:ok, float(), String.t()} | :error
  defp parse_altitude_digits(<<digit, rest::binary>>, sign, value, count) when is_digit(digit) and count < 6 do
    parse_altitude_digits(rest, sign, value * 10 + digit - ?0, count + 1)
  end

  defp parse_altitude_digits(<<digit, _rest::binary>>, _sign, _value, 6) when is_digit(digit), do: :error

  defp parse_altitude_digits(rest, sign, value, count) when count in 5..6 do
    {:ok, sign * value * 1.0, rest}
  end

  defp parse_altitude_digits(_rest, _sign, _value, _count), do: :error

  @spec extract_rng(String.t()) :: {non_neg_integer() | nil, String.t()}
  defp extract_rng(comment) do
    case extract_four_digits(comment, "RNG", 0) do
      {nil, cleaned} -> {nil, cleaned}
      {digits, cleaned} -> {String.to_integer(digits), cleaned}
    end
  end

  @spec extract_phg(String.t()) :: {String.t() | nil, String.t()}
  defp extract_phg(comment), do: extract_four_digits(comment, "PHG", 0)

  @spec extract_four_digits(String.t(), String.t(), non_neg_integer()) :: {String.t() | nil, String.t()}
  defp extract_four_digits(comment, marker, offset) when offset <= byte_size(comment) - 7 do
    scope = {offset, byte_size(comment) - offset}

    case :binary.match(comment, marker, scope: scope) do
      {index, 3} ->
        value_start = index + 3
        value_data = binary_part(comment, value_start, byte_size(comment) - value_start)
        four_digits_at(comment, marker, index, value_data)

      :nomatch ->
        {nil, comment}
    end
  end

  defp extract_four_digits(comment, _marker, _offset), do: {nil, comment}

  @spec four_digits_at(String.t(), String.t(), non_neg_integer(), String.t()) :: {String.t() | nil, String.t()}
  defp four_digits_at(comment, marker, index, <<d1, d2, d3, d4, rest::binary>>)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_digit(d4) do
    if starts_with_digit?(rest) do
      extract_four_digits(comment, marker, index + 1)
    else
      {<<d1, d2, d3, d4>>, remove_slice(comment, index, rest)}
    end
  end

  defp four_digits_at(comment, marker, index, _value_data) do
    extract_four_digits(comment, marker, index + 1)
  end

  @spec starts_with_digit?(String.t()) :: boolean()
  defp starts_with_digit?(<<digit, _::binary>>) when is_digit(digit), do: true
  defp starts_with_digit?(_data), do: false

  @spec remove_slice(String.t(), non_neg_integer(), String.t()) :: String.t()
  defp remove_slice(comment, index, remainder) do
    binary_part(comment, 0, index) <> remainder
  end

  @spec extract_weather(String.t() | nil, String.t()) :: {map() | nil, String.t()}
  defp extract_weather("_", comment) do
    Aprs.Weather.parse_weather_data_with_remainder(comment)
  end

  defp extract_weather(_symbol_code, comment), do: {nil, comment}

  @spec clean_comment(String.t(), boolean()) :: String.t()
  defp clean_comment(comment, true), do: String.trim(comment)

  defp clean_comment(comment, false) do
    comment
    |> String.trim()
    |> strip_leading_delimiter()
    |> String.trim()
  end

  @spec strip_leading_delimiter(String.t()) :: String.t()
  defp strip_leading_delimiter(<<"/", rest::binary>>), do: rest
  defp strip_leading_delimiter(comment), do: comment

  @spec maybe_put(map(), atom(), term()) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
