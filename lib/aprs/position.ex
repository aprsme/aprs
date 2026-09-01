defmodule Aprs.Position do
  @moduledoc """
  Uncompressed position parsing for APRS packets.
  """

  import Aprs.Guards

  @doc false
  @spec parse_aprs_position(String.t(), String.t()) :: %{
          latitude: float() | nil,
          longitude: float() | nil,
          ambiguity: non_neg_integer()
        }
  def parse_aprs_position(lat_str, lon_str) do
    with {:ok, lat_deg, lat_min, lat_dir} <- parse_latitude_components(lat_str),
         {:ok, lon_deg, lon_min, lon_dir} <- parse_longitude_components(lon_str) do
      ambiguity = count_minute_ambiguity(lat_min)
      {lat, lon} = calculate_position_with_ambiguity(lat_deg, lat_min, lat_dir, lon_deg, lon_min, lon_dir, ambiguity)
      %{latitude: lat, longitude: lon, ambiguity: ambiguity}
    else
      _ -> %{latitude: nil, longitude: nil, ambiguity: 0}
    end
  end

  @doc """
  Returns true when an eight-byte field is a syntactically valid APRS latitude.

  Spaces are accepted in the minute and fraction digits (position ambiguity)
  and either case of hemisphere letter is allowed, matching reference parsers.
  """
  @spec valid_latitude_format?(binary()) :: boolean()
  def valid_latitude_format?(<<d1::8, d2::8, m1::8, m2::8, ?., f1::8, f2::8, dir::8>>)
      when is_digit(d1) and is_digit(d2) and is_minute_tens(m1) and is_digit_or_space(m2) and is_digit_or_space(f1) and
             is_digit_or_space(f2) and dir in [?N, ?n, ?S, ?s] do
    true
  end

  def valid_latitude_format?(_), do: false

  @doc """
  Returns true when a nine-byte field is a syntactically valid APRS longitude.
  """
  @spec valid_longitude_format?(binary()) :: boolean()
  def valid_longitude_format?(<<d1::8, d2::8, d3::8, m1::8, m2::8, ?., f1::8, f2::8, dir::8>>)
      when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_minute_tens(m1) and is_digit_or_space(m2) and
             is_digit_or_space(f1) and is_digit_or_space(f2) and dir in [?E, ?e, ?W, ?w] do
    true
  end

  def valid_longitude_format?(_), do: false

  # Parse latitude into {degree_int, minute_string, direction}
  # Accepts spaces in minute digits per APRS position ambiguity spec
  # FAP regex: (\d{2})([0-7 ][0-9 ]\.[0-9 ]{2})([NnSs])
  @spec parse_latitude_components(binary()) ::
          {:ok, non_neg_integer(), <<_::40>>, :north | :south} | :error
  defp parse_latitude_components(<<d1::8, d2::8, m1::8, m2::8, ?., f1::8, f2::8, dir::8>>)
       when is_digit(d1) and is_digit(d2) and is_minute_tens(m1) and is_digit_or_space(m2) and is_digit_or_space(f1) and
              is_digit_or_space(f2) and dir in [?N, ?n, ?S, ?s] do
    minutes = <<m1, m2, ?., f1, f2>>
    deg = (d1 - ?0) * 10 + (d2 - ?0)

    if deg + minute_value(minutes) / 60 <= 90 do
      {:ok, deg, minutes, dir_atom(dir)}
    else
      :error
    end
  end

  defp parse_latitude_components(_), do: :error

  # Parse longitude into {degree_int, minute_string, direction}
  # FAP regex: (\d{3})([0-7 ][0-9 ]\.[0-9 ]{2})([EeWw])
  @spec parse_longitude_components(binary()) ::
          {:ok, non_neg_integer(), <<_::40>>, :east | :west} | :error
  defp parse_longitude_components(<<d1::8, d2::8, d3::8, m1::8, m2::8, ?., f1::8, f2::8, dir::8>>)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_minute_tens(m1) and is_digit_or_space(m2) and
              is_digit_or_space(f1) and is_digit_or_space(f2) and dir in [?E, ?e, ?W, ?w] do
    minutes = <<m1, m2, ?., f1, f2>>
    deg = (d1 - ?0) * 100 + (d2 - ?0) * 10 + (d3 - ?0)

    if deg + minute_value(minutes) / 60 <= 180 do
      {:ok, deg, minutes, dir_atom(dir)}
    else
      :error
    end
  end

  defp parse_longitude_components(_), do: :error

  @spec dir_atom(non_neg_integer()) :: :north | :south | :east | :west
  defp dir_atom(d) when d in [?N, ?n], do: :north
  defp dir_atom(d) when d in [?S, ?s], do: :south
  defp dir_atom(d) when d in [?E, ?e], do: :east
  defp dir_atom(d) when d in [?W, ?w], do: :west

  # Count trailing spaces in minute string (with period removed) for ambiguity level
  # FAP: $tmplat =~ s/\.//; if ($tmplat =~ /^(\d{0,4})( {0,4})$/) { posambiguity = length($2) }
  @spec count_minute_ambiguity(<<_::40>>) :: non_neg_integer()
  defp count_minute_ambiguity(<<m1, m2, ?., f1, f2>>) do
    count_trailing_spaces([m1, m2, f1, f2], 0)
  end

  @spec count_trailing_spaces(list(non_neg_integer()), non_neg_integer()) :: non_neg_integer()
  defp count_trailing_spaces(digits, _count) do
    digits
    |> Enum.reverse()
    |> Enum.take_while(&(&1 == ?\s))
    |> length()
  end

  # Calculate lat/lon with FAP's midpoint centering based on ambiguity
  @spec calculate_position_with_ambiguity(
          non_neg_integer(),
          <<_::40>>,
          :north | :south,
          non_neg_integer(),
          <<_::40>>,
          :east | :west,
          non_neg_integer()
        ) :: {float(), float()}
  defp calculate_position_with_ambiguity(lat_deg, lat_min, lat_dir, lon_deg, lon_min, lon_dir, ambiguity) do
    {lat_minutes, lon_minutes} = adjusted_minutes(lat_min, lon_min, ambiguity)
    lat = lat_deg + lat_minutes / 60
    lon = lon_deg + lon_minutes / 60
    lat = apply_direction(lat, lat_dir)
    lon = apply_direction(lon, lon_dir)
    {lat / 1, lon / 1}
  end

  # FAP's ambiguity-based minute adjustment
  @spec adjusted_minutes(<<_::40>>, <<_::40>>, 0..4) :: {float(), float()}
  defp adjusted_minutes(_lat_min, _lon_min, 4) do
    # Disregard minutes entirely, add 30' (0.5 degree equivalent)
    {30.0, 30.0}
  end

  defp adjusted_minutes(<<m1, _m2, ?., _f1, _f2>>, <<lm1, _lm2, ?., _lf1, _lf2>>, 3) do
    # Use first minute digit + "5"
    lat_m = space_to_zero(m1) * 10 + 5
    lon_m = space_to_zero(lm1) * 10 + 5
    {lat_m * 1.0, lon_m * 1.0}
  end

  defp adjusted_minutes(<<m1, m2, ?., _f1, _f2>>, <<lm1, lm2, ?., _lf1, _lf2>>, 2) do
    # Use whole minutes only, add 0.5
    lat_m = space_to_zero(m1) * 10 + space_to_zero(m2) + 0.5
    lon_m = space_to_zero(lm1) * 10 + space_to_zero(lm2) + 0.5
    {lat_m, lon_m}
  end

  defp adjusted_minutes(<<m1, m2, ?., f1, _f2>>, <<lm1, lm2, ?., lf1, _lf2>>, 1) do
    # Use minutes to one decimal place, add 0.05
    lat_m = space_to_zero(m1) * 10 + space_to_zero(m2) + space_to_zero(f1) / 10 + 0.05
    lon_m = space_to_zero(lm1) * 10 + space_to_zero(lm2) + space_to_zero(lf1) / 10 + 0.05
    {lat_m, lon_m}
  end

  defp adjusted_minutes(lat_min, lon_min, 0), do: {minute_value(lat_min), minute_value(lon_min)}

  @spec minute_value(<<_::40>>) :: float()
  defp minute_value(<<m1, m2, ?., f1, f2>>) do
    space_to_zero(m1) * 10 + space_to_zero(m2) + (space_to_zero(f1) * 10 + space_to_zero(f2)) / 100
  end

  @spec space_to_zero(non_neg_integer()) :: non_neg_integer()
  defp space_to_zero(?\s), do: 0
  defp space_to_zero(d) when d >= ?0 and d <= ?9, do: d - ?0

  @spec apply_direction(float(), :north | :south | :east | :west) :: float()
  defp apply_direction(val, :south), do: -val
  defp apply_direction(val, :west), do: -val
  defp apply_direction(val, _), do: val
end
