# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.2] - 2026-09-02

### Changed
- Parsing is roughly twice as fast, with no change to what any packet parses to.
  The parser now validates UTF-8 with `:unicode.characters_to_binary/1` instead of
  walking the packet in Elixir, finds header delimiters and comment markers
  (`/A=`, `PHG`, `!DAO!`) with `:binary.match/3` instead of rebuilding the packet
  a byte at a time, splits and validates the digipeater path in one pass, builds
  APRS timestamps with integer unix-second arithmetic rather than `Date`/`Time`/
  `DateTime` structs, and derives the reference-parser field aliases from
  `data_extended` instead of re-reading the merged packet.
- The last regular expressions left in the parsing paths (Mic-E comment cleanup,
  the loose timestamped-position fallback, and the item coordinate fallback) are
  replaced by binary pattern matching, and the remaining `cond`/`if` dispatch and
  exception-based control flow in Mic-E destination decoding, compressed
  coordinate decoding and item status detection are now function clauses.

### Added
- `Aprs.Clock`, the single wall-clock read used for `received_at` and for
  resolving APRS timestamps, which caches the calendar date per second.

## [2.0.1] - 2026-09-02

### Fixed
- `Aprs.version/0` returned `"1.0.1"`. It now reads the version from `mix.exs` at
  compile time, so it cannot drift from the released package again.
- README documentation: the installation snippet asked for `~> 1.0`, the example
  packet map showed a `posresolution` and packet `id` shape the parser stopped
  producing in 2.0.0, and the weather example showed `snow: 0.0` for a report that
  carries no snow field (it is `nil`).

### Added
- A `@doc` on every public function, including `Aprs.parse/1`, with executable
  examples for the entry points.
- `CHANGELOG.md` ships in the hex package and is published with the docs.

## [2.0.0] - 2026-09-02

### Fixed
- **Compressed positions**: course is decoded from the `c` byte rather than the speed
  byte, and `c == "!"` is course 360; the radio-range form is signalled by `{`, not `Z`;
  the compression type byte is decoded with the layout the spec defines (GPS fix, NMEA
  source, origin) rather than the position-resolution and messaging layout used before;
  `cs` bytes from a GGA source are decoded as altitude. Compressed positions are always
  ambiguity 0 and take their messaging flag from the data type indicator.
- **Mic-E**: speed is reported in knots, without the mph-to-knots factor that was being
  applied to a value already in knots; course 360 (due north) is kept instead of being
  reported as 0; the `!w..!` DAO extension and `|..|` comment telemetry are decoded
  instead of discarded; the symbol table byte is no longer prepended to the comment as a
  device type code.
- **Messages**: message IDs are parsed as the spec defines them (`{` plus 1-5
  alphanumerics, with no closing brace), including the APRS 1.1 reply-ack form `{MM}AA`;
  `ack` and `rej` bodies are classified as `:message_ack` and `:message_rej`; telemetry
  definition messages (`PARM.`, `UNIT.`, `EQNS.`, `BITS.`) are parsed into structured
  fields; message text is preserved verbatim.
