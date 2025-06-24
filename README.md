# APRS Parser

A pure Elixir library for parsing APRS (Automatic Packet Reporting System) packets.

## Installation

```elixir
def deps do
  [
    {:aprs_parser, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
# Parse an APRS packet
{:ok, packet} = AprsParser.parse("N0CALL>APRS,TCPIP*,qAC,T2TEST:=1234.56N/12345.67W-Test message")

# The parsed packet contains:
# - sender: "N0CALL"
# - destination: "APRS"
# - path: "TCPIP*,qAC,T2TEST"
# - data_type: :position
# - data_extended: %{latitude: ..., longitude: ..., ...}
```

## Supported Packet Types

- Position reports (uncompressed and compressed)
- Mic-E packets
- Weather reports
- Telemetry data
- Messages
- Status reports
- Objects and Items
- PHG data
- And more...

## License

MIT 