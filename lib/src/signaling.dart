// ignore_for_file: avoid_print, unnecessary_null_comparison

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'utils/random_string.dart';
import 'utils/LogUtil.dart';
import 'dart:io' show Platform;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:hanet_webrtc_player/src/webrtc_manager.dart';

/// Represents the current state of the signaling connection
enum SignalingState {
  /// Connection is open and ready for communication
  connectionOpen,

  /// Connection has been closed
  connectionClosed,

  /// Connection encountered an error
  connectionError,
}

/// Represents the current state of media recording
enum RecordState {
  /// Currently recording
  recording,

  /// Recording has been closed
  recordClosed,
}

/// Represents the current state of a call
enum CallState {
  /// New call initiated
  callStateNew,

  /// Call is ringing
  callStateRinging,

  /// Call invitation sent
  callStateInvite,

  /// Call is connected
  callStateConnected,

  /// Call has ended
  callStateBye,
}

/// Represents the online state of a device
enum OnlineState {
  /// Device is online
  online,

  /// Device is offline
  offline,

  /// Device is in sleep mode
  sleep,

  /// Device encountered an error
  error,
}

/// Represents the direction and state of media (audio/video)
class MediaDirection {
  /// Whether the media type is enabled
  final bool enabled;

  /// Whether local media is enabled
  final bool isLocal;

  /// Creates a new MediaDirection instance
  const MediaDirection(this.enabled, this.isLocal);
}

/// Represents a WebRTC session between peers
class Session {
  /// Creates a new session with the given session ID and peer ID
  Session({
    required this.sid,
    required this.pid,
  });

  /// The peer ID of the remote device
  final String pid;

  /// The session ID for this connection
  final String sid;

  /// Whether audio is enabled
  bool audio = false;

  /// Whether video is enabled
  bool video = false;

  /// Whether data channel is enabled
  bool datachannel = false;

  /// Whether data channel is currently open
  bool datachannelOpened = false;

  /// Whether only data channel is used (no media)
  bool onlyDatachannel = false;

  /// Whether an offer has been made
  bool _offered = false;

  /// Current recording state
  RecordState recordState = RecordState.recordClosed;

  /// The WebRTC peer connection
  RTCPeerConnection? pc;

  /// The WebRTC data channel
  RTCDataChannel? dc;

  /// List of remote media streams
  final List<MediaStream> _remoteStreams = <MediaStream>[];

  /// List of remote ICE candidates
  final List<RTCIceCandidate> remoteCandidates = [];

  /// Whether an offer has been made
  bool get offered => _offered;

  /// Set whether an offer has been made
  set offered(bool value) => _offered = value;

  /// Get the list of remote streams
  List<MediaStream> get remoteStreams => List.unmodifiable(_remoteStreams);

  /// Add a remote stream
  void addRemoteStream(MediaStream stream) {
    _remoteStreams.add(stream);
  }

  /// Remove a remote stream
  void removeRemoteStream(MediaStream stream) {
    _remoteStreams.remove(stream);
  }
}

/// A class that handles WebRTC signaling and peer connections
class Signaling {
  /// Creates a new Signaling instance
  Signaling(
    this._selfId,
    this._peerId,
    this._onlyDatachannel,
    this._localVideo,
  );

  final JsonEncoder _encoder = JsonEncoder();
  final JsonDecoder _decoder = JsonDecoder();

  /// The ID of the local peer
  final String _selfId;

  /// The ID of the remote peer
  final String _peerId;

  /// The current mode of operation
  String _mode = '';

  /// The source of the media stream
  String _source = '';

  /// The username for authentication
  String _user = '';

  /// The password for authentication
  String _password = '';

  /// Whether an offer has been made
  bool _offered = false;

  /// The current session ID
  String _sessionId = RandomString.randomNumeric(32);

  /// Whether only data channel is used
  final bool _onlyDatachannel;

  /// Whether local video is enabled
  bool _localVideo;

  /// Whether local audio is enabled
  bool _localAudio = true;

  /// Whether video is enabled
  bool _video = true;

  /// Whether audio is enabled
  bool _audio = true;

  /// Whether data channel is enabled
  bool _datachannel = true;

  /// The start time of the session
  final int _startTime = RandomString.currentTimeMillis();

  /// The media recorder instance
  final MediaRecorder _mediaRecorder = MediaRecorder();

  /// Map of active sessions
  final Map<String, Session> _sessions = {};

  /// The local media stream
  MediaStream? _localStream;

  /// The remote video track
  MediaStreamTrack? _remoteVideoTrack;

  /// List of remote ICE candidates
  final List<RTCIceCandidate> remoteCandidates = [];

  /// Callback for signaling state changes
  Function(SignalingState state)? onSignalingStateChange;

  /// Callback for call state changes
  Function(Session session, CallState state)? onCallStateChange;

  /// Callback for local stream
  Function(MediaStream stream)? onLocalStream;

  /// Callback for remote stream addition
  Function(Session session, MediaStream stream)? onAddRemoteStream;

  /// Callback for remote stream removal
  Function(Session session, MediaStream stream)? onRemoveRemoteStream;

