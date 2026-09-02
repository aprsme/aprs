# APRS

A pure Elixir library for parsing APRS (Automatic Packet Reporting System) packets.

It handles the full range of common APRS formats — position reports (uncompressed and
compressed), Mic-E, weather, telemetry, objects, items, messages, status reports, PHG/DF
data, NMEA and more — and returns a flat, predictable map for each packet. There are **no
runtime dependencies**.

## Installation

Add `:aprs` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:aprs, "~> 2.0"}
  ]
end
```

Requires Elixir 1.17 or later.

## Usage

`Aprs.parse/1` takes a TNC2-format packet string and returns `{:ok, packet}` or
`{:error, reason}`:

```elixir
{:ok, packet} = Aprs.parse("N0CALL>APRS,TCPIP*,qAC,T2TEST:=4903.50N/07201.75W-Test message")

packet.data_type   #=> :position_with_message
packet.latitude    #=> 49.05833333333333
packet.longitude   #=> -72.02916666666667
packet.comment     #=> "Test message"
```

Every packet map carries the same envelope fields, the type-specific fields under
`:data_extended`, and those same type-specific fields flattened into the top level for
convenience:

```elixir
%{
  id: "d00797958416d5581386",   # per-VM random prefix plus a counter
  sender: "N0CALL",
  path: "TCPIP*,qAC,T2TEST",
  destination: "APRS",
  information_field: "=4903.50N/07201.75W-Test message",
  data_type: :position_with_message,
  base_callsign: "N0CALL",
  ssid: "0",
  received_at: ~U[2026-09-01 17:03:51.259500Z],
  resultcode: "success",
  resultmsg: "OK",
  data_extended: %{
    data_type: :position_with_message,
    latitude: 49.05833333333333,
    longitude: -72.02916666666667,
    comment: "Test message",
    symbol_table_id: "/",
    symbol_code: "-",
    aprs_messaging?: true,
    compressed?: false,
    format: :uncompressed,
    has_position: true,
    position_ambiguity: 0,
    posambiguity: 0,
    posresolution: 18.52,
    messaging: 0,
    timestamp: nil,
    altitude: nil,
    course: nil,
    speed: nil,
    phg: nil,
    radiorange: nil,
    dao: nil,
    wx: nil
  },
  # ... flattened data_extended fields plus reference-parser aliases ...
}
```

Errors are returned rather than raised:

```elixir
Aprs.parse("not a packet")
#=> {:error, :invalid_packet}
```

Coordinates are plain floats. Every packet format reports the same units, whichever way
the packet encoded them: `speed` in knots, `altitude` in feet, `course` in degrees
(1-360, where 360 is due north and 0 or a missing value means unknown) and
`posresolution` in metres.

### Reference-parser compatibility fields

Alongside the snake_case fields above, each packet includes field names matching the
common reference APRS parsers, so output can be consumed by existing tooling:

`srccallsign`, `dstcallsign`, `body`, `origpacket`, `header`, `alive`, `type`,
`digipeaters`, `posambiguity`, `format`, `messaging`, `symboltable`, `symbolcode`,
`daodatumbyte`, `gpsfixstatus`, `mbits`, `message`, `phg`, `wx`, `radiorange`,
`itemname`. Packets that carry a position also get `posresolution`.

`type` is the standard type string for the packet (`"location"`, `"wx"`, `"object"`,
`"item"`, `"message"`, `"messageack"`, `"messagerej"`, `"telemetry"`,
`"telemetry-message"`, `"status"`, `"capabilities"`, …), and `digipeaters` is a list of
`%{call: String.t(), wasdigied: 0 | 1}`.

`format` is how the position was encoded — `:uncompressed`, `:compressed`, `:mice`,
`:nmea`, `:maidenhead`, or `:unknown`.

### More examples

Compressed position:

```elixir
{:ok, packet} = Aprs.parse("N0CALL>APRS,TCPIP*:!/5L!!<*e7> sTComment")