- **Position format detection**: lower-case hemisphere letters are accepted; compressed
  positions require a symbol table the spec allows (`/`, `\`, `A-Z`, `a-j`) and base-91
  coordinate bytes (33..123); coordinates that decode out of range are rejected rather
  than clamped; a position with no symbol code no longer reports the weather symbol.
- **Trailing spaces** are no longer trimmed from the information field, so a compressed
  packet whose `csT` bytes are spaces parses.
- **Timestamps**: one implementation, with an injectable clock, shared by positions and
  objects. `DDHHMM/` (local time) is accepted, `HHMMSSh` object timestamps are read as
  hours/minutes/seconds, and a day or hour that would land in the future rolls back to
  the previous month or day.
- **Weather**: positionless reports use the eight-digit `MDHM` timestamp; `sNNN` after
  `cNNN` is wind speed, not snowfall; lower-case `l` luminosity adds 1000.
- **Objects and items**: compressed reports with an alternate or overlay symbol table
  keep their position; `RNG` is reported as `radiorange`; altitude is found anywhere in
  the comment and range checked; reports on the `_` symbol get weather parsing; items
  report `alive` and `itemname` and share the position comment pipeline.
- **Third-party traffic** keeps the data type indicator for tunnelled messages and items.
- **DAO**: `daodatumbyte` is the upper-cased datum byte, and the extra digit of precision
  is applied to the coordinates that are returned.
- **Telemetry**: 1-5 analog channels and a missing bits field are accepted, non-numeric
  (`MIC`) sequences parse, analog values are floats, and `EQNS.` no longer raises on an
  incomplete coefficient group.
- **NMEA**: any talker id is accepted (`$GNRMC`, `$GNGGA`, and so on) along with `GGA`,
  `GLL`, `RMC`, `VTG` and `WPL`; `$ULTW` Peet Bros Ultimeter packets are decoded.
- **Invalid UTF-8** is repaired one byte sequence at a time, falling back to Latin-1,
  instead of replacing every non-ASCII byte in the packet.
- The poles and the antimeridian (`9000.00N`, `18000.00W`) are valid coordinates.
- Every digipeater at or before the last `*` is marked as used, and a path containing an
  empty element is rejected.
- Parse exceptions report the exception message rather than a bare `"Parse exception"`.

### Added
- `Aprs.DAO`: DAO extension parsing and coordinate precision.
- `Aprs.PositionComment`: the comment pipeline shared by objects and items.
- Data type indicators `[` (Maidenhead grid locator beacon, decoded to a position), `%`
  (Agrelo DFJr), `0x1C` and `0x1D` (Mic-E rev 0), and the legacy "`!` within the first 40
  bytes" position form. `` ` `` now gives `:mic_e` and `'` gives `:mic_e_old`.
- Status reports decode a leading timestamp, a Maidenhead locator with its symbol, and a
  trailing `^` beam heading and ERP.
- Station capabilities are decoded into a map, and `DFS` and `CSE/SPD/BRG/NRQ` are parsed
  as comment data extensions.

### Changed
- **Consistent units across every packet format**: `speed` is a float in knots,
  `altitude` a float in feet, `course` an integer from 1 to 360 (360 is north, 0 is
  unknown) and `posresolution` a float in metres (18.52 m at full precision, 0.291 m
  compressed, 0.1852 m for NMEA). Telemetry analog values are floats, not strings.
- Weather parsing is a single left-to-right scan that also returns the non-weather part
  of the comment, replacing eleven per-field rescans and a fifteen-regex strip. A weather
  packet now parses in about 3.2 µs instead of 38.5 µs, and an uncompressed position with
  extensions in about 3.0 µs instead of 17.4 µs.
- Packet IDs are a per-VM random prefix plus a counter, rather than a CSPRNG call for
  every packet.
- `Aprs.DeviceParser` identifies Mic-E radios from the comment prefix and suffix instead
  of decoding the destination field, which holds the encoded latitude and is never a
  TOCALL.

### Removed
- Dead or unreachable code: the `Aprs.Types.MicE` struct, `parse_path/1` from
  `Aprs.AX25`, `parse_from_comment/1` and its helpers from `Aprs.Weather`,
  `count_spaces/1` and `calculate_position_ambiguity/2` from `Aprs.Position` (with the
  `Aprs.UtilityHelpers` delegates), the unused value parsers from
  `Aprs.TelemetryHelpers`, `speed/3` from `Aprs.Convert`,
  `calculate_compressed_ambiguity/1` from `Aprs.CompressedPositionHelpers`, and the
  public `decode_compressed_position/1`, `convert_to_base91/1`, `parse_status/1`,
  `parse_station_capabilities/1`, `parse_query/1`, `parse_user_defined/1` and
  `parse_position_with_datetime_and_weather/7` wrappers from `Aprs`.
- The `cs == "&!"` workaround and the `&!` DAO form, neither of which is in the spec.

## [0.1.6] - 2025-08-13

### Changed
- **Performance Optimization**: Refactored parsing modules to use binary pattern matching instead of regex:
  - Replaced all regex patterns with efficient binary pattern matching in weather parsing modules
  - Converted PHG data parsing from regex to binary pattern matching for better performance
  - Refactored object parsing to use binary pattern matching for course/speed, altitude, and DAO parsing
  - Updated position parsing in main module and position.ex to use binary pattern matching
  - Converted utility helpers coordinate and timestamp parsing to binary pattern matching
  - Eliminated regex compilation overhead and improved memory efficiency
  - Improved type safety with compile-time pattern validation
- **Code Quality**: Refactored conditional logic throughout the codebase to use more functional patterns:
  - Replaced `cond` statements with pattern matching and guard clauses
  - Eliminated most `case` statements in favor of `with` expressions, pattern matching, and functional alternatives
  - Extracted static mappings into module attributes for better maintainability
  - Simplified complex conditionals using built-in functions like `min/max`
  - Broke up large functions into smaller, focused helper functions
  - Improved readability and testability of the codebase
  - Refactored regex pattern matching to use consistent `with` expressions
  - Converted parse result handling to use pipelines and functional composition

### Added
- **Standard APRS Parser Fields**: Added comprehensive field compatibility with standard APRS parsers:
  - `posambiguity`: Position ambiguity level (0-4)
  - `format`: Position format indicator ("compressed" or "uncompressed")
  - `alive`: Packet validity indicator (always 1)
  - `symboltable`: Symbol table identifier
  - `symbolcode`: Symbol code identifier
  - `messaging`: APRS messaging capability for compressed positions
  - `srccallsign`: Source callsign field
  - `dstcallsign`: Destination callsign field
  - `body`: Information field content
  - `origpacket`: Complete original packet string
  - `header`: Packet header without information field
- **Weather Data Extraction**: Implemented comprehensive weather data parsing from position comments:
  - `wx`: Dedicated weather data field extracted from comments
  - Automatic detection and extraction of weather patterns (temperature, humidity, pressure, wind, rain)
  - Clean separation of weather data from comment text
- **Radiorange (RNG) Parsing**: Added support for radio range field extraction from comments
  - Parses "RNG0001" format and converts to range in miles
  - Removes RNG data from comment after extraction
- **Enhanced Comment Processing**: Improved comment parsing with proper whitespace handling and data extraction

### Fixed
- **PHG Data Format**: Fixed PHG parsing to return string representation (e.g., "1060") instead of map structure for better compatibility
- **Comment Cleaning**: Improved comment field cleaning to properly extract and remove embedded data (PHG, weather, RNG)
- **APRS Messaging for Compressed Positions**: Added proper APRS messaging bit extraction from compression type byte
- **Data Type Consistency**: Maintained proper data_type values for MicE packets (mic_e vs mic_e_old) based on packet format

### Changed
- **Compressed Position Helpers**: Extended compression type parsing to include APRS messaging capability (bit 6)
- **MicE Parser**: Enhanced to accept and preserve original data_type classification
- **PHG Module**: Implemented full PHG/DFS parsing with string output format

## [0.1.5] - 2025-08-01

### Fixed
- **Third-Party Traffic Parsing**: Fixed FunctionClauseError in third-party packet parsing caused by incorrect SSID extraction in tunneled packets
- **Invalid Position Data Handling**: Added graceful error handling for packets with invalid UTF-8 characters in position data
  - Packets with invalid characters in compressed positions now return descriptive error messages instead of crashing
  - Added proper handling of UnicodeConversionError in compressed position helpers
  - Distinguishes between "Invalid compressed location" and "Invalid uncompressed location" errors
- **Compressed Latitude Calculation**: Fixed incorrect divisor (was 456976, now 380926) for compressed latitude
- **Telemetry Parsing**: Fixed telemetry parsing to handle both "T#" and "#" prefixes correctly

### Added
- **Enhanced Error Messages**: Position parsing now returns specific error messages for different types of invalid data
- **UTF-8 Safety**: Added safe_to_charlist function to handle invalid UTF-8 sequences in compressed position data
- **Comprehensive Test Coverage**: Added tests for various invalid packet formats including:
  - DB0WV-11 packet with UTF-8 characters in uncompressed position
  - HB9ZF-12 packet with UTF-8 characters in compressed position  
  - TSwWV-8 packet with mixed format position data
  - HB9ELZ-7 packet with malformed UTF-8 encoding
  - KO6TX-1 third-party traffic packet validation
- **Position Resolution Parsing**: Added full support for compressed position resolution (ambiguity) levels 0-4
  - Extracts position resolution from compression type byte (bits 2-4)
  - Supports all standard APRS ambiguity levels: exact, 0.1', 1', 10', 1°
- **Compression Type Details**: Enhanced parsing of compression type byte to extract:
  - GPS fix type (other, GLL/GGA, RMC)
  - Position resolution/ambiguity level
  - Old GPS data flag
- **Alternate Compressed Formats**: Support for compressed positions with leading symbol table ID (e.g., 'L' format)
- **Position Resolution Field**: Added posresolution field showing position accuracy in meters
  - Uncompressed positions: 18.52m to 111,120m based on ambiguity
  - Compressed positions: 0.291m precision
- **Format Field**: Added format field indicating "compressed" or "uncompressed" position type
- **Telemetry in Comments**: Extract base91-encoded telemetry data from position comments
- **Enhanced Telemetry Parsing**: Improved telemetry packet structure with seq, vals, and bits fields
- **Decimal Coordinate Conversion**: Convert latitude/longitude to float values instead of Decimal structs

## [0.1.4] - 2025-07-07

### Added
- **Device ID Parser**: New comprehensive device ID parsing functionality with support for various device types and formats
- **Enhanced Mic-E Packet Support**: Improved parsing of Mic-E packets with better error handling and validation
- **Compressed Position Helpers**: New dedicated module for handling compressed position calculations and conversions
- **Weather Position Integration**: Enhanced weather packet parsing with position data integration
- **Telemetry Helpers**: New comprehensive telemetry parsing and validation utilities
- **Utility Helpers**: New module providing common utility functions for APRS packet processing
- **Device Parser Tests**: Comprehensive test suite for device ID parsing functionality
- **Compressed Position Tests**: Extensive test coverage for compressed position parsing
- **Weather Helpers Tests**: Complete test suite for weather data parsing and validation
- **Telemetry Helpers Tests**: Comprehensive tests for telemetry data processing
- **Utility Helpers Tests**: Full test coverage for utility functions

### Changed
- **Performance Improvements**: Significant performance optimizations in packet parsing logic
- **Enhanced Error Handling**: Improved error handling and validation throughout the parsing pipeline
- **Refined Parsing Logic**: More robust and accurate packet parsing with better edge case handling
- **Weather Parser Enhancements**: Improved weather data parsing with better field validation
- **Test Coverage**: Dramatically increased test coverage across all modules
- **Code Organization**: Better module structure and separation of concerns

### Fixed
- **Weather Packet Parsing**: Fixed issues with weather packet parsing and field extraction
- **Position Ambiguity Calculation**: Improved accuracy of position ambiguity calculations
- **Unicode Handling**: Better handling of Unicode characters in packet data
- **Binary Pattern Matching**: Enhanced binary pattern matching for more reliable parsing
- **Coordinate Validation**: Improved coordinate validation and error handling

### Technical Improvements
- **Binary-Safe Operations**: Enhanced binary operations for better Unicode support
- **Memory Efficiency**: Optimized memory usage in packet processing
- **Type Safety**: Improved type specifications and validation
- **Documentation**: Enhanced inline documentation and code comments
- **Code Quality**: Improved code formatting and adherence to Elixir best practices

## [0.1.3] - Initial Release

### Added
- **Core APRS Parsing**: Basic APRS packet parsing functionality
- **Position Reports**: Support for uncompressed and compressed position reports
- **Weather Reports**: Basic weather data parsing
- **Status Reports**: Status message parsing
- **Messages**: APRS message parsing
- **Objects and Items**: Object and item packet support
- **Mic-E Packets**: Basic Mic-E packet parsing
- **Telemetry Data**: Telemetry packet support
- **PHG Data**: PHG (Power, Height, Gain) data parsing
- **NMEA Support**: NMEA sentence parsing for GPS data
- **AX.25 Support**: AX.25 callsign parsing and validation
- **Basic Documentation**: Initial README and usage examples
