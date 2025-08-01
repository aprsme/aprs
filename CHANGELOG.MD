# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **Third-Party Traffic Parsing**: Fixed FunctionClauseError in third-party packet parsing caused by incorrect SSID extraction in tunneled packets

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
