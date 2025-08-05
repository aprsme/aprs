# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Elixir library for parsing APRS (Automatic Packet Reporting System) packets. It provides comprehensive parsing capabilities for various APRS packet types including position reports, weather data, telemetry, messages, and more.

## Development Commands

### Setup and Dependencies
- `mix deps.get` - Install dependencies
- `mix compile` - Compile the project
- `mix docs` - Generate documentation

### Testing
- `mix test` - Run full test suite
- `mix test --stale` - Run only tests affected by code changes
- `mix test.watch` - Continuous testing with file watching (requires mix_test_watch dependency)
- `mix test --cover` - Generate test coverage reports
- `mix test test/parser/` - Run specific test directory
- `mix test test/parser/position_test.exs` - Run single test file

### Code Quality
- `mix format` - Format code according to .formatter.exs
- `mix credo` - Static code analysis and style checking
- `mix dialyzer` - Static type analysis (must run and fix errors/warnings)

## Architecture

### Core Module Structure
- **Aprs** - Main parsing module with `parse/1` function that handles all packet types
- **Aprs.AX25** - AX.25 protocol handling for callsign parsing
- **Aprs.MicE** - Mic-E packet format parsing with position and messaging support
- **Aprs.Weather** - Weather report parsing with position integration
- **Aprs.Telemetry** - Telemetry data parsing and validation
- **Aprs.Position** - Position report parsing (uncompressed and compressed)
- **Aprs.CompressedPositionHelpers** - Compressed position calculations and conversions
- **Aprs.Object** - Object report parsing
- **Aprs.Item** - Item report parsing
- **Aprs.Message** - Message parsing
- **Aprs.Status** - Status report parsing
- **Aprs.PHG** - PHG (Power, Height, Gain) data parsing
- **Aprs.DeviceParser** - Device ID parsing for various APRS devices

### Helper Modules
- **Aprs.UtilityHelpers** - Common utility functions for packet processing
- **Aprs.CompressedPositionHelpers** - Compressed position format handling
- **Aprs.WeatherHelpers** - Weather data validation and parsing utilities
- **Aprs.TelemetryHelpers** - Telemetry data processing utilities
- **Aprs.PHGHelpers** - PHG data parsing helpers
- **Aprs.NMEAHelpers** - NMEA sentence parsing for GPS data
- **Aprs.SpecialDataHelpers** - Special data format parsing

### Data Flow
1. Raw APRS packet string passed to `Aprs.parse/1`
2. Packet split into sender, path, and data components
3. Data type identified by first character of information field
4. Appropriate parser module called based on data type
5. Parsed data returned as structured map with standardized fields

### Key Dependencies
- **Decimal** - High-precision decimal arithmetic for coordinates
- **ExDoc** - Documentation generation
- **Credo** - Static code analysis
- **Dialyxir** - Type checking
- **StreamData** - Property-based testing
- **Styler** - Code formatting

## Testing Patterns

- Tests are organized in `test/parser/` directory by module
- Each parser module has corresponding test file (e.g., `position_test.exs`)
- Tests use ExUnit framework with standard assertions
- Property-based testing with StreamData for edge cases
- Comprehensive test coverage across all packet types and edge cases

## Data Types and Parsing

### Supported Packet Types
- `:position` - Position reports with latitude/longitude
- `:timestamped_position` - Position reports with timestamp
- `:weather` - Weather reports with optional position data
- `:telemetry` - Telemetry data packets
- `:message` - APRS messages between stations
- `:status` - Status reports
- `:object` - Object reports
- `:item` - Item reports
- `:mic_e` - Mic-E format packets
- `:phg_data` - PHG data

### Output Format
All parsed packets return a standardized map structure with:
- `id` - Unique packet identifier
- `sender` - Originating callsign
- `path` - Digipeater path
- `destination` - Destination callsign
- `data_type` - Packet type atom
- `data_extended` - Type-specific parsed data
- `received_at` - Timestamp of parsing

## Code Style Guidelines

- Follow standard Elixir conventions
- Use pattern matching over conditionals where possible
- Prefer binary pattern matching for performance
- Handle UTF-8 encoding issues gracefully
- Use `with` statements for nested operations
- Implement comprehensive error handling
- Run `mix format` before committing
- Address all Dialyzer warnings

## Git Commit Guidelines

- Write clear, concise commit messages
- Use conventional commit format (e.g., `feat:`, `fix:`, `refactor:`)
- **DO NOT** add "Generated with Claude Code" to commits
- **DO NOT** add Co-Authored-By lines for Claude
- Keep commit messages focused on the code changes

## Parser Compatibility Notes

- **Speed and Altitude**: Leave speed and altitude values as they are decoded from the packet. Do not convert units.
- **Field Names**: Use proper snake_case field names like `symbol_table_id` and `symbol_code` rather than concatenated names
- **UTF-8 Handling**: If the Elixir parser correctly decodes UTF-8, leave it as is. Only adjust if the comment content itself needs fixing.
- **Type Names**: Map internal type names to standard APRS types (e.g., `position_with_message` → `location`)