  /// Callback for received signaling messages
  Function(Session session, String message)? onRecvSignalingMessage;

  /// Callback for data channel messages
  Function(Session session, RTCDataChannel dc, RTCDataChannelMessage data)?
      onDataChannelMessage;

  /// Callback for data channel creation
  Function(Session session, RTCDataChannel dc)? onDataChannel;

  /// Callback for data channel state changes
  Function(Session session, RTCDataChannelState state)? onDataChannelState;

  /// Callback for recording state changes
  Function(Session session, RecordState state)? onRecordState;

  /// Callback for sending signaling messages
  Function(String eventName, dynamic data)? onSendSignalMessage;

  /// Callback for session creation
  Function(String sessionId, String peerId, OnlineState state)? onSessionCreate;

  /// Callback for RTC connection state changes
  Function(Session session, RTCPeerConnectionState state)?
      onSessionRTCConnectState;

  /// Get the SDP semantics based on platform
  String get sdpSemantics =>
      WebRTC.platformIsWindows ? 'plan-b' : 'unified-plan';

  /// ICE server configuration
  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:webrtc-stream.hanet.ai:3478'},
    ]
  };

  /// WebRTC configuration
  final Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
      {'googCpuOveruseDetection': false},
      {'googSuspendBelowMinBitrate': true},
    ]
  };

  /// Data channel constraints
  final Map<String, dynamic> _dcConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
    },
    'optional': [],
  };

  final String _serverUrl = "wss://webrtc-stream.hanet.ai/wswebclient/";
  WebSocketChannel? _ws;

  // Callbacks
  Function(Map<String, dynamic>)? onOffer;
  Function(Map<String, dynamic>)? onAnswer;
  Function(Map<String, dynamic>)? onCandidate;
  Function()? onClose;
  Function(dynamic)? onError;

  bool _isWeb() {
    return kIsWeb == true;
  }

  close() async {
    await _cleanSessions();
  }

  void switchCamera() {
    if (_localStream != null) {
      Helper.switchCamera(_localStream!.getVideoTracks()[0]);
    }
  }

  /*
    使能麦克风 本地声音使能
  */
  void muteMic(bool enabled) {
    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = enabled;
      });
    } else {}
  }

  /*
    使能喇叭  对方声音使能播放
  */
  void muteAllSpeek(bool enabled) {
    _sessions.forEach((key, sess) async {
      for (int i = 0; i < sess._remoteStreams.length; i++) {
        MediaStream item = sess._remoteStreams[i];
        if (item != null) {
          item.getAudioTracks().forEach((track) {
            track.enabled = enabled;
          });
        }
      }
    });
  }

  void muteSpeekSession(String sessionId, bool enabled) {
    var sess = _sessions[sessionId];
    if (sess != null) {
      for (int i = 0; i < sess._remoteStreams.length; i++) {
        MediaStream item = sess._remoteStreams[i];
        if (item != null) {
          item.getAudioTracks().forEach((track) {
            track.enabled = enabled;
          });
        }
      }
    }
  }
  /*
     函数 ： 发起呼叫
     注：  生成一个会话并创建 RTCPeerConnection 并发起Offer
     参数：
     sessionId： 会话ID 用于表示这次会话
     peerId：    设备端ID
     audio：     是否需要音频
     video：     是否需要视频
     localaudio：     是否开始本地音频
     localvideo：     是否开始本地视频
     datachennel：    是否启用datachennel
     mode：       会话模式，用于表示是实时流，远程回放，下载等等，
     source：     会话源，用于表示会话的数据源，例如 实时流的时候。用于表示主通道跟其他通道数据
     user：       用户名，用于设备端校验
     password     用户密码，用于设备端校验
  */

  void invite(
      String sessionId,
      String peerId,
      bool audio,
      bool video,
      bool localaudio,
      bool localvideo,
      bool datachennel,
      String mode,
      String source,
      String user,
      String password) async {
    _sessionId = sessionId;
    _mode = mode;
    _source = source;
    _user = user;
    _password = password;
    _video = video;
    _audio = audio;
    _datachannel = datachennel;
    _localVideo = localvideo;
    _localAudio = localaudio;

    Session session = await _createSession(null,
        peerId: peerId,
        sessionId: sessionId,
        audio: audio,
        video: video,
        dataChannel: datachennel);
    _sessions[sessionId] = session;
    if (datachennel) {
      _createDataChannel(session);
    }
    _createOffer(session, mode, source);
    onCallStateChange?.call(session, CallState.callStateNew);
  }

  /*
     函数 ： 发起呼叫
     注：  发送一个_call 信令，让设备端发起呼叫
     参数：
     sessionId： 会话ID 用于表示这次会话
     peerId：    设备端ID
     audio：     是否需要音频
     video：     是否需要视频
     localaudio：     是否开始本地音频
     localvideo：     是否开始本地视频
     datachennel：    是否启用datachennel
     mode：       会话模式，用于表示是实时流，远程回放，下载等等，
     source：     会话源，用于表示会话的数据源，例如 实时流的时候。用于表示主通道跟其他通道数据
     user：       用户名，用于设备端校验
     password     用户密码，用于设备端校验
  */
  void startcall(
      String sessionId,
      String peerId,
      bool audio,
      bool video,
      bool localaudio,
      bool localvideo,
      bool datachennel,
      String mode,
      String source,
      String user,
      String password) {
    // Log the time taken to reach this point
    var delay = RandomString.currentTimeMillis() - _startTime;
    print('Singaling: <<<<  send call use time  :$delay');

    // Update class variables with the call parameters
    _mode = mode;
    _source = source;
    _localVideo = localvideo;
    _localAudio = localaudio;
    _video = video;
    _audio = audio;
    _datachannel = datachennel;

    // Determine the direction settings for media streams
    final datachanneldir = datachennel ? 'true' : 'false';
    final videodir = _determineVideoDirection(video, localvideo);
    final audiodir = _determineAudioDirection(audio, localaudio);

    // Send the call request with all parameters
    _send('__call', {
      "sessionId": sessionId,
      'sessionType': kIsWeb ? "IE" : "flutter",
      'messageId': RandomString.randomNumeric(32),
      'from': _selfId,
      'to': peerId,
      "mode": mode,
      "source": source,
      "datachannel": datachanneldir,
      "audio": audiodir,
      "video": videodir,
      "user": user,
      "pwd": password,
      "iceservers": _encoder.convert(_iceServers)
    });
  }

  /// Determines the video direction based on video and local video settings
  String _determineVideoDirection(bool video, bool localvideo) {
    if (video) {
      return localvideo ? 'sendrecv' : 'recvonly';
    }
    return 'false';
  }

  /// Determines the audio direction based on audio and local audio settings
  String _determineAudioDirection(bool audio, bool localaudio) {
    if (audio) {
      return localaudio ? 'sendrecv' : 'recvonly';
    }
    return 'false';
  }

  /*
    使用信令通道给设备发送信息
  */
  void postmessage(String sessionId, String message) async {
    var sess = _sessions[sessionId];
    if (sess != null) {
      _send('__post_message', {
        "sessionId": sess.sid,
        'sessionType': "flutter",
        'messageId': RandomString.randomNumeric(32),
        'from': _selfId,
        'to': sess.pid,
        "message": message
      });
    }
  }

  /*
    发送 __disconnected 信令给设备。让设备断开链接
  */
  void bye(String sessionId) {
    var sess = _sessions[sessionId];
    if (sess != null) {
      _send('__disconnected', {
        "sessionId": sess.sid,
        'sessionType': "flutter",
        'messageId': RandomString.randomNumeric(32),
        'from': _selfId,
        'to': sess.pid
      });
      _closeSession(sess);
    }
  }

  int compare(String str1, String str2) {
    var res = Comparable.compare(str1, str2);
    return res;
  }

  void onMessage(dynamic message) async {
    Map<String, dynamic> mapData = jsonDecode(message);
    var eventName = mapData['eventName'];
    var data = mapData['data'];

    LogUtil.v('Signaling: Processing message type: $eventName');

    switch (eventName) {
      case '_create':
        _handleCreateMessage(data);
        break;

      case '_offer':
        await _handleOfferMessage(data);
        break;

      case '_call':
        _handleCallMessage(data);
        break;

      case '_answer':
        _handleAnswerMessage(data);
        break;

      case '_ice_candidate':
        await _handleIceCandidateMessage(data);
        break;

      case '_disconnected':
        _handleDisconnectedMessage(data);
        break;

      case '_session_failed':
        _handleSessionFailedMessage(data);
        break;

      case '_post_message':
        _handlePostMessage(data);
        break;

      case '_connectinfo':
        LogUtil.v("Signaling: Received connect info");
        break;

      case '_ping':
        LogUtil.v("Signaling: Received keepalive response");
        break;

      default:
        LogUtil.v("Signaling: Received unknown message type: $eventName");
        break;
    }
  }

  void _handleCreateMessage(Map<String, dynamic> data) {
    var sessionId = data['sessionId'];
    var peerId = data['from'];
    var state = data['state'];

    // Handle ICE servers configuration if provided
    var iceServers = data['iceServers'];
    if (iceServers != null) {
      if (iceServers is String) {
        LogUtil.v('Signaling: Updating ICE servers from string');
        _iceServers = _decoder.convert(iceServers);
      } else {
        var subIceServers = iceServers['iceServers'];
        _iceServers = subIceServers ?? iceServers;
      }
    }

    // Determine online state
    if (state != null) {
      if (compare(state, "online") == 0) {
        onSessionCreate?.call(sessionId, peerId, OnlineState.online);
      } else if (compare(state, "sleep") == 0) {
        onSessionCreate?.call(sessionId, peerId, OnlineState.sleep);
      } else {
        onSessionCreate?.call(sessionId, peerId, OnlineState.offline);
      }
    } else {
      onSessionCreate?.call(sessionId, peerId, OnlineState.error);
    }
  }

  Future<void> _handleOfferMessage(Map<String, dynamic> data) async {
    try {
      var sessionId = data['sessionId'];
      var peerId = data['from'];
      var sdp = data['sdp'];

      if (sessionId == null || peerId == null || sdp == null) {
        LogUtil.v("Signaling: Missing required fields in offer message");
        return;
      }

      // Update ICE servers if provided
      var iceServers = data['iceservers'];
      if (iceServers != null && iceServers.toString().isNotEmpty) {
        _iceServers = _decoder.convert(iceServers);
      }

      // Parse media directions
      var useDataChannel = _parseDirection(data['datachannel'], true);
      var useAudio = _parseAudioDirection(data['audio']);
      var useVideo = _parseVideoDirection(data['video']);

      // Create or get existing session
      var session = _sessions[sessionId];
      var newSession = await _createSession(session,
          peerId: peerId,
          sessionId: sessionId,
          audio: useAudio.enabled,
          video: useVideo.enabled,
          dataChannel: useDataChannel);

      _sessions[sessionId] = newSession;

      // Set up data channel if needed
      if (useDataChannel) {
        _createDataChannel(newSession);
      }

      // Set remote description and create answer
      await newSession.pc
          ?.setRemoteDescription(RTCSessionDescription(sdp, "offer"));
      await _createAnswer(newSession);

      // Add any pending candidates
      await _addPendingCandidates(newSession);

      onCallStateChange?.call(newSession, CallState.callStateNew);
    } catch (e) {
      LogUtil.v("Signaling: Error handling offer message: $e");
    }
  }

  void _handleCallMessage(Map<String, dynamic> data) {
    if (data['sessionId'] == null || data['from'] == null) {
      LogUtil.v("Signaling: Missing required fields in call message");
      return;
    }

    var sessionId = data['sessionId'];
    var peerId = data['from'];

    // Update ICE servers if provided
    var iceServers = data['iceservers'];
    if (iceServers != null) {
      _iceServers = _decoder.convert(iceServers);
    }

    // Parse media directions
    var useDataChannel = _parseDirection(data['datachannel'], true);
    var useAudio = _parseAudioDirection(data['audio']);
    var useVideo = _parseVideoDirection(data['video']);

    // Create session with parsed parameters
    invite(
        sessionId,
        peerId,
        useAudio.enabled,
        useVideo.enabled,
        useAudio.isLocal,
        useVideo.isLocal,
        useDataChannel,
        _mode,
        _source,
        _user,
        _password);
  }

  void _handleAnswerMessage(Map<String, dynamic> data) {
    var sessionId = data['sessionId'];
    if (compare(sessionId, _sessionId) == 0) {
      var session = _sessions[sessionId];
      var type = data['type'];
      var sdp = data['sdp'];

      if (session != null && type != null && sdp != null) {
        session.pc?.setRemoteDescription(RTCSessionDescription(sdp, type));
      }
    }
  }

  Future<void> _handleIceCandidateMessage(Map<String, dynamic> data) async {
    try {
      var sessionId = data['sessionId'];
      if (compare(sessionId, _sessionId) != 0) {
        return;
      }

      var candidateMap = data['candidate'];
      if (candidateMap == null) {
        return;
      }

      var candidateObj = _decoder.convert(candidateMap);
      var candidate = candidateObj['candidate'];
      var sdpMLineIndex = candidateObj['sdpMLineIndex'];
      var sdpMid = candidateObj['sdpMid'];

      if (candidate == null || sdpMLineIndex == null || sdpMid == null) {
        LogUtil.v("Signaling: Invalid ICE candidate data");
        return;
      }

      var session = _sessions[sessionId];
      var iceCandidate = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);

      if (session != null) {
        if (session.pc != null) {
          LogUtil.v("Signaling: Adding ICE candidate");
          await session.pc?.addCandidate(iceCandidate);
        } else {
          LogUtil.v("Signaling: Storing ICE candidate for later");
          session.remoteCandidates.add(iceCandidate);
        }
      } else {
        LogUtil.v("Signaling: No session found, storing candidate globally");
        remoteCandidates.add(iceCandidate);
      }
    } catch (e) {
      LogUtil.v("Signaling: Error handling ICE candidate: $e");
    }
  }

  void _handleDisconnectedMessage(Map<String, dynamic> data) {
    var sessionId = data['sessionId'];
    if (compare(sessionId, _sessionId) == 0) {
      var session = _sessions.remove(sessionId);
      if (session != null) {
        onCallStateChange?.call(session, CallState.callStateBye);
        _closeSession(session);
      }
    }
  }

  void _handleSessionFailedMessage(Map<String, dynamic> data) {
    var sessionId = data['sessionId'];
    if (compare(sessionId, _sessionId) == 0) {
      var session = _sessions.remove(sessionId);
      if (session != null) {
        onCallStateChange?.call(session, CallState.callStateBye);
        _closeSession(session);
      }
    }
  }

  void _handlePostMessage(Map<String, dynamic> data) {
    var sessionId = data['sessionId'];
    if (compare(sessionId, _sessionId) == 0) {
      var session = _sessions[sessionId];
      var message = data['message'];
      if (session != null && message != null) {
        onRecvSignalingMessage?.call(session, message);
      }
    }
  }

  Future<void> _addPendingCandidates(Session session) async {
    if (session.remoteCandidates.isNotEmpty) {
      LogUtil.v("Signaling: Adding pending session candidates");
      for (var candidate in session.remoteCandidates) {
        await session.pc?.addCandidate(candidate);
      }
      session.remoteCandidates.clear();
    }

    if (remoteCandidates.isNotEmpty) {
      LogUtil.v("Signaling: Adding pending global candidates");
      for (var candidate in remoteCandidates) {
        await session.pc?.addCandidate(candidate);
      }
      remoteCandidates.clear();
    }
  }

  MediaDirection _parseAudioDirection(String? direction) {
    if (direction == null) return MediaDirection(false, false);

    switch (direction) {
      case 'sendrecv':
      case 'sendonly':
      case 'true':
        return MediaDirection(true, true);
      case 'recvonly':
        return MediaDirection(true, false);
      default:
        return MediaDirection(false, false);
    }
  }

  MediaDirection _parseVideoDirection(String? direction) {
    if (direction == null) return MediaDirection(false, false);

    switch (direction) {
      case 'sendrecv':
      case 'sendonly':
      case 'true':
        return MediaDirection(true, true);
      case 'recvonly':
        return MediaDirection(true, false);
      default:
        return MediaDirection(false, false);
    }
  }

  bool _parseDirection(String? direction, bool defaultValue) {
    if (direction == null) return defaultValue;
    return direction.toLowerCase() == 'true';
  }

  void connect() {
    LogUtil.v("Signaling: Connecting to WebSocket server...");
    _ws = WebSocketChannel.connect(Uri.parse(_serverUrl));
    _ws?.stream.listen(
      (message) {
        LogUtil.v("Signaling: WebSocket message received: $message");
        onMessage(message);
      },
      onError: (error) {
        LogUtil.v("Signaling: WebSocket error: $error");
        onError?.call(error);
      },
      onDone: () {
        LogUtil.v("Signaling: WebSocket connection closed");
        onClose?.call();
      },
    );

    // Send connection request
    _send('__connectto', {
      'sessionId': _sessionId,
      'sessionType': "flutter",
      'messageId': RandomString.randomNumeric(32),
      'from': _selfId,
      'to': _peerId
    });
  }

  Future<MediaStream?> createLocalStream(
      bool audio, bool video, bool datachannel) async {
    LogUtil.v("Signaling: Starting createLocalStream");
    LogUtil.v(
        "Signaling: Parameters - audio: $audio, video: $video, datachannel: $datachannel");

    try {
      final Map<String, dynamic> mediaConstraints = {
        'audio': audio,
        'video': video
            ? {
                'mandatory': {
                  'minWidth': '640',
                  'minHeight': '480',
                  'minFrameRate': '30',
                },
                'facingMode': 'user',
                'optional': [],
              }
            : false,
      };

      LogUtil.v("Signaling: Using media constraints: $mediaConstraints");
      LogUtil.v("Signaling: Requesting user media...");

      final stream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);

      if (stream != null) {
        LogUtil.v(
            "Signaling: Local stream created successfully with ${stream.getTracks().length} tracks");
        for (var track in stream.getTracks()) {
          LogUtil.v(
              "Signaling: Track kind: ${track.kind}, enabled: ${track.enabled}, muted: ${track.muted}");
        }
        return stream;
      } else {
        LogUtil.v("Signaling: Failed to create local stream - stream is null");
        throw Exception("Failed to create local stream - stream is null");
      }
    } catch (e) {
      LogUtil.v("Signaling: Error creating local stream: $e");
      throw Exception("Error creating local stream: $e");
    }
  }

  Future<Session> _createSession(Session? session,
      {required String peerId,
      required String sessionId,
      required bool audio,
      required bool video,
      required bool dataChannel}) async {
    try {
      LogUtil.v("Signaling: Creating new session for peer: $peerId");
      LogUtil.v(
          "Signaling: Session parameters - audio: $audio, video: $video, dataChannel: $dataChannel");

      // Check if session already exists
      if (_sessions.containsKey(sessionId)) {
        LogUtil.v("Signaling: Session already exists, reusing");
        return _sessions[sessionId]!;
      }

      var newSession = session ?? Session(sid: sessionId, pid: peerId);
      newSession.audio = audio;
      newSession.video = video;
      newSession.datachannel = dataChannel;
      newSession.recordState = RecordState.recordClosed;
      LogUtil.v("Signaling: Session object created successfully");

      // Store session immediately to prevent race conditions
      _sessions[sessionId] = newSession;

      if (_onlyDatachannel == false &&
          (_localAudio == true || _localVideo == true)) {
        LogUtil.v("Signaling: Creating local stream...");
        try {
          _localStream = await createLocalStream(audio, video, dataChannel);
          if (_localStream == null) {
            LogUtil.v("Signaling: Failed to create local stream");
            throw Exception("Failed to create local stream");
          }
          LogUtil.v("Signaling: Local stream created successfully");
        } catch (e) {
          LogUtil.v("Signaling: Error creating local stream: $e");
          // Clean up session if stream creation fails
          _sessions.remove(sessionId);
          throw Exception("Error creating local stream: $e");
        }
      } else {
        LogUtil.v(
            "Signaling: Skipping local stream creation - onlyDatachannel: $_onlyDatachannel, localAudio: $_localAudio, localVideo: $_localVideo");
      }

      try {
        LogUtil.v(
            "Signaling: Creating peer connection with ICE servers: $_iceServers");
        LogUtil.v("Signaling: Using SDP semantics: $sdpSemantics");

        RTCPeerConnection pc = await createPeerConnection({
          ..._iceServers,
          ...{'tcpCandidatePolicy': 'disabled'},
          ...{'disableIpv6': true},
          ...{'sdpSemantics': sdpSemantics}
        }, _config);

        if (pc == null) {
          LogUtil.v("Signaling: Failed to create peer connection");
          // Clean up session if peer connection creation fails
          _sessions.remove(sessionId);
          throw Exception("Failed to create peer connection");
        }
        LogUtil.v("Signaling: Peer connection created successfully");

        if (_onlyDatachannel == false) {
          LogUtil.v("Signaling: Setting up media tracks");
          switch (sdpSemantics) {
            case 'plan-b':
              LogUtil.v("Signaling: Using Plan-B SDP semantics");
              pc.onAddStream = (MediaStream stream) {
                LogUtil.v("Signaling: Adding remote stream (plan-b)");
                onAddRemoteStream?.call(newSession, stream);
                newSession._remoteStreams.add(stream);
              };
              if (_localStream != null) {
                LogUtil.v(
                    "Signaling: Adding local stream to peer connection (plan-b)");
                await pc.addStream(_localStream!);
              }
              break;
            case 'unified-plan':
              LogUtil.v("Signaling: Using Unified-Plan SDP semantics");
              pc.onTrack = (event) {
                LogUtil.v("Signaling: Adding remote track (unified-plan)");
                onAddRemoteStream?.call(newSession, event.streams[0]);
                newSession._remoteStreams.add(event.streams[0]);
              };
              if (_localStream != null) {
                LogUtil.v(
                    "Signaling: Adding local tracks to peer connection (unified-plan)");
                _localStream!.getTracks().forEach((track) {
                  pc.addTrack(track, _localStream!);
                });
              }
              break;
          }
        }

        LogUtil.v("Signaling: Setting up peer connection event handlers");
        pc.onIceCandidate = (candidate) async {
          if (candidate == null) {
            LogUtil.v("Signaling: ICE gathering completed");
            return;
          }
          try {
            LogUtil.v("Signaling: Sending ICE candidate");
            await Future.delayed(
                const Duration(milliseconds: 10),
                () => _send('__ice_candidate', {
                      'sessionId': newSession.sid,
                      'sessionType': "flutter",
                      'messageId': RandomString.randomNumeric(32),
                      'from': _selfId,
                      'to': newSession.pid,
                      "candidate": _encoder.convert({
                        'candidate': candidate.candidate,
                        'sdpMid': candidate.sdpMid,
                        'sdpMLineIndex': candidate.sdpMLineIndex
                      })
                    }));
          } catch (e) {
            LogUtil.v("Signaling: Error sending ICE candidate: $e");
          }
        };

        pc.onSignalingState = (state) {
          LogUtil.v("Signaling: Signaling state changed: $state");
        };

        pc.onConnectionState = (state) {
          LogUtil.v("Signaling: Connection state changed: $state");
          onSessionRTCConnectState?.call(newSession, state);
        };

        pc.onIceGatheringState = (state) {
          LogUtil.v("Signaling: ICE gathering state changed: $state");
        };

        pc.onIceConnectionState = (state) {
          LogUtil.v("Signaling: ICE connection state changed: $state");
        };

        pc.onAddStream = (stream) {
          LogUtil.v("Signaling: Remote stream added");
          stream.getVideoTracks().forEach((videoTrack) {
            if (_remoteVideoTrack == null) {
              _remoteVideoTrack = videoTrack;
              LogUtil.v("Signaling: Remote video track set");
            }
          });
        };

        pc.onRemoveStream = (stream) {
          LogUtil.v("Signaling: Remote stream removed");
          onRemoveRemoteStream?.call(newSession, stream);
          newSession._remoteStreams.removeWhere((it) {
            return (it.id == stream.id);
          });
          stream.getVideoTracks().forEach((videoTrack) {
            if (_remoteVideoTrack == videoTrack) {
              _remoteVideoTrack = null;
              LogUtil.v("Signaling: Remote video track cleared");
            }
          });
        };

        pc.onAddTrack = (stream, track) {
          LogUtil.v("Signaling: Remote track added: ${track.kind}");
          if (track.kind == "video") {
            _remoteVideoTrack = track;
            LogUtil.v("Signaling: Remote video track set");
          }
        };

        pc.onRemoveTrack = (stream, track) {
          LogUtil.v("Signaling: Remote track removed: ${track.kind}");
          if (track.kind == "video") {
            if (_remoteVideoTrack == track) {
              _remoteVideoTrack = null;
              LogUtil.v("Signaling: Remote video track cleared");
            }
          }
        };

        pc.onDataChannel = (channel) {
          LogUtil.v("Signaling: Data channel received");
          _addDataChannel(newSession, channel);
        };

        newSession.pc = pc;
        LogUtil.v("Signaling: Session created successfully");
        return newSession;
      } catch (e) {
        LogUtil.v("Signaling: Error setting up peer connection: $e");
        // Clean up session if peer connection setup fails
        _sessions.remove(sessionId);
        throw Exception("Error setting up peer connection: $e");
      }
    } catch (e) {
      LogUtil.v("Signaling: Error creating session: $e");
      // Clean up any partial session
      if (_sessions.containsKey(sessionId)) {
        _sessions.remove(sessionId);
      }
      throw Exception("Error creating session: $e");
    }
  }

  void _addDataChannel(Session session, RTCDataChannel channel) {
    channel.onDataChannelState = (e) {
      if (e == RTCDataChannelState.RTCDataChannelOpen) {
        session.datachannelOpened = true;
      } else if (e == RTCDataChannelState.RTCDataChannelClosing) {
        session.datachannelOpened = false;
      } else if (e == RTCDataChannelState.RTCDataChannelClosed) {
        session.datachannelOpened = false;
      } else if (e == RTCDataChannelState.RTCDataChannelConnecting) {
        session.datachannelOpened = false;
      }
      onDataChannelState?.call(session, e);
    };
    channel.onMessage = (RTCDataChannelMessage data) {
      onDataChannelMessage?.call(session, channel, data);
    };
    session.dc = channel;
    onDataChannel?.call(session, channel);
  }

  Future<void> _createDataChannel(Session session,
      {label = 'fileTransfer'}) async {
    RTCDataChannelInit dataChannelDict = RTCDataChannelInit()
      ..maxRetransmits = 30;
    RTCDataChannel channel =
        await session.pc!.createDataChannel(label, dataChannelDict);
    _addDataChannel(session, channel);
  }

  Future<void> _createOffer(Session session, String mode, String source) async {
    try {
      Map<String, dynamic> dcConstraints = {
        'mandatory': {
          'OfferToReceiveAudio': session.audio,
          'OfferToReceiveVideo': session.video,
        },
        'optional': [],
      };

      RTCSessionDescription s =
          await session.pc!.createOffer(_onlyDatachannel ? {} : dcConstraints);
      await session.pc!.setLocalDescription(s);
      // LogUtil.v("Signaling: Created offer SDP: ${s.sdp}");

      var datachanneldir = 'true';
      var audiodir = 'sendrecv';
      var videodir = 'sendrecv';
      if (_video == true && _localVideo == false) {
        videodir = 'recvonly';
      } else if (_video == true && _localVideo == true) {
        videodir = 'sendrecv';
      } else {
        videodir = 'false';
      }
      if (_datachannel == true) {
        datachanneldir = 'true';
      } else {
        datachanneldir = 'false';
      }
      if (_audio == true && _localAudio == true) {
        audiodir = 'sendrecv';
      } else if (_audio == true && _localAudio == false) {
        audiodir = 'recvonly';
      } else {
        audiodir = 'false';
      }
      _send('__offer', {
        'sessionId': session.sid,
        'sessionType': "flutter",
        'messageId': RandomString.randomNumeric(32),
        'from': _selfId,
        'to': session.pid,
        "type": s.type,
        "sdp": s.sdp,
        "mode": mode,
        "source": source,
        "datachannel": datachanneldir,
        "audio": audiodir,
        "video": videodir,
        "user": _user,
        "pwd": _password,
        "iceservers": _encoder.convert(_iceServers)
      });
    } catch (e) {
      LogUtil.v("Signaling: Error creating offer: $e");
    }
  }

  Future<void> _createAnswer(Session session) async {
    try {
      Map<String, dynamic> dcConstraints = {};

      RTCSessionDescription s =
          await session.pc!.createAnswer(_onlyDatachannel ? {} : dcConstraints);
      await session.pc!.setLocalDescription(s);
      var delay = RandomString.currentTimeMillis() - _startTime;
      LogUtil.v("Signaling: Created answer after delay: $delay");
      LogUtil.v("Signaling: Created answer SDP: ${s.sdp}");
      _send('__answer', {
        "type": s.type,
        "sdp": s.sdp,
        'sessionId': session.sid,
        'sessionType': "flutter",
        'messageId': RandomString.randomNumeric(32),
        'from': _selfId,
        'to': session.pid
      });
    } catch (e) {
      LogUtil.v("Signaling: Error creating answer: $e");
    }
  }

  void _send(event, data) {
    onSendSignalMessage?.call(event, data);
  }

  Future<void> _cleanSessions() async {
    _sessions.forEach((key, sess) async {
      if (sess.recordState == RecordState.recording) {
        await _mediaRecorder.stop();
        sess.recordState = RecordState.recordClosed;
      }
    });
    if (_localStream != null) {
      _localStream!.getTracks().forEach((element) async {
        await element.stop();
      });
      await _localStream!.dispose();
      _localStream = null;
    }
    _sessions.forEach((key, sess) async {
      await sess.dc?.close();
      await sess.pc?.close();
    });

    _sessions.clear();
  }

  void _closeSessionByPeerId(String peerId) {
    var session;
    _sessions.removeWhere((String key, Session sess) {
      var ids = key.split('-');
      session = sess;
      return peerId == ids[0] || peerId == ids[1];
    });
    if (session != null) {
      _closeSession(session);
      onCallStateChange?.call(session, CallState.callStateBye);
    }
  }

  Future<void> _closeSession(Session session) async {
    if (session.recordState == RecordState.recording) {
      await _mediaRecorder.stop();
      session.recordState = RecordState.recordClosed;
    }
    _localStream?.getTracks().forEach((element) async {
      await element.stop();
    });
    await _localStream?.dispose();
    _localStream = null;
    await session.dc?.close();
    await session.pc?.close();
  }

  /*
    开始录像
  */
  Future<void> startRecord(String sessionId) async {
    LogUtil.v("Signaling: Starting recording for session: $sessionId");
    var sess = _sessions[sessionId];
    if (sess != null) {
      if (sess.recordState == RecordState.recordClosed) {
        try {
          var appDocDir;
          if (Platform.isIOS) {
            appDocDir = await getApplicationDocumentsDirectory();
          } else if (Platform.isAndroid) {
            appDocDir = await getExternalStorageDirectory();
          } else {
            return;
          }
          String appDocPath = appDocDir!.path;
          print('startRecord appDocPath : $appDocPath');
          List<RTCRtpReceiver> receivers = await sess.pc!.getReceivers();
          bool startrecorded = false;
          receivers.forEach((receive) {
            print(
                'startRecord track ------------------------: ${receive.track}');
            if (receive.track!.kind == "video") {
              if (_remoteVideoTrack != null) {
                if (_remoteVideoTrack!.id == receive.track!.id) {
                  if (startrecorded == false) {
                    startrecorded = true;
                    if (!_isWeb()) {
                      _mediaRecorder.start('$appDocPath/test.mp4',
                          videoTrack: receive.track);
                      sess.recordState = RecordState.recording;
                      onRecordState?.call(sess, RecordState.recording);
                    }
                  }
                }
              }
            }
          });
        } catch (err) {
          print(err);
        }
      } else {
        print('startRecord  is recording');
      }
    } else {
      print('startRecord  is no session $sessionId');
    }
  }

  /*
    停止录像
  */
  Future<void> stopRecord(String sessionId) async {
    LogUtil.v("Signaling: Stopping recording for session: $sessionId");
    print('stopRecord  -------------------------------------------');
    var sess = _sessions[sessionId];
    if (sess != null) {
      if (sess.recordState == RecordState.recording) {
        print('stopRecord  ');
        await _mediaRecorder.stop();
        sess.recordState = RecordState.recordClosed;
        onRecordState?.call(sess, RecordState.recordClosed);
        print('stopRecord  end');
      }
    }
  }

  /*
    截取一张图片并保存
  */
  Future<void> captureFrame(String sessionId) async {
    LogUtil.v("Signaling: Capturing frame for session: $sessionId");
    var sess = _sessions[sessionId];
    if (sess != null) {
      try {
        var appDocDir;
        if (Platform.isIOS) {
          appDocDir = await getApplicationDocumentsDirectory();
        } else if (Platform.isAndroid) {
          appDocDir = await getExternalStorageDirectory();
        } else {
          return;
        }
        String appDocPath = appDocDir!.path;
        print('captureFrame appPath: ' + appDocPath);
        String captureFilepath = "$appDocPath" +
            "/" +
            sess.sid +
            RandomString.randomNumeric(32) +
            ".jpg";

        List<RTCRtpReceiver> receivers = await sess.pc!.getReceivers();

        for (int i = 0; i < receivers.length; i++) {
          RTCRtpReceiver receive = receivers[i];
          if (receive.track!.kind!.isNotEmpty) {
            if (receive.track!.kind!.compareTo("video") == 0) {
              if (_remoteVideoTrack != null) {
                if (_remoteVideoTrack!.id == receive.track!.id) {
                  print('captureFrame track : ${receive.track!.kind}');
                  final buffer = await receive.track!.captureFrame();
                  if (buffer != null) {
                    final byteData = ByteData.view(buffer);
                    await writeToFile(byteData, captureFilepath);
                  }
                }
              }
            }
          }
        }
      } catch (err) {
        print(err);
      }
    }
  }

  Future<void> writeToFile(ByteData data, String path) async {
    try {
      final buffer = data.buffer;
      final file = File(path);
      await file.writeAsBytes(
          buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      LogUtil.v("Signaling: Frame saved to: $path");
    } catch (e) {
      LogUtil.v("Signaling: Error writing frame to file: $e");
    }
  }

  /*
    发送 使用 datachennel 发送 文本数据
  */
  Future<void> dataChannelSendTextMsg(String sessionId, String msg) async {
    var sess = _sessions[sessionId];
    if (sess != null) {
      if (sess.datachannelOpened == true) {
        await sess.dc?.send(RTCDataChannelMessage(msg));
      }
    }
  }

  /*
    发送 使用 datachennel 发送 原始
  */
  Future<void> dataChannelSendRawMsg(String sessionId, Uint8List data) async {
    var sess = _sessions[sessionId];
    if (sess != null) {
      if (sess.datachannelOpened == true) {
        await sess.dc?.send(RTCDataChannelMessage.fromBinary(data));
      }
    }
  }
}
