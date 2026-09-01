defmodule Aprs.NMEAHelpers do
  @moduledoc """
  NMEA coordinate, sentence, and Ultimeter packet parsing helpers for APRS.
  """

  alias Aprs.Convert

  @feet_per_metre 3.280839895

  @spec parse_nmea_coordinate(term(), term()) :: {:ok, float()} | {:error, String.t()}
  def parse_nmea_coordinate(value, direction) when is_binary(value) and is_binary(direction) do
    case Float.parse(value) do
      {coord, _} ->
        degrees = trunc(coord / 100)
        minutes = coord - degrees * 100
        result = degrees + minutes / 60.0
        normalized = apply_nmea_direction(result, direction)
        handle_coordinate_result(normalized)

      _ ->
        {:error, "Invalid coordinate value"}
    end
  end

  def parse_nmea_coordinate(_, _), do: {:error, "Invalid coordinate format"}

  @spec parse_nmea_sentence(term()) :: {:ok, map()} | {:error, String.t()}
  def parse_nmea_sentence(<<"$", sentence::binary>>), do: parse_sentence(sentence, true)
  def parse_nmea_sentence(sentence) when is_binary(sentence), do: parse_sentence(sentence, false)
  def parse_nmea_sentence(_), do: {:error, "Invalid NMEA input"}

  @spec handle_coordinate_result({:error, String.t()} | float()) ::
          {:ok, float()} | {:error, String.t()}
  defp handle_coordinate_result(coord) when is_tuple(coord), do: coord
  defp handle_coordinate_result(coord), do: {:ok, coord}

  @spec apply_nmea_direction(float(), String.t()) :: float() | {:error, String.t()}
  defp apply_nmea_direction(coord, "N"), do: coord
  defp apply_nmea_direction(coord, "S"), do: -coord
  defp apply_nmea_direction(coord, "E"), do: coord
  defp apply_nmea_direction(coord, "W"), do: -coord
  defp apply_nmea_direction(_, _), do: {:error, "Invalid coordinate direction"}

  @spec parse_sentence(binary(), boolean()) :: {:ok, map()} | {:error, String.t()}
  defp parse_sentence(<<"ULTW", payload::binary>>, _had_dollar), do: parse_ultimeter(payload)

  defp parse_sentence(<<talker1, talker2, sentence_type::binary-size(3), ",", fields::binary>>, _had_dollar)
       when talker1 >= ?A and talker1 <= ?Z and talker2 >= ?A and talker2 <= ?Z do
    parsed_fields =
      fields
      |> remove_checksum()
      |> String.split(",", trim: false)

    parse_sentence_type(sentence_type, parsed_fields)
  end

  defp parse_sentence(_sentence, true), do: {:error, "Unsupported NMEA sentence type"}
  defp parse_sentence(_sentence, false), do: {:error, "Not an NMEA sentence"}

  @spec remove_checksum(binary()) :: binary()
  defp remove_checksum(fields) do
    case :binary.split(fields, "*") do
      [body, _checksum] -> body
      [body] -> body
    end
  end

  @spec parse_sentence_type(binary(), [String.t()]) :: {:ok, map()} | {:error, String.t()}
  defp parse_sentence_type("RMC", fields), do: parse_rmc(fields)
  defp parse_sentence_type("GGA", fields), do: parse_gga(fields)
  defp parse_sentence_type("GLL", fields), do: parse_gll(fields)
  defp parse_sentence_type("VTG", fields), do: parse_vtg(fields)
  defp parse_sentence_type("WPL", fields), do: parse_wpl(fields)
  defp parse_sentence_type(_sentence_type, _fields), do: {:error, "Unsupported NMEA sentence type"}

  @spec parse_rmc([String.t()]) :: {:ok, map()} | {:error, String.t()}
  defp parse_rmc([_time, "V" | _rest]), do: {:error, "RMC void status"}

  defp parse_rmc([_time, "A", lat, lat_dir, lon, lon_dir, speed, course | _rest]) do
    with {:ok, latitude} <- parse_nmea_coordinate(lat, lat_dir),
         {:ok, longitude} <- parse_nmea_coordinate(lon, lon_dir),
         {:ok, speed_knots} <- parse_speed(speed),
         {:ok, course_degrees} <- parse_course(course) do
      {:ok,
       :rmc
       |> base_result(latitude, longitude)
       |> Map.put(:speed, speed_knots)
       |> Map.put(:course, course_degrees)}
    end
  end

  defp parse_rmc(_fields), do: {:error, "Invalid RMC sentence"}

  @spec parse_gga([String.t()]) :: {:ok, map()} | {:error, String.t()}
  defp parse_gga([_time, _lat, _lat_dir, _lon, _lon_dir, "0" | _rest]), do: {:error, "GGA no fix"}

  defp parse_gga([_time, lat, lat_dir, lon, lon_dir, fix_quality, _satellites, _hdop, altitude, "M" | _rest]) do
    with :ok <- validate_gga_fix(fix_quality),
         {:ok, latitude} <- parse_nmea_coordinate(lat, lat_dir),
         {:ok, longitude} <- parse_nmea_coordinate(lon, lon_dir),
         {:ok, altitude_metres} <- parse_optional_float(altitude, "Invalid GGA altitude") do
      altitude_feet =
        if is_nil(altitude_metres) do
          nil
        else
          altitude_metres * @feet_per_metre
        end

      {:ok, :gga |> base_result(latitude, longitude) |> Map.put(:altitude, altitude_feet)}
    end
  end

  defp parse_gga(_fields), do: {:error, "Invalid GGA sentence"}

  @spec validate_gga_fix(String.t()) :: :ok | {:error, String.t()}
  defp validate_gga_fix(fix_quality) do
    case Integer.parse(fix_quality) do
      {quality, ""} when quality > 0 -> :ok
      {0, ""} -> {:error, "GGA no fix"}
      _other -> {:error, "Invalid GGA fix quality"}
    end
  end

  @spec parse_gll([String.t()]) :: {:ok, map()} | {:error, String.t()}
  defp parse_gll([_lat, _lat_dir, _lon, _lon_dir, _time, "V" | _rest]), do: {:error, "GLL void status"}

  defp parse_gll([lat, lat_dir, lon, lon_dir, _time, "A" | _rest]) do
    with {:ok, latitude} <- parse_nmea_coordinate(lat, lat_dir),
         {:ok, longitude} <- parse_nmea_coordinate(lon, lon_dir) do
      {:ok, base_result(:gll, latitude, longitude)}
    end
  end

  defp parse_gll(_fields), do: {:error, "Invalid GLL sentence"}

  @spec parse_vtg([String.t()]) :: {:ok, map()} | {:error, String.t()}
  defp parse_vtg([course, "T", _magnetic_course, "M", speed, "N", _speed_kph, "K" | _rest]) do
    with {:ok, course_degrees} <- parse_course(course),
         {:ok, speed_knots} <- parse_speed(speed) do
      {:ok,
       :vtg
       |> base_result(nil, nil)
       |> Map.put(:speed, speed_knots)
       |> Map.put(:course, course_degrees)}
    end
  end

  defp parse_vtg(_fields), do: {:error, "Invalid VTG sentence"}

  @spec parse_wpl([String.t()]) :: {:ok, map()} | {:error, String.t()}
  defp parse_wpl([lat, lat_dir, lon, lon_dir, waypoint_name | _rest]) do
    with {:ok, latitude} <- parse_nmea_coordinate(lat, lat_dir),
         {:ok, longitude} <- parse_nmea_coordinate(lon, lon_dir) do
      {:ok, :wpl |> base_result(latitude, longitude) |> Map.put(:waypoint_name, waypoint_name)}
    end
  end

  defp parse_wpl(_fields), do: {:error, "Invalid WPL sentence"}

  @spec base_result(atom(), float() | nil, float() | nil) :: map()
  defp base_result(nmea_type, latitude, longitude) do
    %{
      latitude: latitude,
      longitude: longitude,
      speed: nil,
      course: nil,
      altitude: nil,
      nmea_type: nmea_type,
      format: :nmea
    }
  end

  @spec parse_speed(String.t()) :: {:ok, float() | nil} | {:error, String.t()}
  defp parse_speed(value) do
    case parse_optional_float(value, "Invalid speed") do
      {:ok, nil} -> {:ok, nil}
      {:ok, speed} when speed >= 0 -> {:ok, speed}
      _other -> {:error, "Invalid speed"}
    end
  end

  @spec parse_course(String.t()) :: {:ok, pos_integer() | nil} | {:error, String.t()}
  defp parse_course(value) do
    case parse_optional_float(value, "Invalid course") do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, course} when course >= 0 and course <= 360 ->
        degrees = trunc(course)
        {:ok, if(degrees == 0, do: 360, else: degrees)}

      _other ->
        {:error, "Invalid course"}
    end
  end

  @spec parse_optional_float(String.t(), String.t()) ::
          {:ok, float() | nil} | {:error, String.t()}
  defp parse_optional_float("", _error), do: {:ok, nil}

  defp parse_optional_float(value, error) do
    case Float.parse(value) do
      {number, ""} -> {:ok, number}
      _other -> {:error, error}
    end
  end

  @spec parse_ultimeter(binary()) :: {:ok, map()} | {:error, String.t()}
  defp parse_ultimeter(payload) do
    with {:ok, normalized_payload} <- normalize_ultimeter_payload(payload) do
      {:ok, ultimeter_result(normalized_payload)}
    end
  end

  @spec normalize_ultimeter_payload(binary()) :: {:ok, binary()} | {:error, String.t()}
  defp normalize_ultimeter_payload(payload) when byte_size(payload) == 48, do: {:ok, payload}
  defp normalize_ultimeter_payload(payload) when byte_size(payload) == 46, do: {:ok, payload <> "00"}
  defp normalize_ultimeter_payload(payload) when byte_size(payload) == 44, do: {:ok, payload <> "----"}
  defp normalize_ultimeter_payload(payload) when byte_size(payload) == 40, do: {:ok, payload <> "--------"}
  defp normalize_ultimeter_payload(_payload), do: {:error, "Invalid Ultimeter sentence"}

  @spec ultimeter_result(binary()) :: map()
  defp ultimeter_result(
         <<peak::binary-size(4), direction::binary-size(4), out_temp::binary-size(4), rain_total::binary-size(4),
           barometer::binary-size(4), in_temp::binary-size(4), out_hum::binary-size(4), in_hum::binary-size(4),
           date::binary-size(4), time::binary-size(4), rain_today::binary-size(4), average::binary-size(4)>>
       ) do
    weather = %{
      wind_peak: peak |> decode_signed_field() |> convert_wind(),
      wind_direction: decode_wind_direction(direction),
      outdoor_temperature: out_temp |> decode_signed_field() |> convert_temperature(),
      rain_total: rain_total |> decode_signed_field() |> scale_non_negative(0.01),
      barometer: barometer |> decode_signed_field() |> scale_non_negative(0.1),
      indoor_temperature: in_temp |> decode_signed_field() |> convert_temperature(),
      outdoor_humidity: out_hum |> decode_signed_field() |> convert_humidity(),
      indoor_humidity: in_hum |> decode_signed_field() |> convert_humidity(),
      date: date |> decode_signed_field() |> validate_range(0, 365),
      time: time |> decode_signed_field() |> validate_range(0, 1439),
      rain_today: rain_today |> decode_signed_field() |> scale_non_negative(0.01),
      wind_average: average |> decode_signed_field() |> convert_wind()
    }

    :ultimeter
    |> base_result(nil, nil)
    |> Map.put(:weather, weather)
  end

  @spec decode_signed_field(binary()) :: integer() | nil
  defp decode_signed_field("----"), do: nil

  defp decode_signed_field(field) do
    case Integer.parse(field, 16) do
      {value, ""} when value >= 0x8000 -> value - 0x10000
      {value, ""} -> value
      _other -> nil
    end
  end

  @spec decode_wind_direction(binary()) :: float() | nil
  defp decode_wind_direction(field) do
    case decode_signed_field(field) do
      value when is_integer(value) and value >= 0 and value <= 255 ->
        value * 360.0 / 256.0

      _other ->
        nil
    end
  end

  @spec convert_wind(integer() | nil) :: float() | nil
  defp convert_wind(value) when is_integer(value) and value >= 0, do: Convert.wind(value, :ultimeter, :mph)

  defp convert_wind(_value), do: nil

  @spec convert_temperature(integer() | nil) :: float() | nil
  defp convert_temperature(value) when is_integer(value), do: Convert.temp(value, :ultimeter, :f)
  defp convert_temperature(_value), do: nil

  @spec scale_non_negative(integer() | nil, float()) :: float() | nil
  defp scale_non_negative(value, scale) when is_integer(value) and value >= 0, do: value * scale
  defp scale_non_negative(_value, _scale), do: nil

  @spec convert_humidity(integer() | nil) :: float() | nil
  defp convert_humidity(value) when is_integer(value) and value >= 0 and value <= 1000, do: value * 0.1
  defp convert_humidity(_value), do: nil

  @spec validate_range(integer() | nil, integer(), integer()) :: integer() | nil
  defp validate_range(value, minimum, maximum) when is_integer(value) and value >= minimum and value <= maximum, do: value

  defp validate_range(_value, _minimum, _maximum), do: nil
end
