import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
// import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'signaling.dart';
import 'utils/websocket.dart';
import 'utils/utils.dart';

/// A class that manages WebSocket connection and WebRTC signaling
class WebRTCManager {
  // WebSocket state
  final String _serverUrl = "https://webrtc-stream.hanet.ai/wswebclient/";
  String _selfId = "";
  String _peerId = "";
  String _source = "SubStream";
  WebSocket? _socket;
  var _delSessionMsgEvent;
  var _newSessionMsgEvent;
  bool _isWebSocketConnected = false;

  // WebRTC state
  Signaling? _signaling;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  // MediaStream? _localStream;
  // MediaStream? _remoteStream;
  String _sessionId = RandomString.randomNumeric(32);

  // Callbacks
  Function(MediaStream?)? onLocalStream;
  Function(MediaStream?)? onRemoteStream;
  Function(bool)? onRecordingStateChanged;
  Function(String)? onError;
  VoidCallback? onOffline;

  /// Creates a new WebRTCManager instance
  WebRTCManager({required String peerId, String source = "SubStream"}) {
    LogUtil.init(title: "webrtc", isDebug: true, limitLength: 800);

    _selfId = Uuid().v4();
    _peerId = peerId;
    _source = source;
    _initializeRenderers().then((_) {
      _initializeSignaling(_peerId);
      _initializeWebSocket();
    });
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    LogUtil.v('WM: Renderers initialized');
  }

  void _initializeSignaling(String peerId) {
    _signaling = Signaling(_selfId, peerId, _sessionId, false, false);
    _signaling?.onSendSignalMessage = (event, data) => _send(event, data);

    // Handle session creation
    _signaling?.onSessionCreate = (sessionId, peerId, state) {
      LogUtil.v('WM: Session created with state: $state');
      if (state == OnlineState.online && peerId != _selfId) {
        _signaling?.startcall(
          sessionId,
          peerId,
          true, // audio
          true, // video
          false, // localAudio
          false, // localVideo
          true, // datachannel
          'live', // mode
          _source, // source
          'admin', // user
          '123456', // password
        );
      } else if (state == OnlineState.offline) {
        onOffline?.call();
      }
    };

    // Set up callbacks
    _signaling?.onLocalStream = (stream) {
      stream.getAudioTracks().forEach((track) {
        track.enabled = true;
        // track.enableSpeakerphone(true);
      });
      // _localStream = stream;
      _localRenderer.srcObject = stream;
      onLocalStream?.call(stream);
    };

    _signaling?.onAddRemoteStream = (session, stream) async {
      stream.getAudioTracks().forEach((track) {
        track.enabled = true;
        // track.enableSpeakerphone(true);
      });

      _remoteRenderer.srcObject = stream;
      onRemoteStream?.call(stream);
    };

    _signaling?.onRemoveRemoteStream = (session, stream) {
      // _remoteStream = null;
      _remoteRenderer.srcObject = null;
      onRemoteStream?.call(null);
      onOffline?.call();
    };

    _signaling?.onRecordState = (session, state) {
      onRecordingStateChanged?.call(state == RecordState.recording);
    };

    _signaling?.onError = (error) {
      onError?.call(error);
      onOffline?.call();
    };
  }

  void _initializeWebSocket() {
    _socket = WebSocket(_serverUrl + _selfId);

    _socket?.onMessage = (message) => _handleWebSocketMessage(message);

    _socket?.onOpen = () {
      LogUtil.v('WM: WebSocket connected');
      _isWebSocketConnected = true;
      _signaling?.connect();
    };

    _socket?.onClose = (code, reason) {
      _isWebSocketConnected = false;
      onError?.call('WebSocket connection closed: $reason');
      onOffline?.call();
    };

    // Connect to the WebSocket server
    _socket?.connect();
  }

  void _handleWebSocketMessage(dynamic message) {
    if (_signaling != null) {
      LogUtil.v('WM: Received WS message: ${message}');
      _signaling!.onMessage(message);
    }
  }

  void _send(String event, dynamic data) {
    if (_socket != null && _isWebSocketConnected) {
      final message = jsonEncode({'eventName': event, 'data': data});
      LogUtil.v('WM: Sending WS message: $message');
      _socket!.send(message);
    }
  }

  /// Toggle volume for remote audio tracks
  void toggleVolume(bool enabled) {
    if (_signaling != null) {
      _signaling!.muteSpeak(enabled);
    }
  }

  /// Toggle microphone for the local stream
  void toggleMic(bool enabled) {
    if (_signaling != null) {
      _signaling!.muteMic(_sessionId, enabled);
    }
  }

  /// Start recording the remote stream
  Future<void> startRecording() async {
    if (_signaling != null) {
      await _signaling!.startRecord(_sessionId);
    }
  }

  /// Stop recording the remote stream
  Future<void> stopRecording() async {
    if (_signaling != null) {
      await _signaling!.stopRecord(_sessionId);
    }
  }

  /// Capture a frame from the remote stream
  Future<void> captureFrame() async {
    if (_signaling != null) {
      await _signaling!.captureFrame(_sessionId);
    }
  }

  /// Get the local video renderer
  RTCVideoRenderer get localRenderer => _localRenderer;

  /// Get the remote video renderer
  RTCVideoRenderer get remoteRenderer => _remoteRenderer;

  /// Clean up resources
  Future<void> dispose() async {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _signaling?.close();
    _socket?.close();
    onOffline?.call();

    // Clean up event bus listeners
    _delSessionMsgEvent?.cancel();
    _newSessionMsgEvent?.cancel();
  }
}
