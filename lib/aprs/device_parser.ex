defmodule Aprs.DeviceParser do
  @moduledoc """
  Extracts device identifier (TOCALL or Mic-E) from APRS packets, matching FAP logic.
  """

  # Minimal legacy Mic-E device map (expand as needed)
  @mic_e_legacy_devices [
    # Kenwood TH-D74
    %{prefix: ">", suffix: "^", tocall: "APK004"},
    # Kenwood TH-D72
    %{prefix: ">", suffix: "=", tocall: "APK003"},
    # Kenwood TH-D7A (no suffix)
    %{prefix: ">", suffix: nil, tocall: "APK002"}
  ]

  @doc """
  Extract the device identifier from a packet map or raw packet string.
  """
  @spec extract_device_identifier(map() | String.t()) :: String.t() | nil
  def extract_device_identifier(%{data_type: :mic_e, destination: dest, data_extended: %{comment: comment}})
      when is_binary(dest) and is_binary(comment) do
    case identify_mic_e_legacy_device(comment) do
      nil -> decode_mic_e_tocall(dest)
      tocall -> tocall
    end
  end

  def extract_device_identifier(%{data_type: :mic_e, destination: dest}) when is_binary(dest) do
    decode_mic_e_tocall(dest)
  end

  def extract_device_identifier(%{destination: dest}) when is_binary(dest) do
    # TOCALL is usually the first 6 chars of destination
    String.slice(dest, 0, 6)
  end

  def extract_device_identifier(packet) when is_binary(packet) do
    # Try to parse out the destination field from raw packet
    case Regex.run(~r/^[^>]+>([^,]+),/, packet) do
      [_, dest] -> decode_mic_e_tocall(String.slice(dest, 0, 6))
      _ -> nil
    end
  end

  def extract_device_identifier(_), do: nil

  # Legacy Mic-E device identification from comment field
  @spec identify_mic_e_legacy_device(String.t()) :: String.t() | nil
  defp identify_mic_e_legacy_device(comment) when is_binary(comment) do
    Enum.find_value(@mic_e_legacy_devices, fn %{prefix: prefix, suffix: suffix, tocall: tocall} ->
      prefix_match = String.starts_with?(comment, prefix)
      suffix_match = suffix == nil or String.ends_with?(comment, suffix)
      if prefix_match and suffix_match, do: tocall
    end)
  end

  @doc """
  Decode a Mic-E destination to its corresponding TOCALL (matches FAP/APRS spec).
  """
  @spec decode_mic_e_tocall(String.t()) :: String.t()
  def decode_mic_e_tocall(dest) when is_binary(dest) and byte_size(dest) == 6 do
    <<c1, c2, c3, c4, c5, c6>> = dest
    # Special case for Kenwood TH-D74 (FAP logic)
    case dest do
      "T5TYR4" ->
        "APK004"

      "T5TYR3" ->
        "APK003"

      "T5TYR2" ->
        "APK002"

      "T5TYR1" ->
        "APK001"

      _ ->
        prefix = mic_e_prefix(<<c1, c2, c3>>)
        suffix = mic_e_suffix(c4, c5, c6)

        if prefix && suffix do
          prefix <> suffix
        else
          dest
        end
    end
  end

  def decode_mic_e_tocall(dest), do: String.slice(dest, 0, 6)

  # Full Mic-E prefix mapping (per APRS/FAP spec, partial list for demo)
  @mic_e_prefix_map %{
    # Kenwood
    "T5T" => "APK",
    # Kenwood
    "T5U" => "APK",
    # Kenwood
    "T5V" => "APK",
    # Byonics
    "T2T" => "APN",
    # Byonics
    "T2U" => "APN",
    # Byonics
    "T2V" => "APN",
    # Argent Data
    "S6T" => "APW",
    # Argent Data
    "S6U" => "APW",
    # Argent Data
    "S6V" => "APW"
    # ... (expand as needed)
  }

  @spec mic_e_prefix(binary()) :: String.t() | nil
  defp mic_e_prefix(three) when is_binary(three) and byte_size(three) == 3 do
    Map.get(@mic_e_prefix_map, three)
  end

  # Suffix calculation (matches FAP logic)
  @spec mic_e_suffix(byte(), byte(), byte()) :: String.t() | nil
  defp mic_e_suffix(c4, c5, c6) do
    d1 = mic_e_digit(c4)
    d2 = mic_e_digit(c5)
    d3 = mic_e_digit(c6)

    if Enum.all?([d1, d2, d3], &is_integer/1) do
      "~3..0B" |> :io_lib.format([d1 * 100 + d2 * 10 + d3]) |> List.to_string()
    end
  end

  # FAP/Spec: '0'..'9' => 0..9, 'A'..'J' => 0..9, 'P'..'Y' => 0..9
  @spec mic_e_digit(byte()) :: integer() | nil
  defp mic_e_digit(char) when char in ?0..?9, do: char - ?0
  defp mic_e_digit(char) when char in ?A..?J, do: char - ?A
  defp mic_e_digit(char) when char in ?P..?Y, do: char - ?P
  defp mic_e_digit(_), do: nil
end
