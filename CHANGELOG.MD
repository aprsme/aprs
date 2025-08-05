# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
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
