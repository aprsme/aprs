defmodule Aprs.PHG do
  @moduledoc """
  PHG (Power, Height, Gain) parsing for APRS packets.
  """

  @doc """
  Parse a PHG/DFS string. Returns a map with PHG data.
  """
  @spec parse(String.t()) :: map()
  def parse(phg_str) when is_binary(phg_str) do
    parse_phg_data(phg_str)
  end

  def parse(_), do: %{data_type: :phg_data, error: "Invalid PHG data"}

  # Parse with optional # prefix
  defp parse_phg_data(<<?#, rest::binary>>), do: parse_phg_data(rest)

  # Parse PHG format
  defp parse_phg_data(<<?P, ?H, ?G, p::8, h::8, g::8, d::8, _::binary>>)
       when p >= ?0 and p <= ?9 and h >= ?0 and h <= ?9 and g >= ?0 and g <= ?9 and d >= ?0 and d <= ?9 do
    %{
      phg: <<p, h, g, d>>,
      data_type: :phg_data,
      raw_data: "PHG" <> <<p, h, g, d>>
    }
  end

  # Parse DFS format
  defp parse_phg_data(<<?D, ?F, ?S, s::8, h::8, g::8, d::8, _::binary>>)
       when s >= ?0 and s <= ?9 and h >= ?0 and h <= ?9 and g >= ?0 and g <= ?9 and d >= ?0 and d <= ?9 do
    %{
      dfs: <<s, h, g, d>>,
      data_type: :df_report,
      raw_data: "DFS" <> <<s, h, g, d>>
    }
  end

  # Invalid format
  defp parse_phg_data(data) do
    %{
      data_type: :phg_data,
      raw_data: data,
      error: "Invalid PHG/DFS format"
    }
  end
end
