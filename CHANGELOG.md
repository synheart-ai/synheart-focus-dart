# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.1.0] - 2026-01-01

### Added
- Comprehensive integration tests matching synheart-core FocusHead usage pattern (15 tests)
  - Tests for FocusEngine initialization with synheart-core config
  - Tests for infer(HSIData, BehaviorData) API pattern with multimodal fusion
  - Tests for streaming updates via onUpdate for reactive integration
  - Tests for temporal smoothing and stable output
  - Tests for edge case handling (extreme HR, high task switching, low HR)
  - Tests for engine state reset and lifecycle management
  - Tests for confidence calculation with varying data quality
  - Tests for focus label assignment (High/Medium/Low Focus)
  - Tests for metadata diagnostic information
  - Tests for custom configuration (thresholds, weights)

- HSI schema compatibility tests (2 tests)
  - Tests verifying FocusState output matches HSI schema
  - Tests for toJson output HSI compatibility
  - Tests validating derived fields (cognitiveLoad, clarity, distraction) calculations
  - Tests ensuring focus scores are valid (0.0-1.0 range)
  - Tests for inverse relationship between focus and distraction

### Improved
- Test coverage increased from 10 to 25 tests (150% increase)
- Validated compatibility with synheart-core-dart v0.0.1 FocusHead implementation
- Confirmed multimodal fusion with HSI (biosignals) + Behavior data
- Verified temporal smoothing maintains stable output
- Ensured focus state mapping to HSI schema is correct

## [0.0.1] - 2025-12-26

### Added
- Initial release
- FocusEngine implementation with real-time inference
- FocusState data model with focus scores and labels
- HSI (Heart Signal Intelligence) data integration
- Behavioral pattern data integration
- On-device ONNX model support
- Adaptive baseline tracking
- Artifact filtering for signal quality
- Feature extraction and scoring
- Window buffer for temporal data
- Cross-platform support (iOS, Android)

