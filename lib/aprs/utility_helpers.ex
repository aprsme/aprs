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

  @spec validate_timestamp(String.t()) :: integer() | nil
  def validate_timestamp(time) when is_binary(time) do
    # Parse APRS timestamp formats
    case String.length(time) do
      # DHM format (day/hour/minute)
      6 ->
        case Regex.run(~r/^(\d{2})(\d{2})(\d{2})$/, time) do
          [_, day, hour, minute] ->
            # Convert to Unix timestamp (approximate - using current month/year)
            now = DateTime.utc_now()
            
            day_int = String.to_integer(day)
            hour_int = String.to_integer(hour)
            minute_int = String.to_integer(minute)
            
            # Validate components
            if day_int >= 1 and day_int <= 31 and
               hour_int >= 0 and hour_int <= 23 and 
               minute_int >= 0 and minute_int <= 59 do
              case Date.new(now.year, now.month, day_int) do
                {:ok, date} ->
                  {:ok, time} = Time.new(hour_int, minute_int, 0)
                  {:ok, datetime} = DateTime.new(date, time)
                  DateTime.to_unix(datetime)
                _ ->
                  nil
              end
            else
              nil
            end

          _ ->
            nil
        end

      # HMS format (hour/minute/second) or Zulu time
      7 ->
        cond do
          String.ends_with?(time, "h") ->
            case Regex.run(~r/^(\d{2})(\d{2})(\d{2})h$/, time) do
              [_, hour, minute, second] ->
                # Convert to Unix timestamp (today's date)
                
                hour_int = String.to_integer(hour)
                minute_int = String.to_integer(minute)
                second_int = String.to_integer(second)
                
                # Validate time components
                if hour_int >= 0 and hour_int <= 23 and 
                   minute_int >= 0 and minute_int <= 59 and
                   second_int >= 0 and second_int <= 59 do
                  {:ok, time} = Time.new(hour_int, minute_int, second_int)
                  {:ok, datetime} = DateTime.new(Date.utc_today(), time)
                  DateTime.to_unix(datetime)
                else
                  nil
                end

              _ ->
                nil
            end

          String.ends_with?(time, "z") ->
            case Regex.run(~r/^(\d{2})(\d{2})(\d{2})z$/, time) do
              [_, day, hour, minute] ->
                # Convert to Unix timestamp (current month/year)
                now = DateTime.utc_now()
                
                day_int = String.to_integer(day)
                hour_int = String.to_integer(hour)
                minute_int = String.to_integer(minute)
                
                # Validate components
                if day_int >= 1 and day_int <= 31 and
                   hour_int >= 0 and hour_int <= 23 and 
                   minute_int >= 0 and minute_int <= 59 do
                  case Date.new(now.year, now.month, day_int) do
                    {:ok, date} ->
                      {:ok, time} = Time.new(hour_int, minute_int, 0)
                      {:ok, datetime} = DateTime.new(date, time)
                      DateTime.to_unix(datetime)
                    _ ->
                      nil
                  end
                else
                  nil
                end

              _ ->
                nil
            end

          true ->
            nil
        end

      _ ->
        nil
    end
  end

  def validate_timestamp(_), do: nil

  @doc """
  Calculate position resolution in meters based on ambiguity level.

  Ambiguity levels and their resolutions:
  - 0: No ambiguity - 18.52 meters (0.01 minute)
  - 1: 0.1 minute - 185.2 meters
  - 2: 1 minute - 1852 meters  
  - 3: 10 minutes - 18520 meters
  - 4: 1 degree - 111120 meters

  For compressed positions, the resolution is calculated differently.
  """
  @spec calculate_position_resolution(integer()) :: float()
  def calculate_position_resolution(ambiguity) when is_integer(ambiguity) do
    case ambiguity do
      # 0.01 minute at equator
      0 -> 18.52
      # 0.1 minute
      1 -> 185.2
      # 1 minute
      2 -> 1852.0
      # 10 minutes
      3 -> 18_520.0
      # 1 degree (60 minutes)
      4 -> 111_120.0
      # Default to no ambiguity
      _ -> 18.52
    end
  end

  @doc """
  Calculate position resolution for compressed positions.
  Compressed positions have much finer resolution.
  """
  @spec calculate_compressed_position_resolution() :: float()
  def calculate_compressed_position_resolution do
    # Compressed positions have approximately 0.291 meter resolution
    0.291
  end
end
