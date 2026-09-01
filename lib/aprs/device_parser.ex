defmodule Aprs.DeviceParser do
  @moduledoc """
  Extracts device identifiers from APRS packet destinations and Mic-E comments.
  """

  @kenwood_mic_e_devices [
    %{prefix: ">", suffix: "^", tocall: "APK004"},
    %{prefix: ">", suffix: "=", tocall: "APK003"},
    %{prefix: "]", suffix: "=", tocall: "APK102"},
    %{prefix: ">", suffix: "", tocall: "APK002"},
    %{prefix: "]", suffix: "", tocall: "APK101"}
  ]

  @backtick_mic_e_devices [
    %{prefix: "", suffix: "_\"", tocall: "APY350"},
    %{prefix: "", suffix: "_#", tocall: "APY008"},
    %{prefix: "", suffix: "_$", tocall: "APY01D"},
    %{prefix: "", suffix: "_%", tocall: "APY400"},
    %{prefix: "", suffix: "_(", tocall: "APY02D"}
  ]
  @current_mic_e_devices @backtick_mic_e_devices ++ @kenwood_mic_e_devices

  @doc """
  Extract the device identifier from a packet map or raw packet string.

  Standard packets use the first six destination characters. Mic-E packets
  identify their device from the DTI and the comment prefix or suffix.
  """
  @spec extract_device_identifier(map() | String.t()) :: String.t() | nil
  def extract_device_identifier(%{data_type: data_type, data_extended: %{comment: comment}})
      when data_type in [:mic_e, :mic_e_old] and is_binary(comment) do
    identify_mic_e_device(data_type, comment)
  end

  def extract_device_identifier(%{data_type: data_type, comment: comment})
      when data_type in [:mic_e, :mic_e_old] and is_binary(comment) do
    identify_mic_e_device(data_type, comment)
  end

  def extract_device_identifier(%{data_type: data_type}) when data_type in [:mic_e, :mic_e_old], do: nil

  def extract_device_identifier(%{destination: destination}) when is_binary(destination) do
    String.slice(destination, 0, 6)
  end

  def extract_device_identifier(packet) when is_binary(packet) do
    with [_source, header] <- :binary.split(packet, ">"),
         {delimiter_index, 1} <- :binary.match(header, [",", ":"]) do
      header
      |> binary_part(0, delimiter_index)
      |> String.slice(0, 6)
    else
      _ -> nil
    end
  end

  def extract_device_identifier(_packet), do: nil

  @spec identify_mic_e_device(:mic_e | :mic_e_old, String.t()) :: String.t() | nil
  defp identify_mic_e_device(:mic_e, comment) do
    match_mic_e_device(comment, @current_mic_e_devices)
  end

  defp identify_mic_e_device(:mic_e_old, comment) do
    match_mic_e_device(comment, @kenwood_mic_e_devices)
  end

  @spec match_mic_e_device(String.t(), [map()]) :: String.t() | nil
  defp match_mic_e_device(comment, devices) do
    Enum.find_value(devices, fn %{prefix: prefix, suffix: suffix, tocall: tocall} ->
      if String.starts_with?(comment, prefix) and String.ends_with?(comment, suffix), do: tocall
    end)
  end
end
