defmodule Aprs.DeviceParser do
  @moduledoc """
  Extracts device identifiers from APRS packet destinations and Mic-E comments.
  """

  # Entries become function clauses in this order, so suffix-specific
  # signatures must precede prefix-only fallbacks.
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
  # Backtick suffixes must win before the broad Kenwood prefix matches.
  @current_mic_e_devices @backtick_mic_e_devices ++ @kenwood_mic_e_devices

  @doc """
  Extract the device identifier from a packet map or raw packet string.

  Standard packets use the first six destination characters. Mic-E packets
  identify their device from the DTI and the comment prefix or suffix.
  """
  @spec extract_device_identifier(term()) :: String.t() | nil
  def extract_device_identifier(%{data_type: data_type, data_extended: %{comment: comment}})
      when data_type in [:mic_e, :mic_e_old] and is_binary(comment) do
    match_mic_e_device(data_type, comment)
  end

  def extract_device_identifier(%{data_type: data_type, comment: comment})
      when data_type in [:mic_e, :mic_e_old] and is_binary(comment) do
    match_mic_e_device(data_type, comment)
  end

  def extract_device_identifier(%{data_type: data_type}) when data_type in [:mic_e, :mic_e_old], do: nil

  def extract_device_identifier(%{destination: destination}) when is_binary(destination) do
    destination_identifier(destination)
  end

  def extract_device_identifier(packet) when is_binary(packet) do
    with [_source, header] <- :binary.split(packet, ">"),
         {delimiter_index, 1} <- :binary.match(header, [",", ":"]) do
      destination =
        binary_part(header, 0, delimiter_index)

      destination_identifier(destination)
    else
      _ -> nil
    end
  end

  def extract_device_identifier(_packet), do: nil

  @spec destination_identifier(binary()) :: binary()
  defp destination_identifier(destination) when byte_size(destination) >= 6 do
    binary_part(destination, 0, 6)
  end

  defp destination_identifier(destination), do: destination

  @spec match_mic_e_device(:mic_e | :mic_e_old, binary()) :: String.t() | nil
  for %{prefix: prefix, suffix: suffix, tocall: tocall} <- @current_mic_e_devices do
    suffix_size = byte_size(suffix)

    defp match_mic_e_device(:mic_e, <<unquote(prefix), _::binary>> = comment)
         when byte_size(comment) >= unquote(suffix_size) and
                binary_part(comment, byte_size(comment) - unquote(suffix_size), unquote(suffix_size)) == unquote(suffix) do
      unquote(tocall)
    end
  end

  for %{prefix: prefix, suffix: suffix, tocall: tocall} <- @kenwood_mic_e_devices do
    suffix_size = byte_size(suffix)

    defp match_mic_e_device(:mic_e_old, <<unquote(prefix), _::binary>> = comment)
         when byte_size(comment) >= unquote(suffix_size) and
                binary_part(comment, byte_size(comment) - unquote(suffix_size), unquote(suffix_size)) == unquote(suffix) do
      unquote(tocall)
    end
  end

  defp match_mic_e_device(_data_type, _comment), do: nil
end
