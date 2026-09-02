defmodule Aprs.DAO do
  @moduledoc """
  APRS 1.1 DAO extension (`!DAO!`).

  The extension carries the datum used by the sender plus one extra digit of
  latitude/longitude minute precision:

    * uppercase datum (`!W52!`) - the two bytes are ASCII digits giving
      thousandths of a minute (`4903.50N` + `5` becomes 49 03.505')
    * lowercase datum (`!w52!`) - the two bytes are base-91 giving
      `(byte - 33) / 91` of a hundredth of a minute

  The datum byte is reported upper-cased, matching reference parsers.
  """

  @typedoc "Parsed DAO extension: datum byte plus the extra precision in degrees"
  @type t :: %{datum: String.t(), lat_offset: float(), lon_offset: float()}

  @hundredth_minute 0.01 / 60
  @thousandth_minute 0.001 / 60

  @doc """
  Find and remove a DAO extension in a comment.

  Returns `{dao, comment_without_dao}`, or `{nil, comment}` when the comment
  holds no DAO extension.
  """
  @spec parse(term()) :: {t() | nil, term()}
  def parse(comment) when is_binary(comment), do: scan(comment, 0)
  def parse(comment), do: {nil, comment}

  @spec scan(binary(), non_neg_integer()) :: {t() | nil, String.t()}
  defp scan(comment, offset) when offset <= byte_size(comment) - 5 do
    scope = {offset, byte_size(comment) - offset}

    case :binary.match(comment, "!", scope: scope) do
      {index, 1} ->
        candidate = binary_part(comment, index, byte_size(comment) - index)
        parse_candidate(comment, index, candidate)

      :nomatch ->
        {nil, comment}
    end
  end

  defp scan(comment, _offset), do: {nil, comment}

  @spec parse_candidate(binary(), non_neg_integer(), binary()) :: {t() | nil, String.t()}
  defp parse_candidate(comment, index, <<?!, d, a, o, ?!, rest::binary>>) do
    case offsets(d, a, o) do
      {lat_offset, lon_offset} ->
        dao = %{datum: <<upcase(d)>>, lat_offset: lat_offset, lon_offset: lon_offset}
        {dao, String.trim(binary_part(comment, 0, index) <> rest)}

      nil ->
        scan(comment, index + 1)
    end
  end

  defp parse_candidate(comment, index, _candidate), do: scan(comment, index + 1)

  # Human-readable form: two ASCII digits of 1/1000 minute.
  @spec offsets(byte(), byte(), byte()) :: {float(), float()} | nil
  defp offsets(d, a, o) when d in ?A..?Z and a in ?0..?9 and o in ?0..?9 do
    {(a - ?0) * @thousandth_minute, (o - ?0) * @thousandth_minute}
  end

  # Datum only, no additional precision.
  defp offsets(d, ?\s, ?\s) when d in ?A..?Z, do: {0.0, 0.0}

  # Base-91 form: 1/91 of a hundredth of a minute per unit.
  defp offsets(d, a, o) when d in ?a..?z and a in 33..123 and o in 33..123 do
    {(a - 33) / 91 * @hundredth_minute, (o - 33) / 91 * @hundredth_minute}
  end

  defp offsets(_, _, _), do: nil

  @spec upcase(byte()) :: byte()
  defp upcase(c) when c in ?a..?z, do: c - 32
  defp upcase(c), do: c

  @doc """
  Apply DAO additional precision to a decoded coordinate pair.

  The offset moves the coordinate away from the equator or the prime meridian,
  in the direction its own sign already points. An ambiguous position is left
  alone, since ambiguity exists to drop the precision DAO would add.
  """
  @spec apply_precision(float() | nil, float() | nil, t() | nil, non_neg_integer()) ::
          {float() | nil, float() | nil}
  def apply_precision(lat, lon, nil, _ambiguity), do: {lat, lon}
  def apply_precision(lat, lon, _dao, ambiguity) when ambiguity > 0, do: {lat, lon}

  def apply_precision(lat, lon, %{lat_offset: lat_offset, lon_offset: lon_offset}, _ambiguity) do
    {shift(lat, lat_offset), shift(lon, lon_offset)}
  end

  @spec shift(float() | nil, float()) :: float() | nil
  defp shift(nil, _offset), do: nil
  defp shift(value, offset) when is_number(value) and value < 0, do: value - offset
  defp shift(value, offset) when is_number(value), do: value + offset
end
