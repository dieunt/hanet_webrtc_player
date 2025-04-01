# Hanet WebRTC Player

A WebRTC video player widget component for Flutter applications with built-in controls for volume, microphone, and fullscreen mode.

## Features

-   Responsive black rectangle container that adapts to parent container size
-   Volume control toggle (on/off)
-   Microphone control toggle (on/off)
-   Fullscreen mode support
    -   On mobile: Rotates to landscape and hides system UI
    -   On web: Expands to full screen
-   Material Design icons for controls
-   Gradient overlay for better button visibility

## Getting Started

### Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
    hanet_webrtc_player:
        git:
            url: https://github.com/dieunt/hanet_webrtc_player.git
            tag: ...
```

### Usage

```dart
import 'package:hanet_webrtc_player/hanet_webrtc_player.dart';

// Basic usage
HanetWebRTCPlayer()

// Inside a container with specific dimensions
Container(
  width: 400,
  height: 300,
  child: HanetWebRTCPlayer(
    peerId: '....',
    showFullscreen: true,
    showCapture: true,
    showRecord: true,
    showMic: true,
    showVolume: true,
    source: 'MainStream',
    showControls: true,
  ),
)
```

## Features

### Volume Control

-   Toggle between volume on/off using the volume icon
-   Default state is volume off

### Microphone Control

-   Toggle between microphone on/off using the mic icon
-   Default state is microphone off

### Fullscreen Mode

-   Toggle fullscreen mode using the fullscreen icon
-   On mobile devices:
    -   Rotates to landscape orientation
    -   Hides system UI for immersive experience
-   On web:
    -   Expands to full screen
-   Automatically resets orientation when widget is disposed

## Development

This package is currently in development and will be extended with actual WebRTC video playback functionality in future releases.

