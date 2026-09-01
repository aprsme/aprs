defmodule Aprs.Guards do
  @moduledoc """
  Reusable guard macros for APRS binary pattern matching.
  """

  defguard is_digit(b) when b >= ?0 and b <= ?9
  defguard is_minute_tens(b) when b in ?0..?7 or b == ?\s
  defguard is_digit_or_space(b) when b in ?0..?9 or b == ?\s
  # APRS base-91 uses the printable range `!`..`{` (33..123); `|` and `~` are
  # reserved as telemetry/no-data markers and are not valid base-91 digits.
  defguard is_base91(b) when b >= 33 and b <= 123

  # Symbol tables legal in a compressed position: primary, alternate, or an
  # overlay character (APRS101 chapter 9).
  defguard is_compressed_table(b)
           when b in [?/, ?\\] or (b >= ?A and b <= ?Z) or (b >= ?a and b <= ?j)

  defguard is_alphanumeric(b)
           when (b >= ?a and b <= ?z) or (b >= ?A and b <= ?Z) or (b >= ?0 and b <= ?9)
end
