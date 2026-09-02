defmodule Aprs.KISSHelpers do
  @moduledoc """
  KISS/TNC2 conversion helpers for APRS.
  """

  @doc """
  Unwrap a KISS data frame into its TNC2 payload.

  Strips the `C0 00` header and trailing `C0`, and undoes KISS byte stuffing.
  Anything that is not a KISS data frame returns an error map with
  `:error_code` and `:error_message`.
  """
  @spec kiss_to_tnc2(binary()) :: binary() | map()
  def kiss_to_tnc2(<<0xC0, 0x00, rest::binary>>) do
    tnc2 =
      rest
      |> String.trim_trailing(<<0xC0>>)
      |> String.replace(<<0xDB, 0xDC>>, <<0xC0>>)
      |> String.replace(<<0xDB, 0xDD>>, <<0xDB>>)

    tnc2
  end

  def kiss_to_tnc2(_), do: %{error_code: :packet_invalid, error_message: "Unknown error"}

  @doc """
  Wrap a TNC2 payload in a KISS data frame, escaping `C0` and `DB` bytes.
  """
  @spec tnc2_to_kiss(binary()) :: binary()
  def tnc2_to_kiss(tnc2) do
    escaped =
      tnc2
      |> String.replace(<<0xDB>>, <<0xDB, 0xDD>>)
      |> String.replace(<<0xC0>>, <<0xDB, 0xDC>>)

    <<0xC0, 0x00>> <> escaped <> <<0xC0>>
  end
end
