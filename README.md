# APRS Parser

A pure Elixir library for parsing APRS (Automatic Packet Reporting System) packets.

## Installation

```elixir
def deps do
  [
    {:aprs, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
# Parse an APRS packet
{:ok, packet} = Aprs.parse("N0CALL>APRS,TCPIP*,qAC,T2TEST:=1234.56N/12345.67W-Test message")
```

## Example Output

### Position Packet

```elixir
iex> Aprs.parse("N0CALL>APRS,TCPIP*,qAC,T2TEST:=4903.50N/07201.75W-Test message")
{:ok,
 %{
   id: "...", # random hex string
   sender: "N0CALL",
   path: "TCPIP*,qAC,T2TEST",
   destination: "APRS",
   information_field: "=4903.50N/07201.75W-Test message",
   data_type: :position_with_message,
   base_callsign: "N0CALL",
   ssid: nil,
   data_extended: %{
     latitude: #Decimal<49.058333>,
     longitude: #Decimal<-72.029167>,
     comment: "Test message",
     symbol_table_id: "/",
     symbol_code: "-",
     data_type: :position
   },
   received_at: ~U[2024-06-20T12:34:56.000000Z]
 }}
```

### Weather Packet

```elixir
iex> Aprs.parse("N0CALL>APRS,TCPIP*,qAC,T2TEST:_12345678c000s000g000t000r000p000P000h00b00000")
{:ok,
 %{
   id: "...",
   sender: "N0CALL",
   path: "TCPIP*,qAC,T2TEST",
   destination: "APRS",
   information_field: "_12345678c000s000g000t000r000p000P000h00b00000",
   data_type: :weather,
   base_callsign: "N0CALL",
   ssid: nil,
   data_extended: %{
     data_type: :weather,
     # ... other weather fields ...
   },
   received_at: ~U[2024-06-20T12:34:56.000000Z]
 }}
```

### Status Packet

```elixir
iex> Aprs.parse("N0CALL>APRS,TCPIP*,qAC,T2TEST:>Test status message")
{:ok,
 %{
   id: "...",
   sender: "N0CALL",
   path: "TCPIP*,qAC,T2TEST",
   destination: "APRS",
   information_field: ">Test status message",
   data_type: :status,
   base_callsign: "N0CALL",
   ssid: nil,
   data_extended: %{
     data_type: :status,
     status_text: "Test status message"
   },
   received_at: ~U[2024-06-20T12:34:56.000000Z]
 }}
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