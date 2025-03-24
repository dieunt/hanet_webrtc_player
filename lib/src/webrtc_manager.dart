import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'signaling.dart';
import 'utils/event_bus_util.dart';
import 'utils/event_message.dart';
import 'utils/random_string.dart';
import 'utils/websocket.dart';
import 'utils/LogUtil.dart';

/// A class that manages WebSocket connection and WebRTC signaling
class WebRTCManager {
  // WebSocket state
  final String _serverUrl = "https://webrtc-stream.hanet.ai/wswebclient/";
  String _selfId = "";
  String _peerId = "";
  WebSocket? _socket;
  var _delSessionMsgEvent;
  var _newSessionMsgEvent;
  Map<String, String> _sessions = {};
  late SharedPreferences _prefs;
  bool _isWebSocketConnected = false;

  // WebRTC state
  Signaling? _signaling;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _sessionId;

  // Callbacks
  Function(MediaStream?)? onLocalStream;
  Function(MediaStream?)? onRemoteStream;
  Function(bool)? onRecordingStateChanged;
  Function(String)? onError;

  /// Creates a new WebRTCManager instance
  WebRTCManager({
    required String peerId,
  }) {
    _sessionId = RandomString.randomNumeric(32);
    _selfId = Uuid().v4();
    _peerId = peerId;
    _initializeRenderers().then((_) {
      _initializeSignaling(peerId);
      _initializeWebSocket();
    });
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    LogUtil.v('WM: Renderers initialized');
  }

  void _initializeSignaling(String peerId) {
    _signaling = Signaling(
      _selfId,
      peerId,
      false, // onlyDatachannel should be false to allow media
      true, // localVideo should be true to enable video
    );

    // Set up signaling message handler BEFORE connecting
    _signaling?.onSendSignalMessage = (event, data) {
      _send(event, data);
    };

    // Set up callbacks
    _signaling?.onLocalStream = (stream) {
      LogUtil.v(
          "WM: Local stream received with ${stream.getTracks().length} tracks");
      _localRenderer.srcObject = stream;
      _localStream = stream;
      onLocalStream?.call(stream);
    };

    _signaling?.onAddRemoteStream = (session, stream) {
      LogUtil.v(
          "WM: Remote stream received with ${stream.getTracks().length} tracks");
      _remoteRenderer.srcObject = stream;
      _remoteStream = stream;
      onRemoteStream?.call(stream);
    };

    _signaling?.onRemoveRemoteStream = (session, stream) {
      LogUtil.v("WM: Remote stream removed");
      _remoteRenderer.srcObject = null;
      _remoteStream = null;
      onRemoteStream?.call(null);
    };

    _signaling?.onRecordState = (session, state) {
      onRecordingStateChanged?.call(state == RecordState.recording);
    };

    // Handle session creation
    _signaling?.onSessionCreate = (sessionId, peerId, state) {
      LogUtil.v('WM: Session created with state: $state');
      if (state == OnlineState.online) {
        _signaling?.startcall(
          sessionId,
          peerId,
          true, // audio
          true, // video
          true, // localAudio
          false, // localVideo
          true, // datachannel
          'live', // mode
          'MainStream', // source
          'admin', // user
          '123456', // password
        );
      }
    };
  }

  void _initializeWebSocket() {
    LogUtil.init(title: "webrtc", isDebug: true, limitLength: 800);

    // Set up event bus listeners
    _delSessionMsgEvent = eventBus.on<DeleteSessionMsgEvent>((event) {
      var session = _sessions.remove(event.msg);
      if (session != null) {
        LogUtil.v('WM: remove session $session');
      }
    });

    _newSessionMsgEvent = eventBus.on<NewSessionMsgEvent>((event) {
      _sessions[event.msg] = event.msg;
    });

    // Connect to WebSocket
    _connectWebSocket();
  }

  void _connectWebSocket() {
    LogUtil.v('WM: Connecting to WebSocket server...');
    _socket = WebSocket(_serverUrl + (kIsWeb ? _peerId : _selfId));
    _socket?.onMessage = (message) {
      _handleWebSocketMessage(message);
    };
    _socket?.onOpen = () {
      LogUtil.v('WM: WebSocket connected');
      _isWebSocketConnected = true;
      // Now that WebSocket is connected, we can start signaling
      _signaling?.connect();
    };
    _socket?.onClose = (code, reason) {
      LogUtil.v('WM: WebSocket closed: $code - $reason');
      _isWebSocketConnected = false;
      onError?.call('WebSocket connection closed: $reason');
    };
    // Connect to the WebSocket server
    _socket?.connect();
  }

  void _handleWebSocketMessage(dynamic message) {
    try {
      if (_signaling != null) {
        // Log the received message in a formatted way
        try {
          final jsonMessage = jsonDecode(message);
          LogUtil.v(
              'WM: Received WebSocket message: ${jsonEncode(jsonMessage)}');
        } catch (e) {
          // If it's not JSON, log the raw message
          LogUtil.v('WM: Received WebSocket message (raw): $message');
        }
        _signaling!.onMessage(message);
      }
    } catch (e) {
      LogUtil.v('WM: Error handling WebSocket message: $e');
      onError?.call('Error handling message: $e');
    }
  }

  void _send(String event, dynamic data) {
    try {
      if (_socket != null && _isWebSocketConnected) {
        final message = jsonEncode({
          'eventName': event,
          'data': data,
        });
        LogUtil.v('WM: Sending WebSocket message: $message');
        _socket!.send(message);
      } else {
        LogUtil.v('WM: WebSocket not connected');
        onError?.call('WM: WebSocket not connected');
      }
    } catch (e) {
      LogUtil.v('WM: Error sending message: $e');
      onError?.call('WM: Error sending message: $e');
    }
  }

  /// Toggle volume for the remote stream
  void toggleVolume(bool enabled) {
    if (_signaling != null && _sessionId != null) {
      _signaling!.muteSpeekSession(_sessionId!, !enabled);
    }
  }

  /// Toggle microphone for the local stream
  void toggleMic(bool enabled) {
    if (_signaling != null) {
      _signaling!.muteMic(enabled);
    }
  }

  /// Start recording the remote stream
  Future<void> startRecording() async {
    if (_signaling != null && _sessionId != null) {
      await _signaling!.startRecord(_sessionId!);
    }
  }

  /// Stop recording the remote stream
  Future<void> stopRecording() async {
    if (_signaling != null && _sessionId != null) {
      await _signaling!.stopRecord(_sessionId!);
    }
  }

  /// Capture a frame from the remote stream
  Future<void> captureFrame() async {
    if (_signaling != null && _sessionId != null) {
      await _signaling!.captureFrame(_sessionId!);
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

    // Clean up event bus listeners
    _delSessionMsgEvent?.cancel();
    _newSessionMsgEvent?.cancel();
  }
}
