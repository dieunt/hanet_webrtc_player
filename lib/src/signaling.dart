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
      'sessionType': "flutter",
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

  void onMessage(message) async {
    Map<String, dynamic> mapData = _decoder.convert(message);
    var data = mapData['data'];
    var eventName = mapData['eventName'];
    switch (eventName) {
      case '_create':
        {
          var sessionId = data['sessionId'];
          var peerId = data['from'];
          if (compare(sessionId, _sessionId) == 0) {
            var iceServers = data['iceServers'];
            if (iceServers != null) {
              if (iceServers is String) {
                // LogUtil.v("Signaling: iceServers $iceServers");
                _iceServers = _decoder.convert(iceServers);
              } else {
                var subiceServers = iceServers['iceServers'];
                if (subiceServers == null) {
                  _iceServers = subiceServers;
                } else {
                  _iceServers = iceServers;
                }
              }
            }
            var state = data['state'];
            if (state != null) {
              if (compare(state, "online") == 0) {
                LogUtil.v("Signaling: Session state: online");
                onSessionCreate?.call(sessionId, peerId, OnlineState.online);
              } else if (compare(state, "sleep") == 0) {
                LogUtil.v("Signaling: Session state: sleep");
                onSessionCreate?.call(sessionId, peerId, OnlineState.sleep);
              } else {
                LogUtil.v("Signaling: Session state: offline");
                onSessionCreate?.call(sessionId, peerId, OnlineState.offline);
              }
            } else {
              LogUtil.v("Signaling: Session state: error");
              onSessionCreate?.call(sessionId, peerId, OnlineState.error);
            }
          } else {
            LogUtil.v("Signaling: Session state: error");
            onSessionCreate?.call(sessionId, peerId, OnlineState.error);
          }
        }
        break;
      case '_call':
        {
          var sessionId = data['sessionId'];
          if (sessionId == null) {
            return;
          }
          var peerId = data['from'];
          if (peerId == null) {
            return;
          }
          var iceServers = data['iceservers'];
          if (iceServers != null) {
            // print('_call iceServers ----------=$iceServers');
            _iceServers = _decoder.convert(iceServers);
          }
          var datachannel = data['datachannel'];
          var audiodir = data['audio'];
          var videodir = data['video'];
          var user = data['user'];
          var pwd = data['pwd'];
          var usedatachannel = false;
          var useaudio = false;
          var usevideo = false;
          if (datachannel == null) {
          } else {
            if (compare(datachannel, "true") == 0) {
              usedatachannel = true;
            }
          }
          if (audiodir == null) {
          } else {
            if (compare(audiodir, "sendrecv") == 0) {
              useaudio = true;
              _localAudio = true;
            } else if (compare(audiodir, "sendonly") == 0) {
              useaudio = true;
              _localAudio = true;
            } else if (compare(audiodir, "recvonly") == 0) {
              useaudio = true;
              _localAudio = false;
            } else if (compare(audiodir, "true") == 0) {
              useaudio = true;
              _localAudio = true;
            }
          }

          if (videodir == null) {
          } else {
            if (compare(videodir, "sendrecv") == 0) {
              usevideo = true;
              _localVideo = true;
            } else if (compare(videodir, "sendonly") == 0) {
              usevideo = true;
              _localVideo = true;
            } else if (compare(videodir, "recvonly") == 0) {
              usevideo = false;
              _localVideo = false;
            } else if (compare(videodir, "true") == 0) {
              usevideo = true;
              _localVideo = true;
            }
          }
          invite(sessionId, peerId, useaudio, usevideo, _localAudio,
              _localVideo, usedatachannel, _mode, _source, _user, _password);
        }
        break;
      case '_offer':
        {
          var delay = RandomString.currentTimeMillis() - _startTime;
          // LogUtil.v("Signaling: Received offer after delay: $delay");
          var iceServers = data['iceservers'];
          if (iceServers != null && iceServers.toString().isNotEmpty) {
            _iceServers = _decoder.convert(iceServers);
          }
          var peerId = data['from'];
          var sdp = data['sdp'];
          // LogUtil.v("Signaling: Received offer SDP: $sdp");
          var datachannel = data['datachannel'];
          var audiodir = data['audio'];
          var videodir = data['video'];
          var user = data['user'];
          var pwd = data['pwd'];
          var usedatachannel = true;
          var useaudio = true;
          var usevideo = false;
          if (datachannel == null) {
          } else {
            if (compare(datachannel, "true") == 0) {
              usedatachannel = true;
            }
          }
          if (audiodir == null) {
          } else {
            if (compare(audiodir, "sendrecv") == 0) {
              useaudio = true;
              _localAudio = true;
            } else if (compare(audiodir, "sendonly") == 0) {
              useaudio = true;
              _localAudio = false;
            } else if (compare(audiodir, "recvonly") == 0) {
              useaudio = true;
              _localAudio = true;
            } else if (compare(audiodir, "true") == 0) {
              useaudio = true;
              _localAudio = true;
            }
          }
          if (videodir == null) {
          } else {
            if (compare(videodir, "sendrecv") == 0) {
              usevideo = true;
              _localVideo = true;
            } else if (compare(videodir, "sendonly") == 0) {
              usevideo = true;
              _localVideo = false;
            } else if (compare(videodir, "recvonly") == 0) {
              usevideo = true;
              _localVideo = true;
            } else if (compare(videodir, "true") == 0) {
              usevideo = true;
              _localVideo = true;
            }
          }
          var sessionId = data['sessionId'];
          var session = _sessions[sessionId];
          var newSession = await _createSession(session,
              peerId: peerId,
              sessionId: sessionId,
              audio: useaudio,
              video: usevideo,
              dataChannel: usedatachannel);
          _sessions[sessionId] = newSession;
          if (newSession != null && usedatachannel == true) {
            _createDataChannel(newSession);
          }

          await newSession.pc
              ?.setRemoteDescription(RTCSessionDescription(sdp, "offer"));
          await _createAnswer(newSession);
          if (newSession.remoteCandidates.isNotEmpty) {
            newSession.remoteCandidates.forEach((candidate) async {
              await newSession.pc?.addCandidate(candidate);
            });
            newSession.remoteCandidates.clear();
          }
          if (remoteCandidates.isNotEmpty) {
            remoteCandidates.forEach((candidate) async {
              var candi = candidate.candidate;
              await newSession.pc?.addCandidate(candidate);
            });
            remoteCandidates.clear();
          }

          onCallStateChange?.call(newSession, CallState.callStateNew);
        }
        break;
      case '_answer':
        {
          var type = data['type'];
          var sdp = data['sdp'];
          // LogUtil.v("Signaling: Received answer SDP: $sdp");
          var sessionId = data['sessionId'];
          if (compare(sessionId, _sessionId) == 0) {
            var session = _sessions[sessionId];
            session?.pc?.setRemoteDescription(RTCSessionDescription(sdp, type));
          }
        }
        break;
      case '_ice_candidate':
        {
          var peerId = data['from'];
          var candidateMap = data['candidate'];
          var candidateobject = _decoder.convert(candidateMap);
          var scandidate = candidateobject['candidate'];
          var nsdpMLineIndex = candidateobject['sdpMLineIndex'];
          var ssdpMid = candidateobject['sdpMid'];
          var sessionId = data['sessionId'];
          if (compare(sessionId, _sessionId) == 0) {
            // print(
            //     'recv candidate-<<<-----------sdpMLineIndex :$nsdpMLineIndex sdpMid: $ssdpMid candidate: $scandidate');
            var session = _sessions[sessionId];
            RTCIceCandidate candidate =
                RTCIceCandidate(scandidate, ssdpMid, nsdpMLineIndex);

            if (session != null) {
              if (session.pc != null) {
                // print('addCandidate-----------candidate: $scandidate');
                await session.pc?.addCandidate(candidate);
              } else {
                // print('addCandidate-----------add tmp: $scandidate');
                session.remoteCandidates.add(candidate);
              }
            } else {
              remoteCandidates.add(candidate);

              // print(
              //     'addCandidate--------sessionId--$sessionId -add candidate------------: $scandidate');
              //_sessions[sessionId] = Session(pid: peerId, sid: sessionId)..remoteCandidates.add(candidate);
            }
          }
        }
        break;
      case '_disconnected':
        {
          var sessionId = data['sessionId'];
          if (compare(sessionId, _sessionId) == 0) {
            LogUtil.v("Signaling: Session disconnected: $sessionId");
            var session = _sessions.remove(sessionId);
            if (session != null) {
              onCallStateChange?.call(session, CallState.callStateBye);
              _closeSession(session);
            }
          }
        }
        break;
      case '_session_failed':
        {
          var sessionId = data['sessionId'];
          if (compare(sessionId, _sessionId) == 0) {
            LogUtil.v("Signaling: Session failed: $sessionId");
            var session = _sessions.remove(sessionId);
            if (session != null) {
              onCallStateChange?.call(session, CallState.callStateBye);
              _closeSession(session);
            }
          }
        }
        break;
      case '_post_message':
        {
          var sessionId = data['sessionId'];
          if (compare(sessionId, _sessionId) == 0) {
            var session = _sessions[sessionId];
            var message = data['message'];
            LogUtil.v("Signaling: Received post message: $message");
            if (session != null) {
              onRecvSignalingMessage?.call(session, message);
            }
          }
        }
        break;
      case '_connectinfo':
        LogUtil.v("Signaling: Received connect info");
        break;
      case '_ping':
        {
          LogUtil.v("Signaling: Received keepalive response");
        }
        break;
      default:
        LogUtil.v("Signaling: Received unknown message type: $eventName");
        break;
    }
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

  Future<MediaStream> createLocalStream(
      bool audio, bool video, bool datachennel) async {
    // print(
    //     'createLocalStream: audio = $audio  video= $video datachennel = $datachennel');
    Map<String, dynamic> mediaConstraints = {};
    if (audio == false && video == false && datachennel == true) {
      mediaConstraints = {'audio': false, 'video': false};
    } else if (audio == true &&
        video == true &&
        (_localAudio == true || _localVideo == true) &&
        datachennel == true) {
      mediaConstraints = {
        'audio': _localAudio,
        'video': _localVideo
            ? {
                'mandatory': {
                  'minWidth':
                      '1280', // Provide your own width, height and frame rate here
                  'minHeight': '720',
                  'minFrameRate': '30',
                },
                'facingMode': 'user',
                'optional': [],
              }
            : false
      };
    } else if (audio == true &&
        video == true &&
        (_localAudio == true || _localVideo == true) &&
        datachennel == false) {
      mediaConstraints = {'audio': _localAudio, 'video': _localVideo};
    } else if (audio == true &&
        video == false &&
        (_localAudio == true || _localVideo == true) &&
        datachennel == true) {
      mediaConstraints = {
        'audio': _localAudio,
        'video': _localVideo
            ? {
                'mandatory': {
                  'minWidth':
                      '1280', // Provide your own width, height and frame rate here
                  'minHeight': '720',
                  'minFrameRate': '30',
                },
                'facingMode': 'user',
                'optional': [],
              }
            : false
      };
    } else {
      mediaConstraints = {'audio': _localAudio, 'video': _localVideo};
    }

    MediaStream stream =
        await navigator.mediaDevices.getUserMedia(mediaConstraints);
    if (stream != null) {
      onLocalStream?.call(stream);
    }

    return stream;
  }

  Future<Session> _createSession(Session? session,
      {required String peerId,
      required String sessionId,
      required bool audio,
      required bool video,
      required bool dataChannel}) async {
    var newSession = session ?? Session(sid: sessionId, pid: peerId);
    newSession.audio = audio;
    newSession.video = video;
    newSession.datachannel = dataChannel;
    newSession.recordState = RecordState.recordClosed;
    if (_onlyDatachannel == false &&
        (_localAudio == true || _localVideo == true)) {
      _localStream = await createLocalStream(audio, video, dataChannel);
    }
    //print(_iceServers);
    //  ...{'tcpCandidatePolicy':'disabled'},
    //  ...{'disableIpv6':true},
    RTCPeerConnection pc = await createPeerConnection({
      ..._iceServers,
      ...{'tcpCandidatePolicy': 'disabled'},
      ...{'disableIpv6': true},
      ...{'sdpSemantics': sdpSemantics}
    }, _config);
    if (_onlyDatachannel == false) {
      switch (sdpSemantics) {
        case 'plan-b':
          pc.onAddStream = (MediaStream stream) {
            onAddRemoteStream?.call(newSession, stream);
            // print('_add remote streams ');
            newSession._remoteStreams.add(stream);
          };
          if (_localStream != null) {
            await pc.addStream(_localStream!);
          }

          break;
        case 'unified-plan':
          // Unified-Plan
          pc.onTrack = (event) {
            onAddRemoteStream?.call(newSession, event.streams[0]);
            newSession._remoteStreams.add(event.streams[0]);
          };
          if (_localStream != null) {
            _localStream!.getTracks().forEach((track) {
              pc.addTrack(track, _localStream!);
            });
          }
          break;
      }

      // Unified-Plan: Simuclast
      /*
      await pc.addTransceiver(
        track: _localStream.getAudioTracks()[0],
        init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendOnly, streams: [_localStream]),
      );

      await pc.addTransceiver(
        track: _localStream.getVideoTracks()[0],
        init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendOnly,
            streams: [
              _localStream
            ],
            sendEncodings: [
              RTCRtpEncoding(rid: 'f', active: true),
              RTCRtpEncoding(
                rid: 'h',
                active: true,
                scaleResolutionDownBy: 2.0,
                maxBitrate: 150000,
              ),
              RTCRtpEncoding(
                rid: 'q',
                active: true,
                scaleResolutionDownBy: 4.0,
                maxBitrate: 100000,
              ),
            ]),
      );*/
      /*
        var sender = pc.getSenders().find(s => s.track.kind == "video");
        var parameters = sender.getParameters();
        if(!parameters)
          parameters = {};
        parameters.encodings = [
          { rid: "h", active: true, maxBitrate: 900000 },
          { rid: "m", active: true, maxBitrate: 300000, scaleResolutionDownBy: 2 },
          { rid: "l", active: true, maxBitrate: 100000, scaleResolutionDownBy: 4 }
        ];
        sender.setParameters(parameters);
      */
    } else {}

    pc.onIceCandidate = (candidate) async {
      if (candidate == null) {
        // print('onIceCandidate: complete!');
        return;
      }
      var szcandidate = candidate.candidate;
      var sdpMLineIndex = candidate.sdpMLineIndex;
      var sdpMid = candidate.sdpMid;
      // print(
      //     'send candidate -------------->> sdpMLineIndex: $sdpMLineIndex sdpMid: $sdpMid candidate: $szcandidate');

      // This delay is needed to allow enough time to try an ICE candidate
      // before skipping to the next one. 1 second is just an heuristic value
      // and should be thoroughly tested in your own environment.
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
      print('onSignalingState: $state');
    };
    pc.onConnectionState = (state) {
      print('onConnectionState: $state');
      onSessionRTCConnectState?.call(newSession, state);
    };
    pc.onIceGatheringState = (state) {
      print('onIceGatheringState: $state');
    };
    pc.onIceConnectionState = (state) {
      print('onIceConnectionState: $state');
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
    newSession.pc = pc;
    return newSession;
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
