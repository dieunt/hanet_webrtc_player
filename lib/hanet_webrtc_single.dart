import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'src/webrtc_manager.dart';

class HanetWebRTSingle extends StatefulWidget {
  final String peerId;
  final String source;
  final bool showVolume;
  final bool showMic;
  final bool showCapture;
  final bool showRecord;
  final bool showFullscreen;
  final bool showControls;
  final bool isDebug;
  final bool isVertical;
  final VoidCallback? onOffline;
  final Function(bool)? onFullscreen;

  const HanetWebRTSingle({
    Key? key,
    required this.peerId,
    this.source = "SubStream",
    this.showVolume = true,
    this.showMic = true,
    this.showCapture = false,
    this.showRecord = false,
    this.showFullscreen = true,
    this.showControls = true,
    this.isDebug = false,
    this.isVertical = false,
    this.onOffline,
    this.onFullscreen,
  }) : super(key: key);

  @override
  State<HanetWebRTSingle> createState() => _HanetWebRTSingleState();
}

class _HanetWebRTSingleState extends State<HanetWebRTSingle> with WidgetsBindingObserver {
  bool _isVolumeOn = false;
  bool _isMicOn = false;
  bool _isFullscreen = false;
  bool _isRecording = false;
  bool _isDebug = false;

  WebRTCManager? _webrtcManager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeWebRTC();
    if (!kIsWeb) _resetOrientation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_webrtcManager != null) {
      // _webrtcManager?.remoteRenderer.srcObject = null;
      // _webrtcManager?.localRenderer.srcObject = null;
      // _webrtcManager?.remoteRenderer.dispose();
      // _webrtcManager?.localRenderer.dispose();
      _webrtcManager!.dispose();
      _webrtcManager = null;
    }
    if (!kIsWeb) _resetOrientation();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb && state == AppLifecycleState.resumed) {
      _resetOrientation();
    }
  }

  void _initializeWebRTC() {
    _webrtcManager = WebRTCManager(
      peerId: widget.peerId,
      source: widget.source,
      isDebug: widget.isDebug,
    );

    _webrtcManager?.onRecordingStateChanged = (isRecording) {
      if (mounted) setState(() => _isRecording = isRecording);
    };

    _webrtcManager?.onRemoteStream = (stream) {
      if (mounted && stream != null) {
        stream.getAudioTracks().forEach((track) {
          track.enabled = false;
        });
        setState(() {});
      }
    };

    _webrtcManager?.onLocalStream = (stream) {
      if (mounted && stream != null) {
        stream.getAudioTracks().forEach((track) {
          track.enabled = false;
        });
        setState(() {});
      }
    };

    _webrtcManager?.onError = (error) {
      if (mounted) {
        setState(() {});
        widget.onOffline!();
      }
    };

    _webrtcManager?.onOffline = () {
      if (mounted && widget.onOffline != null) {
        widget.onOffline!();
      }
    };
  }

  void _toggleVolume() {
    if (!widget.showVolume) return;
    setState(() {
      _isVolumeOn = !_isVolumeOn;
      _webrtcManager?.toggleVolume(_isVolumeOn);
    });
  }

  void _toggleMic() {
    if (!widget.showMic) return;
    setState(() {
      _isMicOn = !_isMicOn;
      _webrtcManager?.toggleMic(_isMicOn);
    });
  }

  void _resetOrientation() {
    if (kIsWeb) return;

    // SystemChrome.setEnabledSystemUIMode(
    //   SystemUiMode.manual,
    //   overlays: SystemUiOverlay.values,
    // );

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // SystemChrome.setPreferredOrientations([
    //   DeviceOrientation.portraitUp,
    //   DeviceOrientation.portraitDown,
    // ]);
  }

  Future<void> _toggleFullscreen() async {
    if (kIsWeb || !widget.showFullscreen) return;

    setState(() {
      _isFullscreen = !_isFullscreen;
    });

    if (_isFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!widget.isVertical) {
        // SystemChrome.setPreferredOrientations([
        //   DeviceOrientation.landscapeLeft,
        //   DeviceOrientation.landscapeRight,
        // ]);
      }
      // 3) Let parent know
      widget.onFullscreen?.call(true);
    } else {
      _resetOrientation();
      widget.onFullscreen?.call(false);
    }
  }

  Future<void> _startRecording() async {
    if (!widget.showRecord) return;
    await _webrtcManager?.startRecording();
  }

  Future<void> _stopRecording() async {
    if (!widget.showRecord) return;
    await _webrtcManager?.stopRecording();
  }

  Future<void> _captureFrame() async {
    if (!widget.showCapture) return;
    await _webrtcManager?.captureFrame();
  }

  Widget _buildVideoView() {
    return Container(
      color: Colors.black, // Always black background
      child: Stack(
        children: [
          if (_webrtcManager != null)
            RTCVideoView(
              _webrtcManager!.remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              // placeholderBuilder: (context) => Center(
              //   child: SizedBox(
              //     width: 12,
              //     height: 12,
              //     child: CircularProgressIndicator(color: Colors.white),
              //   ),
              // ),
            ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.2),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (widget.showVolume)
            IconButton(
              icon: Icon(
                _isVolumeOn ? Icons.volume_up : Icons.volume_off,
                color: Colors.white,
              ),
              onPressed: _toggleVolume,
            ),
          if (widget.showMic)
            IconButton(
              icon: Icon(
                _isMicOn ? Icons.mic : Icons.mic_off,
                color: Colors.white,
              ),
              onPressed: _toggleMic,
            ),
          if (widget.showCapture)
            IconButton(
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              onPressed: _captureFrame,
            ),
          if (widget.showRecord)
            IconButton(
              icon: Icon(
                _isRecording ? Icons.stop : Icons.fiber_manual_record,
                color: _isRecording ? Colors.red : Colors.white,
              ),
              onPressed: _isRecording ? _stopRecording : _startRecording,
            ),
          if (widget.showFullscreen && !kIsWeb)
            IconButton(
              icon: Icon(
                _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Colors.white,
              ),
              onPressed: _toggleFullscreen,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black, // Always black background
      child: Stack(
        children: [
          _isFullscreen
              ? Positioned.fill(
                  child: _buildVideoView(),
                )
              : Center(
                  child: AspectRatio(
                    aspectRatio: widget.isVertical ? 9 / 16 : 16 / 9,
                    child: _buildVideoView(),
                  ),
                ),
          if (widget.showControls)
            _isFullscreen
                ? Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildControls(),
                  )
                : Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildControls(),
                  ),
        ],
      ),
    );
  }
}
