// ignore_for_file: avoid_print, unnecessary_null_comparison

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'utils/utils.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'utils/web_utils.dart' if (dart.library.io) 'utils/web_utils_stub.dart'
    as web_utils;

/// Signaling connection state
enum SignalingState {
  connectionOpen,
  connectionClosed,
  connectionError,
}

/// Media recording state
enum RecordState {
  recording,
  recordClosed,
}

/// Call state
enum CallState {
  callStateNew,
  callStateRinging,
  callStateInvite,
  callStateConnected,
  callStateBye,
}

/// Device online state
enum OnlineState {
  online,
  offline,
  sleep,
  error,
}

/// Media direction configuration
class MediaDirection {
  final bool enabled;
  final bool isLocal;
  const MediaDirection(this.enabled, this.isLocal);
}

/// WebRTC session between peers
class Session {
  /// Creates a new session with the given session ID and peer ID
  Session({
    required this.sid,
    required this.pid,
  });

  final String pid;
  final String sid;

  bool audio = false;
  bool video = false;
  bool datachannel = false;
  bool datachannelOpened = false;
  bool onlyDatachannel = false;
  bool _offered = false;

  /// Current recording state
  RecordState recordState = RecordState.recordClosed;

  RTCPeerConnection? pc;
  RTCDataChannel? dc;

  /// List of remote media streams
  final List<MediaStream> _remoteStreams = <MediaStream>[];
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

/// WebRTC signaling and peer connection handler
class Signaling {
  /// Creates a new Signaling instance
  Signaling(
    this._selfId,
    this._peerId,
    this._sessionId,
    this._onlyDatachannel,
    this._localVideo,
  );

  final JsonEncoder _encoder = JsonEncoder();
  final JsonDecoder _decoder = JsonDecoder();

  final String _selfId;
  final String _peerId;
  final String _sessionId; // Make it final to prevent accidental changes
  final bool _onlyDatachannel;

  String _mode = 'live';
  String _source = 'SubStream';
  String _user = '';
  String _password = '';
  bool _offered = false;
  bool _localVideo = false;
  bool _localAudio = false;
  bool _video = false;
  bool _audio = false;
  bool _datachannel = true;
  MediaStream? _localStream;
  MediaStreamTrack? _remoteVideoTrack;

  final int _startTime = RandomString.currentTimeMillis();
  MediaRecorder _mediaRecorder = MediaRecorder();
  final Map<String, Session> _sessions = {};
  final List<RTCIceCandidate> remoteCandidates = [];

  // Callbacks
  Function(Map<String, dynamic>)? onOffer;
  Function(Map<String, dynamic>)? onAnswer;
  Function(Map<String, dynamic>)? onCandidate;
  Function()? onClose;
  Function(dynamic)? onError;

  Function(SignalingState state)? onSignalingStateChange;
  Function(Session session, CallState state)? onCallStateChange;
  Function(MediaStream stream)? onLocalStream;
  Function(Session session, MediaStream stream)? onAddRemoteStream;
  Function(Session session, MediaStream stream)? onRemoveRemoteStream;
  Function(Session session, String message)? onRecvSignalingMessage;
  Function(Session session, RTCDataChannel dc, RTCDataChannelMessage data)?
      onDataChannelMessage;
  Function(Session session, RTCDataChannel dc)? onDataChannel;
  Function(Session session, RTCDataChannelState state)? onDataChannelState;
  Function(Session session, RecordState state)? onRecordState;
  Function(String eventName, dynamic data)? onSendSignalMessage;
  Function(String sessionId, String peerId, OnlineState state)? onSessionCreate;
  Function(Session session, RTCPeerConnectionState state)?
      onSessionRTCConnectState;

  /// Get the SDP semantics based on platform
  String get sdpSemantics =>
      WebRTC.platformIsWindows ? 'plan-b' : 'unified-plan';

  /// ICE server configuration
  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:webrtc-stream.hanet.ai:3478'}
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

