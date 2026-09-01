# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Elixir library for parsing APRS (Automatic Packet Reporting System) packets. It provides comprehensive parsing capabilities for various APRS packet types including position reports, weather data, telemetry, messages, and more.

The library has **no runtime dependencies** — it is pure Elixir and relies only on the standard library plus `:crypto` (used for packet ID generation). All dev/test dependencies are `only: [:dev, :test]`.

## Development Environment

- Elixir/OTP versions are pinned in `.tool-versions` (currently Elixir 1.20.3-otp-29, Erlang 29.0.5); `mix.exs` requires `elixir ~> 1.17`.
- A Nix flake dev shell is provided (`flake.nix`, `nix/`). With direnv installed, `.envrc` (`use flake .`) loads it automatically; otherwise `nix develop`.
- CI runs on GitHub Actions (`.github/workflows/ci.yml`): format check, Credo, and the test suite on `push`/`pull_request` against `main`. It resolves versions from `.tool-versions` via `erlef/setup-beam`.

## Development Commands

### Setup and Dependencies
- `mix deps.get` - Install dependencies
- `mix compile` - Compile the project
- `mix docs` - Generate documentation

### Testing
- `mix test` - Run full test suite (~900 tests/properties)
- `mix test --stale` - Run only tests affected by code changes
- `mix test.watch` - Continuous testing with file watching (mix_test_watch)
- `mix test --cover` - Generate test coverage reports
- `mix test test/parser/` - Run specific test directory
- `mix test test/parser/position_test.exs` - Run single test file

### Code Quality
- `mix format` - Format code according to `.formatter.exs` (uses the Styler plugin, so formatting also rewrites style)
- `mix credo` - Static code analysis and style checking (config in `.credo.exs`; max line length 120)
- `mix dialyzer` - Static type analysis (must run and fix errors/warnings; not run in CI)

## Architecture

### Core Module Structure
- **Aprs** (`lib/aprs.ex`) - Main parsing module with `parse/1`; also owns position/timestamp/compressed-position parsing, the data-type indicator map, digipeater parsing, and the mapping of internal fields to reference-parser field names
- **Aprs.AX25** - AX.25 callsign and path parsing/validation
- **Aprs.MicE** - Mic-E packet format parsing with position and messaging support
- **Aprs.Weather** - Weather report parsing, including weather data embedded in position comments
- **Aprs.Telemetry** - Telemetry data parsing and validation
- **Aprs.TelemetryFromComment** - Extraction of base91 telemetry (`|SS...|`) embedded in comment fields
- **Aprs.Position** - Position report parsing and position ambiguity calculation
- **Aprs.CompressedPositionHelpers** - Compressed (base91) position calculations and compression-type decoding
- **Aprs.Object** - Object report parsing
- **Aprs.Item** - Item report parsing
- **Aprs.Status** - Status report parsing
- **Aprs.PHG** - PHG (Power, Height, Gain) data parsing
- **Aprs.DeviceParser** - Device ID parsing (TOCALL and Mic-E legacy device identification)

Message parsing lives in `Aprs.parse_data/3` in the main module (there is no separate `Aprs.Message` module).

### Helper Modules
- **Aprs.UtilityHelpers** - Timestamp validation, position resolution/ambiguity, misc utilities
- **Aprs.WeatherHelpers** - Weather field parsing and validation (wind, temperature, rain, humidity, pressure, luminosity, snow)
- **Aprs.TelemetryHelpers** - Telemetry sequence/analog/digital/coefficient parsing
- **Aprs.PHGHelpers** - PHG and DF field decoding tables
- **Aprs.NMEAHelpers** - NMEA sentence parsing for GPS data
- **Aprs.SpecialDataHelpers** - PEET logging and invalid/test data formats
- **Aprs.KISSHelpers** - KISS ↔ TNC2 frame conversion
- **Aprs.Convert** - Unit conversion helpers (Ultimeter wind/temp, knots→mph)
- **Aprs.Guards** - Reusable guard macros for binary pattern matching (`is_digit`, `is_base91`, etc.)
- **Aprs.Types** / **Aprs.Types.MicE** - Struct/type definitions; `Aprs.Types.MicE` implements `Access`

### Data Flow
1. Raw APRS packet string passed to `Aprs.parse/1`
2. Size check (`@max_packet_size` 8192 bytes) and UTF-8 validation/repair
3. Packet split into sender, path, and data components
4. Data type identified from the data type indicator (first character; `#DFS`/`#PHG` prefixes are special-cased)
5. Appropriate parser module called via `Aprs.parse_data/3`
6. Parsed data returned as a structured map with standardized fields, with `data_extended` fields also merged into the top level and renamed to reference-parser field names

