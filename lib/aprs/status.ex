defmodule Aprs.Status do
  @moduledoc """
  APRS status parsing.
  """

  import Aprs.Guards

  alias Aprs.UtilityHelpers

  # Maidenhead field letters are A..R; subsquare letters are A..X.
  defguardp is_grid_field(b) when (b >= ?A and b <= ?R) or (b >= ?a and b <= ?r)
  defguardp is_grid_subsquare(b) when (b >= ?A and b <= ?X) or (b >= ?a and b <= ?x)

  @doc """
  Parses an APRS status string.
  """
  @spec parse(String.t()) :: map()
  def parse(<<">", status::binary>>), do: parse_status(status)
  def parse(data) when is_binary(data), do: parse_status(data)

  @spec parse_status(binary()) :: map()
  defp parse_status(data) do
    {timestamp, data} = extract_timestamp(data)
    {grid_locator, symbol_table_id, symbol_code, data} = extract_grid_locator(data)
    {beam_heading, beam_power, status_text} = extract_beam(data)

    %{data_type: :status, status_text: String.trim(status_text)}
    |> put_optional(:timestamp, timestamp)
    |> put_optional(:grid_locator, grid_locator)
    |> put_optional(:symbol_table_id, symbol_table_id)
    |> put_optional(:symbol_code, symbol_code)
    |> put_optional(:beam_heading, beam_heading)
    |> put_optional(:beam_power, beam_power)
  end

  @spec extract_timestamp(binary()) :: {integer() | nil, binary()}
  defp extract_timestamp(<<d1, d2, h1, h2, m1, m2, suffix, rest::binary>> = data)
       when is_digit(d1) and is_digit(d2) and is_digit(h1) and is_digit(h2) and is_digit(m1) and is_digit(m2) and
              suffix in [?z, ?h, ?/] do
    case UtilityHelpers.parse_timestamp(<<d1, d2, h1, h2, m1, m2, suffix>>) do
      nil -> {nil, data}
      timestamp -> {timestamp, rest}
    end
  end

  defp extract_timestamp(data), do: {nil, data}

  @spec extract_grid_locator(binary()) ::
          {String.t() | nil, String.t() | nil, String.t() | nil, binary()}
  defp extract_grid_locator(<<a, b, d1, d2, rest::binary>> = data)
       when is_grid_field(a) and is_grid_field(b) and is_digit(d1) and is_digit(d2) do
    extend_grid_locator(<<a, b, d1, d2>>, rest, data)
  end

  defp extract_grid_locator(data), do: {nil, nil, nil, data}

  @spec extend_grid_locator(String.t(), binary(), binary()) ::
          {String.t() | nil, String.t() | nil, String.t() | nil, binary()}
  defp extend_grid_locator(grid, <<e, f, table, code, rest::binary>>, _data)
       when is_grid_subsquare(e) and is_grid_subsquare(f) do
    {grid <> <<e, f>>, <<table>>, <<code>>, rest}
  end

  defp extend_grid_locator(grid, <<table, code, rest::binary>>, _data) do
    {grid, <<table>>, <<code>>, rest}
  end

  defp extend_grid_locator(_grid, _rest, data), do: {nil, nil, nil, data}

  @spec extract_beam(binary()) :: {non_neg_integer() | nil, pos_integer() | nil, binary()}
  defp extract_beam(data) when byte_size(data) >= 3 do
    status_size = byte_size(data) - 3

    case data do
      <<status_text::binary-size(^status_size), ?^, heading, power>>
      when (is_digit(heading) or heading in ?A..?Z) and
             (is_digit(power) or power in ?A..?Z) ->
        heading_index = base36_index(heading)
        power_index = base36_index(power) + 1
        {heading_index * 10, power_index * power_index * 10, status_text}

      _ ->
        {nil, nil, data}
    end
  end

  defp extract_beam(data), do: {nil, nil, data}

  @spec base36_index(byte()) :: non_neg_integer()
  defp base36_index(char) when is_digit(char), do: char - ?0
  defp base36_index(char) when char in ?A..?Z, do: char - ?A + 10

  @spec put_optional(map(), atom(), term()) :: map()
  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)
end
