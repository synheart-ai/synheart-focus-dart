# Changelog

All notable changes to this project will be documented in this file.


## [0.1.0] - 2026-01-01

### Added
- Comprehensive integration tests matching synheart-core FocusHead usage pattern 

- HSI schema compatibility tests 

### Improved
- Test coverage increased
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

