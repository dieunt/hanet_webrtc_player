import 'package:flutter/foundation.dart' show kIsWeb; // Thêm để kiểm tra Web
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'src/webrtc_manager.dart';

class HanetWebRTCPlayer extends StatefulWidget {
  final String peerId;
  final String source;
  final bool showVolume;
  final bool showMic;
  final bool showCapture;
  final bool showRecord;
  final bool showFullscreen;
  final bool showControls;
  final bool isDebug;
  final VoidCallback? onOffline;

  const HanetWebRTCPlayer({
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
    this.onOffline,
  }) : super(key: key);

  @override
  State<HanetWebRTCPlayer> createState() => _HanetWebRTCPlayerState();
}

class _HanetWebRTCPlayerState extends State<HanetWebRTCPlayer>
    with WidgetsBindingObserver {
  bool _isVolumeOn = false;
  bool _isMicOn = false;
  bool _isFullscreen = false;
  bool _isRecording = false;
  bool _showRemoteVideo = false;
  bool _isLoading = true;
  bool _isDebug = false;

  WebRTCManager? _webrtcManager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeWebRTC();
    if (!kIsWeb) _resetOrientation(); // Chỉ reset orientation trên Mobile
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_webrtcManager != null) {
      _webrtcManager!.dispose();
      _webrtcManager = null;
    }
    if (!kIsWeb) _resetOrientation(); // Chỉ reset orientation trên Mobile
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb && state == AppLifecycleState.resumed) {
      _resetOrientation(); // Chỉ reset trên Mobile khi resume
    }
  }

  void _resetOrientation() {
    if (kIsWeb) return; // Không làm gì trên Web
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
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
        setState(() {
          _showRemoteVideo = true;
          _isLoading = false;
        });
      }
    };

    _webrtcManager?.onLocalStream = (stream) {
      if (mounted && stream != null) {
        setState(() {
          _showRemoteVideo = true;
          _isLoading = false;
        });
      }
    };

    _webrtcManager?.onError = (error) {
      if (mounted) {
        setState(() => _isLoading = false);
        // ScaffoldMessenger.of(context)
        //     .showSnackBar(SnackBar(content: Text(error)));
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

  Future<void> _toggleFullscreen() async {
    if (kIsWeb || !widget.showFullscreen) return;
    setState(() {
      _isFullscreen = !_isFullscreen;
      if (_isFullscreen) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
          overlays: [],
        );
      } else {
        _resetOrientation();
      }
    });
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
      color: _isLoading ? const Color(0xFFEEF0F8) : Colors.black,
      child: _showRemoteVideo && _webrtcManager != null
          ? RTCVideoView(
              _webrtcManager!.remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          : const Center(child: CircularProgressIndicator(color: Colors.white)),
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
    return Stack(
      children: [
        // Video view
        _isFullscreen
            ? Positioned.fill(
                child: _buildVideoView(),
              )
            : Container(
                width: double.infinity,
                height: double.infinity,
                child: _buildVideoView(),
              ),
        // Controls
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
    );
  }
}
