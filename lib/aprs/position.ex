defmodule Aprs.Position do
  @moduledoc """
  Uncompressed position parsing for APRS packets.
  """

  import Aprs.Guards

  alias Aprs.Types.Position

  @doc """
  Parse an uncompressed APRS position string. Returns a Position struct or nil.
  """
  @spec parse(String.t()) :: Position.t() | nil
  def parse(position_str) do
    # Example: "4903.50N/07201.75W>comment"
    case position_str do
      <<lat::binary-size(8), sym_table_id::binary-size(1), lon::binary-size(9), sym_code::binary-size(1),
        comment::binary>> ->
        %{latitude: lat_val, longitude: lon_val} = parse_aprs_position(lat, lon)
        ambiguity = calculate_position_ambiguity(lat, lon)
        dao_data = parse_dao_extension(comment)

        %Position{
          latitude: lat_val,
          longitude: lon_val,
          timestamp: nil,
          symbol_table_id: sym_table_id,
          symbol_code: sym_code,
          comment: comment,
          aprs_messaging?: false,
          compressed?: false,
          position_ambiguity: ambiguity,
          dao: dao_data
        }

      _ ->
        nil
    end
  end

  @doc false
  @spec parse_aprs_position(String.t(), String.t()) :: %{
          latitude: Decimal.t() | nil,
          longitude: Decimal.t() | nil,
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

  # Parse latitude into {degree_int, minute_string, direction}
  # Accepts spaces in minute digits per APRS position ambiguity spec
  # FAP regex: (\d{2})([0-7 ][0-9 ]\.[0-9 ]{2})([NnSs])
  @spec parse_latitude_components(binary()) ::
          {:ok, non_neg_integer(), <<_::40>>, :north | :south} | :error
  defp parse_latitude_components(<<d1::8, d2::8, m1::8, m2::8, ?., f1::8, f2::8, dir::8>>)
       when is_digit(d1) and is_digit(d2) and is_minute_tens(m1) and is_digit_or_space(m2) and is_digit_or_space(f1) and
              is_digit_or_space(f2) and dir in [?N, ?n, ?S, ?s] do
    deg = (d1 - ?0) * 10 + (d2 - ?0)

    if deg <= 89 do
      {:ok, deg, <<m1, m2, ?., f1, f2>>, dir_atom(dir)}
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
    deg = (d1 - ?0) * 100 + (d2 - ?0) * 10 + (d3 - ?0)

    if deg <= 179 do
      {:ok, deg, <<m1, m2, ?., f1, f2>>, dir_atom(dir)}
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
        ) :: {Decimal.t(), Decimal.t()}
  defp calculate_position_with_ambiguity(lat_deg, lat_min, lat_dir, lon_deg, lon_min, lon_dir, ambiguity) do
    {lat_minutes, lon_minutes} = adjusted_minutes(lat_min, lon_min, ambiguity)
    lat = lat_deg + lat_minutes / 60
    lon = lon_deg + lon_minutes / 60
    lat = apply_direction(lat, lat_dir)
    lon = apply_direction(lon, lon_dir)
    {Decimal.from_float(lat), Decimal.from_float(lon)}
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

  defp adjusted_minutes(<<m1, m2, ?., f1, f2>>, <<lm1, lm2, ?., lf1, lf2>>, 0) do
    # Full precision
    lat_m = space_to_zero(m1) * 10 + space_to_zero(m2) + (space_to_zero(f1) * 10 + space_to_zero(f2)) / 100
    lon_m = space_to_zero(lm1) * 10 + space_to_zero(lm2) + (space_to_zero(lf1) * 10 + space_to_zero(lf2)) / 100
    {lat_m, lon_m}
  end

  @spec space_to_zero(non_neg_integer()) :: non_neg_integer()
  defp space_to_zero(?\s), do: 0
  defp space_to_zero(d) when d >= ?0 and d <= ?9, do: d - ?0

  @spec apply_direction(float(), :north | :south | :east | :west) :: float()
  defp apply_direction(val, :south), do: -val
  defp apply_direction(val, :west), do: -val
  defp apply_direction(val, _), do: val

  @ambiguity_levels %{
    {0, 0} => 0,
    {1, 1} => 1,
    {2, 2} => 2,
    {3, 3} => 3,
    {4, 4} => 4
  }

  @doc false
  @spec calculate_position_ambiguity(String.t(), String.t()) :: non_neg_integer()
  def calculate_position_ambiguity(latitude, longitude) do
    lat_spaces = count_spaces(latitude)
    lon_spaces = count_spaces(longitude)
    Map.get(@ambiguity_levels, {lat_spaces, lon_spaces}, 0)
  end

  @doc false
  @spec count_spaces(String.t()) :: non_neg_integer()
  def count_spaces(str) do
    str |> String.graphemes() |> Enum.count(&(&1 == " "))
  end

  @doc false
  @spec parse_dao_extension(String.t()) ::
          %{lat_dao: String.t(), lon_dao: String.t(), datum: String.t()} | nil
  def parse_dao_extension(comment) do
    case Regex.run(~r/!([A-Za-z])([A-Za-z])([A-Za-z])!/, comment) do
      [_, lat_dao, lon_dao, _] ->
        %{
          lat_dao: lat_dao,
          lon_dao: lon_dao,
          datum: "WGS84"
        }

      _ ->
        nil
    end
  end

  @spec from_aprs(String.t(), String.t()) :: %{
          latitude: Decimal.t() | nil,
          longitude: Decimal.t() | nil,
          ambiguity: non_neg_integer()
        }
  def from_aprs(lat_str, lon_str), do: parse_aprs_position(lat_str, lon_str)

  @spec from_decimal(integer() | String.t() | Decimal.t(), integer() | String.t() | Decimal.t()) ::
          %{latitude: Decimal.t(), longitude: Decimal.t()}
  def from_decimal(lat, lon) do
    %{latitude: Decimal.new(lat), longitude: Decimal.new(lon)}
  end
end
