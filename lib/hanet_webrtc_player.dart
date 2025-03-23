import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'src/webrtc_manager.dart';

/// A WebRTC video player widget with volume, mic, and fullscreen controls.
/// This widget is designed for single player usage.
class HanetWebRTCPlayer extends StatefulWidget {
  /// The ID of the remote peer to connect to
  final String peerId;

  /// Creates a new instance of [HanetWebRTCPlayer].
  const HanetWebRTCPlayer({
    super.key,
    required this.peerId,
  });

  @override
  State<HanetWebRTCPlayer> createState() => _HanetWebRTCPlayerState();
}

class _HanetWebRTCPlayerState extends State<HanetWebRTCPlayer> {
  // UI state
  bool _isVolumeOn = true;
  bool _isMicOn = true;
  bool _isFullscreen = false;
  bool _isRecording = false;

  // WebRTC manager
  WebRTCManager? _webrtcManager;

  @override
  void initState() {
    super.initState();
    _initializeWebRTC();
  }

  void _initializeWebRTC() {
    _webrtcManager = WebRTCManager(
      peerId: widget.peerId,
    );

    // Set up callbacks
    _webrtcManager?.onRecordingStateChanged = (isRecording) {
      setState(() {
        _isRecording = isRecording;
      });
    };

    _webrtcManager?.onError = (error) {
      // Handle error (e.g., show a snackbar)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    };
  }

  void _toggleVolume() {
    setState(() {
      _isVolumeOn = !_isVolumeOn;
      _webrtcManager?.toggleVolume(_isVolumeOn);
    });
  }

  void _toggleMic() {
    setState(() {
      _isMicOn = !_isMicOn;
      _webrtcManager?.toggleMic(_isMicOn);
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

  Future<void> _startRecording() async {
    await _webrtcManager?.startRecording();
  }

  Future<void> _stopRecording() async {
    await _webrtcManager?.stopRecording();
  }

  Future<void> _captureFrame() async {
    await _webrtcManager?.captureFrame();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // Main video container
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            child: RTCVideoView(
              _webrtcManager?.remoteRenderer ?? RTCVideoRenderer(),
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
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
                  // Record button
                  IconButton(
                    icon: Icon(
                      _isRecording ? Icons.stop : Icons.fiber_manual_record,
                      color: _isRecording ? Colors.red : Colors.white,
                    ),
                    onPressed: _isRecording ? _stopRecording : _startRecording,
                  ),
                  // Capture frame button
                  IconButton(
                    icon: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                    ),
                    onPressed: _captureFrame,
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
    _webrtcManager?.dispose();

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