packet.data_type          #=> :position
packet.format             #=> :compressed
packet.latitude           #=> 49.5
packet.longitude          #=> -72.75000393777269
packet.data_extended.compression_type  #=> "T"
```

Mic-E:

```elixir
{:ok, packet} = Aprs.parse(~s(KD8XYZ-9>T2SXTS,WIDE1-1:`(_fn"Oj/]"4H}Testing Mic-E))

packet.data_type                    #=> :mic_e
packet.latitude                     #=> 42.6405
packet.longitude                    #=> -112.129
packet.data_extended.speed          #=> 20.0
packet.data_extended.course         #=> 251
packet.data_extended.altitude       #=> 160.761154855
packet.data_extended.message_type   #=> :standard
```

Weather:

```elixir
{:ok, packet} =
  Aprs.parse("N0CALL>APRS,TCPIP*,qAC,T2TEST:_12345678c000s000g000t000r000p000P000h00b00000")

packet.data_type  #=> :weather
packet.wx
#=> %{
#     wind_direction: 0, wind_speed: 0, wind_gust: 0, temperature: 0,
#     rain_1h: 0.0, rain_24h: 0.0, rain_since_midnight: 0.0,
#     humidity: 100, pressure: 0.0, luminosity: nil, snow: nil,
#     timestamp: "12345678", raw_weather_data: "c000s000g000t000r000p000P000h00b00000"
#   }
```

A field the report leaves out is `nil`, so a station that sends no snow gauge reading is
distinguishable from one reporting no snow.

Weather data embedded in a position comment is detected and extracted automatically into
the same `:wx` field, and the comment is cleaned of it.

Telemetry:

```elixir
{:ok, packet} = Aprs.parse("N0CALL>APRS,TCPIP*:T#005,199,000,255,073,123,01101001")

packet.data_type            #=> :telemetry
packet.data_extended.telemetry
#=> %{seq: "005", vals: [199.0, 0.0, 255.0, 73.0, 123.0], bits: "01101001"}
```

Message:

```elixir
{:ok, packet} = Aprs.parse("N0CALL>APRS,TCPIP*,qAC,T2TEST::WU2Z     :Hello there{001")

packet.data_type                  #=> :message
packet.data_extended.addressee    #=> "WU2Z"
packet.data_extended.message_text #=> "Hello there"
packet.data_extended.message_number #=> "001"
```

Object:

```elixir
{:ok, packet} = Aprs.parse("N0CALL>APRS,TCPIP*:;LEADER   *092345z4903.50N/07201.75W>088/036")

packet.data_type                 #=> :object
packet.data_extended.object_name #=> "LEADER"
packet.data_extended.live_killed #=> "*"
packet.data_extended.course      #=> 88
packet.data_extended.speed       #=> 36.0
```

## Supported packet types

| Indicator | `data_type` | Notes |
| --- | --- | --- |
| `!` | `:position` | Uncompressed or compressed |
| `=` | `:position_with_message` | |
| `/` | `:timestamped_position` | |
| `@` | `:timestamped_position_with_message` | |
| `` ` `` | `:mic_e` | Position, course/speed, altitude, message bits |
| `'` | `:mic_e_old` | Old Mic-E |
| `0x1C` `0x1D` | `:mic_e` / `:mic_e_old` | Rev-0 (current and old) Mic-E |
| `_` | `:weather` | Full weather field set |
| `;` | `:object` | Live/killed, course/speed, altitude, RNG, DAO, weather |
| `)` | `:item` | Live/killed, course/speed, altitude, RNG, DAO, weather |
| `:` | `:message` | Addressee, text, message number, reply-ack, `ack`/`rej` |
| `>` | `:status` | Timestamp, Maidenhead locator, beam heading/ERP |
| `T#` | `:telemetry` | 1-5 analog values, digital bits, sequence |
| `[` | `:maidenhead_grid` | Grid locator beacon, decoded to a position |
| `%` | `:agrelo_dfjr` | Agrelo DFJr / MicroFinder |
| `#PHG` | `:phg_data` | Power, height, gain, directivity |
| `#DFS` | `:df_report` | |
| `$` | `:raw_gps_ultimeter` | NMEA (RMC, GGA, GLL, VTG, WPL) and `$ULTW` |
| `<` | `:station_capabilities` | Decoded into a capability map |
| `?` | `:query` | |
| `{` | `:user_defined` | `{{` is the spec's experimental form |
| `}` | `:third_party_traffic` | |
| `#` `*` | `:peet_logging` | Peet Bros U-II weather station |
| `,` | `:invalid_test_data` | |

The legacy rule that `!` may appear anywhere in the first 40 bytes of the information
field is honoured when the leading byte is not itself a data type indicator.

Additional handling for position-bearing packets, following the same order as the
reference `Ham::APRS::FAP` parser:

- A leading data extension — course/speed (`088/036`), PHG (`PHG5132`), RNG (`RNG0050`)
  or DFS (`DFS2360`) — parsed as mutually exclusive alternatives and removed from the
  comment; a course/speed pair followed by `/BRG/NRQ` is decoded as a DF report
  (`bearing`, `nrq`, `df_hits`, `df_range`, `df_quality`)
- Altitude anywhere in the comment (`/A=001234`), validated to −10 000..500 000 ft
- Base91 telemetry embedded in the comment (`|SS...|`), removed from the comment and
  decoded into `telemetry: %{seq: integer, vals: [integer], bits: String.t() | nil}`
  (the key is absent when the comment carries no telemetry)
- DAO precision extensions (`!W12!`), exposed as `dao` and `daodatumbyte`, with the
  extra digit applied to the returned coordinates
- Position ambiguity, with the matching `posresolution` in metres
- Weather data on the `_` symbol, exposed as `:wx` and `:weather`
- Device identification from the TOCALL, or from the Mic-E comment prefix/suffix
  (`Aprs.DeviceParser`)

## Other public helpers

- `Aprs.version/0` — library version string
- `Aprs.parse_datatype/1` — the data type of an information field, without parsing it
- `Aprs.AX25` — callsign and path parsing/validation
- `Aprs.KISSHelpers` — KISS ↔ TNC2 frame conversion
- `Aprs.DeviceParser` — device identification from a packet or raw string
- `Aprs.PHGHelpers` — decode the digits of a PHG or DFS value
- `Aprs.Convert` — Ultimeter unit conversions

## Development

```sh
mix deps.get
mix test                    # full suite (unit + StreamData property tests)
mix test --stale            # only what your changes affect
mix format                  # formats and applies Styler
mix credo                   # static analysis
mix dialyzer                # type analysis
mix docs                    # generate HexDocs output
```

Elixir/OTP versions are pinned in `.tool-versions`. A Nix flake dev shell is provided —
`nix develop`, or automatically via direnv (`.envrc`). CI runs the format check, Credo,
and the test suite on GitHub Actions.

Contributions should go on a feature branch and be opened as a pull request against
`main`.

## License

GNU General Public License v3.0 or later — see [LICENSE](LICENSE).
