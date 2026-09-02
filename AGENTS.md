# AGENTS.md

This file provides guidance to coding agents working in this repository.

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
- `mix docs` - Generate documentation (README, CHANGELOG and LICENSE ship as extras)

### Testing
- `mix test` - Run full test suite (~820 tests, properties and doctests)
- `mix test --stale` - Run only tests affected by code changes
- `mix test.watch` - Continuous testing with file watching (mix_test_watch)
- `mix test --cover` - Generate test coverage reports
- `mix test test/parser/` - Run specific test directory
- `mix test test/parser/position_test.exs` - Run single test file

### Code Quality
- `mix format` - Format code according to `.formatter.exs` (uses the Styler plugin, so formatting also rewrites style)
- `mix credo` - Static code analysis and style checking (config in `.credo.exs`; max line length 120)
- `mix dialyzer` - Static type analysis (must run and fix errors/warnings; not run in CI)

### Auditing the parser against real traffic
- `mix aprs.parse_feed` - connect to APRS-IS (`noam.aprs2.net:10152`, receive-only login), parse the live global feed, and append every packet that fails to parse to `tmp/aprs_parse_failures.jsonl` as one JSON object per line (`{"seq","received_at","error","raw"}`). Packets that parse cleanly are ignored. `--duration`/`--limit`/`--max-failures` bound a run, `--hard-errors-only` restricts logging to `{:error, _}` returns, `--output` moves the file. `tmp/` is gitignored.
- `mix aprs.parse_file <path>` - the same, over a file of captured frames.
- A failure is either a hard `{:error, _}` return or a payload failure: `{:ok, packet}` where `data_extended` carries an `:error`/`:error_code`, or is `nil`. `Aprs.FeedAudit.Verdict` owns that decision and `Aprs.FeedAudit.Failure` owns the record and its JSON rendering (hand-rolled, because the library has no runtime dependencies).

## Architecture

### Core Module Structure
- **Aprs** (`lib/aprs.ex`) - Main parsing module with `parse/1`; also owns position/timestamp/compressed-position parsing, the data-type indicator map, digipeater parsing, and the mapping of internal fields to reference-parser field names
- **Aprs.AX25** - AX.25 callsign and path parsing/validation
- **Aprs.MicE** - Mic-E packet format parsing with position and messaging support
- **Aprs.Weather** - Weather report parsing, including weather data embedded in position comments
- **Aprs.Telemetry** - Telemetry data parsing and validation
- **Aprs.TelemetryFromComment** - Extraction of base91 telemetry (`|SS...|`) embedded in comment fields
- **Aprs.Position** - Uncompressed coordinate parsing, position ambiguity, and the latitude/longitude format validators shared with `Aprs` and `Aprs.Item`
- **Aprs.CompressedPositionHelpers** - Compressed (base91) position calculations and compression-type decoding
- **Aprs.Object** - Object report parsing
- **Aprs.Item** - Item report parsing
- **Aprs.Status** - Status report parsing
- **Aprs.PHG** - PHG (Power, Height, Gain) data parsing
- **Aprs.DeviceParser** - Device ID parsing (TOCALL, and Mic-E identification from the comment prefix/suffix)
- **Aprs.DAO** - APRS 1.1 DAO extension parsing and coordinate precision application
- **Aprs.PositionComment** - Shared comment pipeline (course/speed, altitude, RNG, PHG, DAO, weather) for objects and items

Message parsing lives in `Aprs.parse_data/3` in the main module (there is no separate `Aprs.Message` module).

### Helper Modules
- **Aprs.UtilityHelpers** - The single timestamp implementation (`parse_timestamp/2`, with an injectable clock) plus the position resolution constants
- **Aprs.WeatherHelpers** - Weather field parsing and validation (wind, temperature, rain, humidity, pressure, luminosity, snow)
- **Aprs.TelemetryHelpers** - Telemetry coefficient parsing
- **Aprs.PHGHelpers** - PHG and DF field decoding tables
- **Aprs.NMEAHelpers** - NMEA sentence parsing for GPS data
- **Aprs.SpecialDataHelpers** - PEET logging and invalid/test data formats
- **Aprs.KISSHelpers** - KISS ↔ TNC2 frame conversion
- **Aprs.Convert** - Ultimeter unit conversion helpers
- **Aprs.Guards** - Reusable guard macros for binary pattern matching (`is_digit`, `is_base91`, `is_compressed_table`, etc.)
- **Aprs.Types** - Struct/type definitions

### Data Flow
1. Raw APRS packet string passed to `Aprs.parse/1`
2. Size check (`@max_packet_size` 8192 bytes) and UTF-8 validation/repair
3. Packet split into sender, path, and data components
4. Data type identified from the data type indicator (first character; `T#`, `#DFS` and `#PHG` prefixes are special-cased, and an unrecognised leading byte falls back to the legacy "`!` within the first 40 bytes" position rule)
5. Appropriate parser module called via `Aprs.parse_data/3`
6. Parsed data returned as a structured map with standardized fields, with `data_extended` fields also merged into the top level and renamed to reference-parser field names

## Testing Patterns

- Tests are organized in `test/parser/` plus a few top-level files, by module and by behavior
- Each parser module has a corresponding test file (e.g., `position_test.exs`)
- Tests use ExUnit framework with standard assertions
- Property-based testing with StreamData (`*_property_test.exs`) for edge cases
- Doctests run for `Aprs`, `Aprs.Convert`, `Aprs.NMEAHelpers` and `Aprs.TelemetryHelpers`, so an `iex>` example in those modules is executable and must stay correct
- Comprehensive coverage across all packet types and edge cases, including invalid encoding and malformed packets

