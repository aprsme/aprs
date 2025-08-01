defmodule Aprs.PHG do
  @moduledoc """
  PHG (Power, Height, Gain) parsing for APRS packets.
  """

  @doc """
  Parse a PHG/DFS string. Returns a map with PHG data.
  """
  @spec parse(String.t()) :: map()
  def parse(phg_str) when is_binary(phg_str) do
    case Regex.run(~r"^PHG(\d)(\d)(\d)(\d)", phg_str) do
      [_full_match, p, h, g, d] ->
        # Return the PHG string directly for compatibility
        %{
          phg: p <> h <> g <> d,
          data_type: :phg_data,
          raw_data: phg_str
        }

      _ ->
        case Regex.run(~r"^DFS(\d)(\d)(\d)(\d)", phg_str) do
          [_full_match, s, h, g, d] ->
            %{
              dfs: s <> h <> g <> d,
              data_type: :df_report,
              raw_data: phg_str
            }

          _ ->
            %{
              data_type: :phg_data,
              raw_data: phg_str,
              error: "Invalid PHG/DFS format"
            }
        end
    end
  end

  def parse(_), do: %{data_type: :phg_data, error: "Invalid PHG data"}
end
