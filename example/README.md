# Synheart Focus Example App

This example demonstrates how to use the Synheart Focus SDK to detect cognitive states from heart rate data.

## Running the Example

### Prerequisites
- Flutter SDK installed (>=3.10.0)
- A device/emulator/simulator running

### Steps

1. **Navigate to the example directory:**
   ```bash
   cd example
   ```

2. **Get dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run on your preferred platform:**
   
   **iOS Simulator:**
   ```bash
   flutter run -d ios
   ```
   
   **Android Emulator:**
   ```bash
   flutter run -d android
   ```
   
   **macOS Desktop:**
   ```bash
   flutter run -d macos
   ```
   
   **Check available devices:**
   ```bash
   flutter devices
   ```

## What the Example Does

1. **Initializes** the Focus Engine with the Gradient Boosting model
2. **Simulates** HR data streams for three cognitive states:
   - **Focused**: HR ~70 BPM (optimal focus)
   - **Anxious**: HR ~90 BPM (heightened arousal)
   - **Bored**: HR ~60 BPM (low engagement)
3. **Displays** real-time inference results showing:
   - Detected cognitive state
   - Focus score (0-100)
   - Confidence level
   - Class probabilities

## Features Demonstrated

- HR data input with windowing (60s window, 5s step)
- Automatic HR → IBI conversion
- Subject-specific z-score normalization
- 24-feature HRV extraction
- 4-class classification (Bored, Focused, Anxious, Overload)

