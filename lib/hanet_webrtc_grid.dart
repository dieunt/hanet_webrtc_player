import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// A widget that displays multiple WebRTC players in a grid layout.
/// This widget is designed for displaying multiple video streams simultaneously.
class HanetWebRTCGrid extends StatefulWidget {
  /// List of peer IDs to display in the grid
  final List<String> peerIds;

  /// Number of columns in the grid (optional)
  final int? crossAxisCount;

  /// Creates a new instance of [HanetWebRTCGrid].
  const HanetWebRTCGrid({
    super.key,
    required this.peerIds,
    this.crossAxisCount,
  });

  @override
  State<HanetWebRTCGrid> createState() => _HanetWebRTCGridState();
}

class _HanetWebRTCGridState extends State<HanetWebRTCGrid> {
  bool _isFullscreen = false;

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
    final crossAxisCount = widget.crossAxisCount ??
        _calculateGridCrossAxisCount(widget.peerIds.length);

    return Stack(
      children: [
        GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: widget.peerIds.length,
          itemBuilder: (context, index) {
            return Container(
              color: Colors.black,
              child: RTCVideoView(
                RTCVideoRenderer(),
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            );
          },
        ),
        // Fullscreen button
        Positioned(
          top: 16,
          right: 16,
          child: IconButton(
            icon: Icon(
              _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white,
            ),
            onPressed: _toggleFullscreen,
          ),
        ),
      ],
    );
  }

  int _calculateGridCrossAxisCount(int itemCount) {
    if (itemCount <= 1) return 1;
    if (itemCount <= 2) return 2;
    if (itemCount <= 4) return 2;
    if (itemCount <= 6) return 3;
    if (itemCount <= 9) return 3;
    return 4; // For more than 9 items
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
