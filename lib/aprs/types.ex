defmodule Aprs.Types do
  @moduledoc """
  Type definitions for APRS parsing.
  """

  defmodule Position do
    @moduledoc """
    Represents position data with latitude, longitude, and associated metadata.
    """
    @type t :: %__MODULE__{
            latitude: float() | nil,
            longitude: float() | nil,
            timestamp: integer() | String.t() | nil,
            symbol_table_id: String.t() | nil,
            symbol_code: String.t() | nil,
            comment: String.t() | nil,
            aprs_messaging?: boolean() | nil,
            compressed?: boolean() | nil,
            position_ambiguity: non_neg_integer() | nil,
            dao: map() | nil
          }
    defstruct [
      :latitude,
      :longitude,
      :timestamp,
      :symbol_table_id,
      :symbol_code,
      :comment,
      :aprs_messaging?,
      :compressed?,
      :position_ambiguity,
      :dao
    ]

    @doc """
    Return a map with latitude and longitude from decimal values.
    """
    @spec from_decimal(number(), number()) :: %{latitude: float(), longitude: float()}
    def from_decimal(lat, lon) do
      %{latitude: lat / 1, longitude: lon / 1}
    end
  end
end
