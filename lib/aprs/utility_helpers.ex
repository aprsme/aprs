defmodule Aprs.UtilityHelpers do
  @moduledoc """
  Utility and ambiguity helpers for APRS.
  """

  @spec count_spaces(String.t()) :: non_neg_integer()
  def count_spaces(str) do
    # More efficient than String.graphemes() |> Enum.count()
    str |> String.to_charlist() |> Enum.count(fn c -> c == ?\s end)
  end

  @spec count_leading_braces(binary()) :: non_neg_integer()
  def count_leading_braces(packet), do: count_leading_braces(packet, 0)

  @spec count_leading_braces(binary(), non_neg_integer()) :: non_neg_integer()
  def count_leading_braces(<<"}", rest::binary>>, count), do: count_leading_braces(rest, count + 1)

  def count_leading_braces(_packet, count), do: count

  @spec calculate_position_ambiguity(String.t(), String.t()) :: 0..4
  def calculate_position_ambiguity(latitude, longitude) do
    lat_spaces = count_spaces(latitude)
    lon_spaces = count_spaces(longitude)

    # Use a more efficient lookup
    case {lat_spaces, lon_spaces} do
      {0, 0} -> 0
      {1, 1} -> 1
      {2, 2} -> 2
      {3, 3} -> 3
      {4, 4} -> 4
      _ -> 0
    end
  end

  @spec find_matches(Regex.t(), String.t()) :: map()
  def find_matches(regex, text) do
    case Regex.names(regex) do
      [] ->
        matches = Regex.run(regex, text)

        Enum.reduce(Enum.with_index(matches), %{}, fn {match, index}, acc ->
          Map.put(acc, index, match)
        end)

      _ ->
        Regex.named_captures(regex, text)
    end
  end

  @spec validate_position_data(String.t(), String.t()) ::
          {:ok, {Decimal.t(), Decimal.t()}} | {:error, :invalid_position}
  def validate_position_data(latitude, longitude) do
    import Decimal, only: [new: 1, add: 2, negate: 1]

    lat =
      case Regex.run(~r/^(\d{2})(\d{2}\.\d+)([NS])$/, latitude) do
        [_, degrees, minutes, direction] ->
          lat_val = add(new(degrees), Decimal.div(new(minutes), new("60")))
          if direction == "S", do: negate(lat_val), else: lat_val

        _ ->
          nil
      end

    lon =
      case Regex.run(~r/^(\d{3})(\d{2}\.\d+)([EW])$/, longitude) do
        [_, degrees, minutes, direction] ->
          lon_val = add(new(degrees), Decimal.div(new(minutes), new("60")))
          if direction == "W", do: negate(lon_val), else: lon_val

        _ ->
          nil
      end

    if is_struct(lat, Decimal) and is_struct(lon, Decimal) do
      {:ok, {lat, lon}}
    else
      {:error, :invalid_position}
    end
  end

  @spec validate_timestamp(any()) :: nil
  def validate_timestamp(_time), do: nil
end