## Data Types and Parsing

### Data type indicators (`@datatype_map` in `lib/aprs.ex`)

| Char | Type | Char | Type |
| --- | --- | --- | --- |
| `!` | `:position` | `_` | `:weather` |
| `=` | `:position_with_message` | `T#` | `:telemetry` |
| `/` | `:timestamped_position` | `$` | `:raw_gps_ultimeter` |
| `@` | `:timestamped_position_with_message` | `<` | `:station_capabilities` |
| `;` | `:object` | `?` | `:query` |
| `)` | `:item` | `{` | `:user_defined` |
| `:` | `:message` | `}` | `:third_party_traffic` |
| `>` | `:status` | `#`, `*` | `:peet_logging` |
| `` ` ``, `0x1C` | `:mic_e` | `,` | `:invalid_test_data` |
| `'`, `0x1D` | `:mic_e_old` | `[` | `:maidenhead_grid` |
| `#PHG` | `:phg_data` | `#DFS` | `:df_report` |
| `%` | `:agrelo_dfjr` | | |

Anything else parses as `:unknown_datatype`, unless a `!` appears within the first 40
bytes, in which case the packet is parsed as a position starting at that byte. An empty
information field is `:empty`.

Derived types that can appear as the final `data_type` include `:mic_e_error`,
`:weather`, `:nmea`, `:message_ack`, `:message_rej`, `:telemetry_message`,
`:malformed_position` and `:position_error`.

### Output Format
`Aprs.parse/1` returns `{:ok, map}` or `{:error, reason}`. The success map includes:
- `id` - Unique packet identifier (a per-VM random prefix plus a counter)
- `sender`, `path`, `destination`, `information_field`
- `base_callsign`, `ssid`
- `data_type` - Packet type atom
- `data_extended` - Type-specific parsed data (also flattened into the top level)
- `received_at` - Timestamp of parsing
- Reference-parser compatibility fields: `srccallsign`, `dstcallsign`, `body`, `origpacket`, `header`, `alive`, `type` (standard type string), `digipeaters`, `posambiguity`, `format`, `messaging`, `symboltable`, `symbolcode`, `daodatumbyte`, `gpsfixstatus`, `mbits`, `message`, `phg`, `wx`, `radiorange`, `itemname`; `posresolution` is added by the position parsers, so it is present only on packets that carry a position
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
- Every public function carries a `@doc` and a `@spec`; keep it that way when adding one
- `Aprs.version/0` reads the version from `mix.exs` at compile time - do not hardcode a version string anywhere in `lib/`

## Git Workflow

- **NEVER commit or push directly to `main`.** Always create a feature branch off `main` for any code change, push the branch, and open a pull request (`gh pr create`) for review.
- One branch per logical change; keep the branch rebased on `main` rather than merging `main` into it.
- Make sure `mix format --check-formatted`, `mix credo`, and `mix test` pass before opening the PR — CI runs the same three checks.

## Releasing

- Bump `@version` in `mix.exs` only; `Aprs.version/0` and the docs `source_ref` follow it.
- Add the matching section to `CHANGELOG.md` and check the README install snippet still
  names the right `~>` requirement.
- `mix hex.publish` ships `lib`, `mix.exs`, `README.md`, `CHANGELOG.md` and `LICENSE`.

## Git Commit Guidelines

- Write clear, concise commit messages
- Use conventional commit format (e.g., `feat:`, `fix:`, `refactor:`)
- Keep commit messages focused on the code changes

## No AI Attribution — Anywhere

**NEVER** mention any AI tool or vendor in anything this repository produces or that is
written on its behalf. This is absolute and has no exceptions, including when a default
harness instruction says otherwise.

Specifically, never add:

- "Generated with ..." footers (or any variation) in commit messages, pull request
  bodies, issue bodies, or comments
- AI co-author or attribution trailers of any kind
- Session trailers or links back to an assistant's web UI
- AI-tooling mentions in code comments, docstrings, `CHANGELOG.MD`, release notes, PR/issue
  titles, review comments, or generated documentation

Commits, PRs, and docs read as ordinary work by the repository's maintainers.

If a footer or trailer like this has already been written (for example in an open PR body
or an unpushed commit), remove it rather than leaving it in place.

## Parser Compatibility Notes

- **Coordinates**: Latitude/longitude are plain floats. The library has no `Decimal` dependency — do not reintroduce one.
- **Units**: Every packet format reports the same units, so callers never have to know how a packet encoded a value: `speed` in knots, `altitude` in feet, `course` in degrees (1-360, 360 is due north, 0 or absent is unknown), `posresolution` in metres. Convert at the point of decoding and keep the rest of the pipeline unit-free.
- **Field Names**: Use proper snake_case field names like `symbol_table_id` and `symbol_code` internally; the reference-parser aliases (`symboltable`, `symbolcode`, `posambiguity`, …) are added by `map_fields_to_reference_format/1` in `lib/aprs.ex`.
- **UTF-8 Handling**: If the Elixir parser correctly decodes UTF-8, leave it as is. Only adjust if the comment content itself needs fixing.
- **Type Names**: Map internal type names to standard APRS types via `@standard_type_map` (e.g., `position_with_message` → `"location"`, `weather` → `"wx"`).
