# Hanet WebRTC Player

A WebRTC video player widget component for Flutter applications. Currently displays a black rectangle as a placeholder for WebRTC video content.

## Features

-   Simple black rectangle widget that can be used as a placeholder for WebRTC video content
-   Customizable width and height
-   Ready to be extended with actual WebRTC video playback functionality

## Getting Started

### Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
    hanet_webrtc_player:
        git:
            url: https://github.com/dieunt/hanet_webrtc_player.git
```

### Usage

```dart
import 'package:hanet_webrtc_player/hanet_webrtc_player.dart';

// Use the widget with default size (300x200)
HanetWebRTCPlayer()

// Or specify custom dimensions
HanetWebRTCPlayer(
  width: 400,
  height: 300,
)
```

## Development

This package is currently in development and will be extended with actual WebRTC video playback functionality in future releases.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
