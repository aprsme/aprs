defmodule Aprs.Types do
  @moduledoc """
  Type definitions for APRS parsing.
  """

  alias Aprs.Types.MicE

  @type mice :: MicE.t()

  defmodule Packet do
    @moduledoc """
    Represents an APRS packet with all its components.
    """
    @type t :: %__MODULE__{
            id: String.t() | nil,
            sender: String.t() | nil,
            path: String.t() | nil,
            destination: String.t() | nil,
            information_field: String.t() | nil,
            data_type: atom() | nil,
            base_callsign: String.t() | nil,
            ssid: String.t() | nil,
            data_extended: map() | nil,
            received_at: DateTime.t() | nil
          }
    defstruct [
      :id,
      :sender,
      :path,
      :destination,
      :information_field,
      :data_type,
      :base_callsign,
      :ssid,
      :data_extended,
      :received_at
    ]
  end

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
    Parse APRS lat/lon strings (e.g., "3339.13N", "11759.13W") into a map with latitude and longitude.
    """
    @spec from_aprs(String.t(), String.t()) :: %{latitude: float() | nil, longitude: float() | nil}
    def from_aprs(lat_str, lon_str) do
      %{latitude: parse_lat(lat_str), longitude: parse_lon(lon_str)}
    end

    @spec parse_lat(String.t()) :: float() | nil
    defp parse_lat(lat_str) do
      case Regex.run(~r/^(\d{2})(\d{2}\.\d+)([NS])$/, lat_str) do
        [_, degrees, minutes, direction] ->
          signed_decimal(degrees, minutes, direction, "S")

        _ ->
          nil
      end
    end

    @spec parse_lon(String.t()) :: float() | nil
    defp parse_lon(lon_str) do
      case Regex.run(~r/^(\d{3})(\d{2}\.\d+)([EW])$/, lon_str) do
        [_, degrees, minutes, direction] ->
          signed_decimal(degrees, minutes, direction, "W")

        _ ->
          nil
      end
    end

    @spec signed_decimal(String.t(), String.t(), String.t(), String.t()) :: float()
    defp signed_decimal(degrees, minutes, negative, negative),
      do: -(String.to_integer(degrees) + String.to_float(minutes) / 60)

    defp signed_decimal(degrees, minutes, _direction, _negative),
      do: String.to_integer(degrees) + String.to_float(minutes) / 60

    @doc """
    Return a map with latitude and longitude from decimal values.
    """
    @spec from_decimal(number(), number()) :: %{latitude: float(), longitude: float()}
    def from_decimal(lat, lon) do
      %{latitude: lat / 1, longitude: lon / 1}
    end
  end

  defmodule ParseError do
    @moduledoc """
    Represents parsing errors with error code, message, and raw data.
    """
    @type t :: %__MODULE__{
            error_code: atom() | nil,
            error_message: String.t() | nil,
            raw_data: String.t() | nil
          }
    defstruct [
      :error_code,
      :error_message,
      :raw_data
    ]
  end

  # Add more structs as needed for NMEA, PHG, etc.
end