  /// Toggle local microphone
  Future<void> muteMic(String sessionId, bool enabled) async {
    _localAudio = enabled;

    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = enabled;
      });
    }

    if (enabled && _localStream == null) {
      var session = _sessions[sessionId];
      if (session != null) {
        RTCPeerConnection? pc = session.pc;
        if (pc == null) {
          return;
        }

        _localStream = await createLocalStream(_audio, _datachannel);
        _localStream!.getTracks().forEach((track) async {
          await pc.addTrack(track, _localStream!);
        });

        _localStream!.getAudioTracks().forEach((track) {
          track.enabled = true;
        });

        var newSession = await _createSession(null,
            peerId: _peerId,
            sessionId: RandomString.randomString(32),
            audio: true,
            video: false,
            dataChannel: _datachannel);

        //     _sessions[sessionId] = newSession;
        //     await _createOffer(newSession, _mode, _source);
      }
    }
  }

  /// Mute or unmute the remote audio stream
  void muteSpeak(bool enabled) async {
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

  /// Start call with given parameters
  void startcall(
      String sessionId,
      String peerId,
      bool audio,
      bool video,
      bool localaudio,
      bool localvideo,
      bool datachannel,
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
    _datachannel = datachannel;

    // Determine the direction settings for media streams
    final datachanneldir = datachannel ? 'true' : 'false';
    // final videodir = _determineVideoDirection(video, false);
    final videodir = 'recvonly';
    final audiodir = localaudio ? 'sendrecv' : 'recvonly';

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

  /// Send message via signaling channel
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

  /// Disconnect from device
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
        // _handleCallMessage(data);
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

  // void _handleCallMessage(Map<String, dynamic> data) {
  //   if (data['sessionId'] == null || data['from'] == null) {
  //     LogUtil.v("Signaling: Missing required fields in call message");
  //     return;
  //   }

  //   var sessionId = data['sessionId'];
  //   var peerId = data['from'];

  //   // Update ICE servers if provided
  //   var iceServers = data['iceservers'];
  //   if (iceServers != null) {
  //     _iceServers = _decoder.convert(iceServers);
  //   }

  //   // Parse media directions
  //   var useDataChannel = _parseDirection(data['datachannel'], true);
  //   var useAudio = _parseAudioDirection(data['audio']);
  //   var useVideo = _parseVideoDirection(data['video']);

  //   // Create session with parsed parameters
  //   invite(
  //       sessionId,
  //       peerId,
  //       useAudio.enabled,
  //       useVideo.enabled,
  //       useAudio.isLocal,
  //       useVideo.isLocal,
  //       useDataChannel,
  //       _mode,
  //       _source,
  //       _user,
  //       _password);
  // }

  void _handleAnswerMessage(Map<String, dynamic> data) {
    var sessionId = data['sessionId'];
    if (compare(sessionId, _sessionId) == 0) {
      var session = _sessions[sessionId];
      var type = data['type'];
      var sdp = data['sdp'];

      session?.pc?.setRemoteDescription(RTCSessionDescription(sdp, type));
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
    LogUtil.v("Signaling: WebSocket connected");
    _send('__connectto', {
      'sessionId': _sessionId,
      'sessionType': kIsWeb ? 'IE' : "flutter",
      'messageId': RandomString.randomNumeric(32),
      'from': _selfId,
      'to': _peerId
    });
  }

  Future<MediaStream?> createLocalStream(bool audio, bool datachannel) async {
    Map<String, dynamic> mediaConstraints = {
      'audio': _localAudio,
      'video': false
    };

    LogUtil.v("Signaling: Using media constraints: $mediaConstraints");
    final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    if (stream != null) {
      onLocalStream?.call(stream);
      return stream;
    }

    LogUtil.v("Signaling: Stream is null");
    return null;
  }

  Future<Session> _createSession(Session? session,
      {required String peerId,
      required String sessionId,
      required bool audio,
      required bool video,
      required bool dataChannel}) async {
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
    _sessions[sessionId] = newSession;

    if (_onlyDatachannel == false &&
        (_localAudio == true || _localVideo == true)) {
      _localStream = await createLocalStream(audio, dataChannel);
    }

    try {
      RTCPeerConnection pc = await createPeerConnection({
        ..._iceServers,
        ...{'tcpCandidatePolicy': 'disabled'},
        ...{'disableIpv6': true},
        ...{'sdpSemantics': sdpSemantics}
      }, _config);

      if (pc == null) {
        _sessions.remove(sessionId);
        throw Exception("Failed to create peer connection");
      }
      LogUtil.v("Signaling: Peer connection created successfully");

      if (_onlyDatachannel == false) {
        switch (sdpSemantics) {
          case 'plan-b':
            LogUtil.v("Signaling: Using Plan-B SDP semantics");
            pc.onAddStream = (MediaStream stream) {
              onAddRemoteStream?.call(newSession, stream);
              newSession._remoteStreams.add(stream);
            };

            if (_localStream != null) {
              LogUtil.v("Signaling: Adding local stream to peer (plan-b)");
              await pc.addStream(_localStream!);
            }
            break;
          case 'unified-plan':
            LogUtil.v("Signaling: Using Unified-Plan SDP semantics");
            pc.onTrack = (event) {
              onAddRemoteStream?.call(newSession, event.streams[0]);
              newSession._remoteStreams.add(event.streams[0]);
            };

            if (_localStream != null) {
              LogUtil.v("Signaling: Adding local tracks (unified-plan)");
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
        stream.getVideoTracks().forEach((videoTrack) {
          if (_remoteVideoTrack == null) {
            _remoteVideoTrack = videoTrack;
          }
        });
      };

      pc.onRemoveStream = (stream) {
        onRemoveRemoteStream?.call(newSession, stream);
        newSession._remoteStreams.removeWhere((it) {
          return (it.id == stream.id);
        });
        stream.getVideoTracks().forEach((videoTrack) {
          if (_remoteVideoTrack == videoTrack) {
            _remoteVideoTrack = null;
          }
        });
      };

      pc.onAddTrack = (stream, track) {
        if (track.kind == "video") {
          _remoteVideoTrack = track;
        }
      };

      pc.onRemoveTrack = (stream, track) {
        if (track.kind == "video") {
          if (_remoteVideoTrack == track) {
            _remoteVideoTrack = null;
          }
        }
      };

      pc.onDataChannel = (channel) {
        _addDataChannel(newSession, channel);
      };

      LogUtil.v("Signaling: Session created successfully");
      newSession.pc = pc;
      return newSession;
    } catch (e) {
      LogUtil.v("Signaling: Error setting up peer connection: $e");
      _sessions.remove(sessionId);
      throw Exception("Error setting up peer connection: $e");
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

      //   // Determine the direction settings for media streams
      final datachanneldir = _datachannel ? 'true' : 'false';
      final videodir = 'recvonly';
      final audiodir = _localAudio ? 'sendrecv' : 'recvonly';

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
      // LogUtil.v("Signaling: Created answer SDP: ${s.sdp}");
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

  // void _closeSessionByPeerId(String peerId) {
  //   var session;
  //   _sessions.removeWhere((String key, Session sess) {
  //     var ids = key.split('-');
  //     session = sess;
  //     return peerId == ids[0] || peerId == ids[1];
  //   });
  //   if (session != null) {
  //     _closeSession(session);
  //     onCallStateChange?.call(session, CallState.callStateBye);
  //   }
  // }

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

  /// Start video recording
  Future<void> startRecord(String sessionId) async {
    try {
      if (_isWeb()) {
        LogUtil.v("Signaling: Recording not supported on web platform");
        return;
      }

      var session = _sessions[sessionId];
      if (session == null) {
        LogUtil.v("Signaling: No session found: $sessionId");
        return;
      }

      if (session.recordState == RecordState.recording) {
        LogUtil.v("Signaling: Recording already in progress: $sessionId");
        return;
      }

      // For mobile platforms (iOS and Android)
      Directory? appDocDir;
      if (Platform.isIOS) {
        appDocDir = await getApplicationDocumentsDirectory();
      } else if (Platform.isAndroid) {
        appDocDir = await getExternalStorageDirectory();
      }

      if (appDocDir == null) {
        LogUtil.v("Signaling: Failed to get application directory");
        return;
      }

      String appDocPath = appDocDir.path;
      final filename = "Recording_${RandomString.randomNumeric(8)}.mp4";
      final filePath = "$appDocPath/$filename";
      LogUtil.v("Signaling: Recording started: $filePath");

      // Get all receivers and find video track
      List<RTCRtpReceiver> receivers = await session.pc!.getReceivers();
      bool recordingStarted = false;

      for (var receiver in receivers) {
        if (receiver.track?.kind == "video" &&
            _remoteVideoTrack != null &&
            _remoteVideoTrack!.id == receiver.track!.id) {
          if (recordingStarted) {
            break;
          }

          recordingStarted = true;
          await _mediaRecorder.start(
            filePath,
            videoTrack: receiver.track,
            audioChannel: RecorderAudioChannel.OUTPUT,
          );

          session.recordState = RecordState.recording;
          onRecordState?.call(session, RecordState.recording);
        }
      }

      if (!recordingStarted) {
        LogUtil.v("Signaling: No suitable video track found for recording");
      }
    } catch (e) {
      LogUtil.v("Signaling: Error starting recording: $e");
      if (e is Error) {
        LogUtil.v("Signaling: Error stack trace: ${e.stackTrace}");
      }
    }
  }

  /// Stop video recording and save to appropriate location
  Future<void> stopRecord(String sessionId) async {
    try {
      if (_isWeb()) {
        LogUtil.v("Signaling: Recording not supported on web platform");
        return;
      }

      var session = _sessions[sessionId];
      if (session == null) {
        LogUtil.v("Signaling: No session found: $sessionId");
        return;
      }

      if (session.recordState == RecordState.recording) {
        final filePath = await _mediaRecorder.stop();
        session.recordState = RecordState.recordClosed;
        onRecordState?.call(session, RecordState.recordClosed);

        LogUtil.v("Signaling: Recording stopped successfully");

        if (filePath != null) {
          final file = File(filePath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final filename =
                "Recording_${DateTime.now().millisecondsSinceEpoch}.mp4";

            // For mobile platforms (iOS and Android), save to photo library
            await ImageGallerySaver.saveFile(filePath, name: filename);

            // Clean up the temporary file
            await file.delete();
          }
        }
      }
    } catch (e) {
      LogUtil.v("Signaling: Error stopping recording: $e");
    }
  }

  /// Capture video frame and save to appropriate location based on platform
  Future<void> captureFrame(String sessionId) async {
    try {
      var session = _sessions[sessionId];
      if (session == null) {
        LogUtil.v("Signaling: No session found: $sessionId");
        return;
      }

      // Get all receivers and find video track
      List<RTCRtpReceiver> receivers = await session.pc!.getReceivers();
      for (var receiver in receivers) {
        if (receiver.track?.kind == "video" &&
            _remoteVideoTrack != null &&
            _remoteVideoTrack!.id == receiver.track!.id) {
          final buffer = await receiver.track!.captureFrame();

          if (buffer != null) {
            final byteData = ByteData.view(buffer);
            final bytes = byteData.buffer
                .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);

            final filename =
                "Capture_${DateTime.now().millisecondsSinceEpoch}.jpg";
            if (_isWeb()) {
              // For web, trigger browser download
              web_utils.downloadFile(bytes, filename);
            } else {
              // For mobile platforms (iOS and Android), save to photo library
              LogUtil.v("Signaling: mobile save image: $filename");
              await ImageGallerySaver.saveImage(
                bytes,
                quality: 100,
                name: filename,
              );
            }
            break;
          }
        }
      }
    } catch (e) {
      LogUtil.v("Signaling: Error capturing frame: $e");
    }
  }

  /// Send text via data channel
  Future<void> dataChannelSendTextMsg(String sessionId, String msg) async {
    var sess = _sessions[sessionId];
    if (sess != null) {
      if (sess.datachannelOpened == true) {
        await sess.dc?.send(RTCDataChannelMessage(msg));
      }
    }
  }

  /// Send raw data via data channel
  Future<void> dataChannelSendRawMsg(String sessionId, Uint8List data) async {
    var sess = _sessions[sessionId];
    if (sess != null) {
      if (sess.datachannelOpened == true) {
        await sess.dc?.send(RTCDataChannelMessage.fromBinary(data));
      }
    }
  }

  /// Get the remote stream for a given session
  MediaStream? getRemoteStream(String sessionId) {
    var sess = _sessions[sessionId];
    if (sess != null && sess._remoteStreams.isNotEmpty) {
      return sess._remoteStreams.first;
    }
    return null;
  }
}
