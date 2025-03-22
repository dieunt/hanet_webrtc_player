import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A WebRTC video player widget with volume, mic, and fullscreen controls.
class HanetWebRTCPlayer extends StatefulWidget {
  /// Creates a new instance of [HanetWebRTCPlayer].
  const HanetWebRTCPlayer({super.key});

  @override
  State<HanetWebRTCPlayer> createState() => _HanetWebRTCPlayerState();
}

class _HanetWebRTCPlayerState extends State<HanetWebRTCPlayer> {
  bool _isVolumeOn = true;
  bool _isMicOn = true;
  bool _isFullscreen = false;

  void _toggleVolume() {
    setState(() {
      _isVolumeOn = !_isVolumeOn;
    });
  }

  void _toggleMic() {
    setState(() {
      _isMicOn = !_isMicOn;
    });
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      // Exit fullscreen
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    } else {
      // Enter fullscreen
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
    }
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // Main video container (black rectangle)
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
          ),
          // Control buttons at the bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Volume button
                  IconButton(
                    icon: Icon(
                      _isVolumeOn ? Icons.volume_up : Icons.volume_off,
                      color: Colors.white,
                    ),
                    onPressed: _toggleVolume,
                  ),
                  // Mic button
                  IconButton(
                    icon: Icon(
                      _isMicOn ? Icons.mic : Icons.mic_off,
                      color: Colors.white,
                    ),
                    onPressed: _toggleMic,
                  ),
                  // Fullscreen button
                  IconButton(
                    icon: Icon(
                      _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white,
                    ),
                    onPressed: _toggleFullscreen,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Reset orientation when widget is disposed
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }
}