## Testing Patterns

- Tests are organized in `test/parser/` (plus `test/types/` and a few top-level files) by module and by behavior
- Each parser module has a corresponding test file (e.g., `position_test.exs`)
- Tests use ExUnit framework with standard assertions
- Property-based testing with StreamData (`*_property_test.exs`) for edge cases
- Comprehensive coverage across all packet types and edge cases, including invalid encoding and malformed packets

## Data Types and Parsing

### Data type indicators (`@datatype_map` in `lib/aprs.ex`)

| Char | Type | Char | Type |
| --- | --- | --- | --- |
| `!` | `:position` | `_` | `:weather` |
| `=` | `:position_with_message` | `T` | `:telemetry` |
| `/` | `:timestamped_position` | `$` | `:raw_gps_ultimeter` |
| `@` | `:timestamped_position_with_message` | `<` | `:station_capabilities` |
| `;` | `:object` | `?` | `:query` |
| `%`, `)` | `:item` | `{` | `:user_defined` |
| `:` | `:message` | `}` | `:third_party_traffic` |
| `>` | `:status` | `*` | `:peet_logging` |
| `` ` ``, `'` | `:mic_e_old` | `,` | `:invalid_test_data` |
| `#`/`#PHG` | `:phg_data` | `#DFS` | `:df_report` |

Anything else parses as `:unknown_datatype`; an empty information field is `:empty`.

Derived types that can appear as the final `data_type` include `:mic_e`, `:mic_e_error`, `:weather` (from a position comment), `:position_with_datetime_and_weather`, `:nmea`, and `:malformed_position`.

### Output Format
`Aprs.parse/1` returns `{:ok, map}` or `{:error, reason}`. The success map includes:
- `id` - Unique packet identifier (random hex)
- `sender`, `path`, `destination`, `information_field`
- `base_callsign`, `ssid`
- `data_type` - Packet type atom
- `data_extended` - Type-specific parsed data (also flattened into the top level)
- `received_at` - Timestamp of parsing
- Reference-parser compatibility fields: `srccallsign`, `dstcallsign`, `body`, `origpacket`, `header`, `alive`, `type` (standard type string), `digipeaters`, `posambiguity`, `format`, `messaging`, `symboltable`, `symbolcode`, `posresolution`, `daodatumbyte`, `gpsfixstatus`, `mbits`, `message`, `phg`, `wx`, `radiorange`, `itemname`
- `resultcode` / `resultmsg` - `"success"` / `"OK"` on a successful parse

## Code Style Guidelines

- Follow standard Elixir conventions
- Use pattern matching over conditionals where possible
- Prefer binary pattern matching for performance (the codebase deliberately avoids regex in hot paths)
- Handle UTF-8 encoding issues gracefully
- Use `with` statements for nested operations
- Implement comprehensive error handling
- Run `mix format` before committing
- Address all Dialyzer warnings

## Git Workflow

- **NEVER commit or push directly to `main`.** Always create a feature branch off `main` for any code change, push the branch, and open a pull request (`gh pr create`) for review.
- One branch per logical change; keep the branch rebased on `main` rather than merging `main` into it.
- Make sure `mix format --check-formatted`, `mix credo`, and `mix test` pass before opening the PR — CI runs the same three checks.

## Git Commit Guidelines

- Write clear, concise commit messages
- Use conventional commit format (e.g., `feat:`, `fix:`, `refactor:`)
- **DO NOT** add "Generated with Claude Code" to commits
- **DO NOT** add Co-Authored-By lines for Claude
- Keep commit messages focused on the code changes

## Parser Compatibility Notes

- **Coordinates**: Latitude/longitude are plain floats. The library has no `Decimal` dependency — do not reintroduce one.
- **Speed and Altitude**: Leave speed and altitude values as they are decoded from the packet. Do not convert units.
- **Field Names**: Use proper snake_case field names like `symbol_table_id` and `symbol_code` internally; the reference-parser aliases (`symboltable`, `symbolcode`, `posambiguity`, …) are added by `map_fields_to_reference_format/1` in `lib/aprs.ex`.
- **UTF-8 Handling**: If the Elixir parser correctly decodes UTF-8, leave it as is. Only adjust if the comment content itself needs fixing.
- **Type Names**: Map internal type names to standard APRS types via `@standard_type_map` (e.g., `position_with_message` → `"location"`, `weather` → `"wx"`).
