import 'dart:core';
import 'dart:async';
import 'dart:io';
import 'dart:io' show Platform;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'src/call_sample/event_bus_util.dart';
import 'src/call_sample/event_message.dart';
import 'src/call_sample/random_string.dart';
import 'src/utils/LogUtil.dart';
import 'src/utils/ProxyWebsocket.dart';

enum RecordState { Redording, RecordClosed }

final String WSS_SERVER_URL = "https://webrtc-stream.hanet.ai/wswebclient/";

class HanetWebRTCSingle extends StatefulWidget {
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
  final bool usedatachannel;

  const HanetWebRTCSingle({
    Key? key,
    required this.peerId,
    this.source = "SubStream",
    this.showVolume = true,
    this.showMic = true,
    this.showCapture = false,
    this.showRecord = false,
    this.showFullscreen = true,
    this.showControls = false,
    this.isDebug = false,
    this.isVertical = false,
    this.onOffline,
    this.onFullscreen,
    this.usedatachannel = false,
  }) : super(key: key);

  @override
  State<HanetWebRTCSingle> createState() => _HanetWebRTCSingleState();
}

class _HanetWebRTCSingleState extends State<HanetWebRTCSingle> with WidgetsBindingObserver {
  // WebRTC variable
  String? _selfId;
  String? _peerId;
  bool _usedatachannel = false;

  // UI controller variable
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isFullscreen = false;
  bool _isRecording = false;

  // widget util variable
  late String _appPath = "";
  var _sendMsgEvent;
  var _recvMsgEvent;
  var _delSessionMsgEvent;
  var _newSessionMsgEvent;
  var _sessions = <String, String>{};
  bool _run_first = true;

  // WebSocket variable
  String _serverUrl = "";
  ProxyWebsocket? _socket;
  final _encoder = JsonEncoder();
  final _decoder = JsonDecoder();

  // WebRTC variable
  bool _inited = false;
  bool _recording = false;
  bool _inCalling = false;
  bool _mic_mute = false;
  bool _speek_mute = false;
  bool _localaudio = true;
  bool _localvideo = false;
  bool _video = true;
  bool _audio = true;
  bool _datachannel = true;
  bool _can_add_candidate = false;

  int sendsequence = 0;
  final String _user = "admin";
  final String _password = "123456";
  final String _mode = "live";
  final String _source = "MainStream";
  final bool _onlydatachnannel = false;
  final String _sessionId = randomNumeric(32);
  final int _startTime = currentTimeMillis();

  MediaStream? _localStream;
  RTCPeerConnection? pc;
  RTCDataChannel? dc;
  MediaStreamTrack? _remotevideotrack;
  MediaStreamTrack? _remoteaudiotrack;
  RecordState redordstate = RecordState.RecordClosed;
  MediaRecorder _mediarecoder = MediaRecorder();
  List<RTCIceCandidate> remoteCandidates = [];

  String get sdpSemantics => WebRTC.platformIsWindows ? 'plan-b' : 'unified-plan';

  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:webrtc-stream.hanet.ai:3478'},
    ],
  };

  Map<String, dynamic> _iceServers_peer = {
    'iceServers': [
      {'url': 'stun:webrtc-stream.hanet.ai:3478'},
    ],
  };

  final Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
      {'googCpuOveruseDetection': false},
      {'googSuspendBelowMinBitrate': true},
    ],
  };

  // WebRTC DataChannel variable
  // bool _sendDataChannelMsg = false;
  Timer? myTimer;

  @override
  initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _peerId = widget.peerId;
    _usedatachannel = widget.usedatachannel;
    _selfId = randomNumeric(32);
    _serverUrl = WSS_SERVER_URL + _selfId!;

    LogUtil.init(isDebug: true);

    if (_inited == false) {
      _inited = true;
      _getAppDocPath();
      _initEventBus();
      _initRenderers();

      // first init WebSocket
      _webSocketConnect();
    }
  }

  /// ******************************************************
  /// WebSocket Connection Handler Start
  Future<void> _webSocketConnect() async {
    LogUtil.d('websocketconnect:: _serverUrl: $_serverUrl');
    _socket = ProxyWebsocket(_serverUrl);
    // onOpen
    _socket?.onOpen = () {
      LogUtil.d('websocketconnect::onOpen');
      connect();
    };

    // onClose
    _socket?.onClose = (int code, String reason) {
      LogUtil.d('websocketconnect::onClose');
      Timer(const Duration(seconds: 5), () {
        _webSocketConnect();
      });
    };

    // onMessage
    _socket?.onMessage = (message) {
      // LogUtil.d('websocketconnect::onMessage: $message');
      // Map<String, dynamic> mapData = _decoder.convert(message);
      // var eventName = mapData['eventName'];
      // var data = mapData['data'];
      // switch (eventName) {
      //   case '_ring':
      //     break;
      //   case '_call':
      //     eventBus.emit(ReciveMsgEvent(message));
      //     break;
      //   case '_offer':
      //     eventBus.emit(ReciveMsgEvent(message));
      //     break;
      //   default:
      eventBus.emit(ReciveMsgEvent(message));
      //     break;
      // }
    };

    await _socket?.connect();
  }

  _webSocketSend(eventName, data) {
    eventBus.emit(SendMsgEvent(eventName, data));
  }

  /// WebSocket Connection Handler End
  /// ******************************************************

  /// ******************************************************
  /// WebRTC Message Handler Start
  _initRenderers() async {
    await _remoteRenderer.initialize();
    _remoteRenderer.onFirstFrameRendered = () {
      LogUtil.d('-----------onFirstFrameRendered-----------');
      setState(() {
        _inCalling = true;
      });
    };
    _remoteRenderer.onResize = () {};
  }

  Future<void> connect() async {
    _webSocketSend('__connectto', {
      'sessionId': _sessionId,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
    });
  }

  void onMessage(message) async {
    // LogUtil.d('onMessage recv $message');
    Map<String, dynamic> mapData = _decoder.convert(message);
    var data = mapData['data'];
    var eventName = mapData['eventName'];
    switch (eventName) {
      case '_create':
        {
          //var peerId = data['from'];
          var sessionId = data['sessionId'];
          if (compare(sessionId, _sessionId) != 0) {
            break;
          }

          var iceServers = data['iceServers'];
          var domainNameiceServers = data['domainnameiceServers'];
          if (domainNameiceServers != null) {
            if (domainNameiceServers is String) {
              LogUtil.d('_create domainNameiceServers $domainNameiceServers');
              _iceServers = _decoder.convert(domainNameiceServers);
            } else {
              var subiceServers = domainNameiceServers['iceServers'];
              if (subiceServers == null) {
                _iceServers = subiceServers;
              } else {
                _iceServers = iceServers;
              }
            }

            if (iceServers is String) {
              _iceServers_peer = _decoder.convert(iceServers);
            } else {
              var subiceServers = iceServers['iceServers'];
              if (subiceServers == null) {
                _iceServers_peer = subiceServers;
              } else {
                _iceServers_peer = iceServers;
              }
            }
          } else {
            if (iceServers != null) {
              if (iceServers is String) {
                LogUtil.d('_create iceServers $iceServers');
                _iceServers = _decoder.convert(iceServers);
              } else {
                var subiceServers = iceServers['iceServers'];
                if (subiceServers == null) {
                  _iceServers = subiceServers;
                } else {
                  _iceServers = iceServers;
                }
              }
              _iceServers_peer = _iceServers;
            }
          }

          var state = data['state'];
          if (state != null) {
            if (compare(state, "online") == 0) {
              startcall();
            } else if (compare(state, "sleep") == 0) {
              startcall();
            } else {}
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
            LogUtil.d('_call iceServers ----------=$iceServers');
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

          if (datachannel != null) {
            if (compare(datachannel, "true") == 0) {
              // usedatachannel = true;
            }
          }

          if (audiodir != null) {
            if (compare(audiodir, "sendrecv") == 0) {
              useaudio = true;
              _localaudio = true;
            } else if (compare(audiodir, "sendonly") == 0) {
              useaudio = true;
              _localaudio = true;
            } else if (compare(audiodir, "recvonly") == 0) {
              useaudio = true;
              _localaudio = false;
            } else if (compare(audiodir, "true") == 0) {
              useaudio = true;
              _localaudio = true;
            }
          }

          if (videodir != null) {
            if (compare(videodir, "sendrecv") == 0) {
              usevideo = true;
              _localvideo = true;
            } else if (compare(videodir, "sendonly") == 0) {
              usevideo = true;
              _localvideo = true;
            } else if (compare(videodir, "recvonly") == 0) {
              usevideo = false;
              _localvideo = false;
            } else if (compare(videodir, "true") == 0) {
              usevideo = true;
              _localvideo = true;
            }
          }
        }
        break;
      case '_offer':
        {
          var delay = currentTimeMillis() - _startTime;
          LogUtil.d('<<<<<<<<<<<<<<<<<<<<<<<<<  recv offer use time  :$delay');

          var iceServers = data['iceservers'];
          if (iceServers != null && iceServers.toString().isNotEmpty) {
            _iceServers = _decoder.convert(iceServers);
          }

          var peerId = data['from'];
          var sdp = data['sdp'];
          LogUtil.d("_offer $sdp");
          var datachannel = data['datachannel'];
          var audiodir = data['audio'];
          var videodir = data['video'];
          var user = data['user'];
          var pwd = data['pwd'];
          var usedatachannel = true;
          var useaudio = true;
          var usevideo = false;

          if (datachannel != null) {
            if (compare(datachannel, "true") == 0) {
              usedatachannel = true;
            }
          }

          if (audiodir != null) {
            if (compare(audiodir, "sendrecv") == 0) {
              useaudio = true;
              _localaudio = true;
            } else if (compare(audiodir, "sendonly") == 0) {
              useaudio = true;
              _localaudio = false;
            } else if (compare(audiodir, "recvonly") == 0) {
              useaudio = true;
              _localaudio = true;
            } else if (compare(audiodir, "true") == 0) {
              useaudio = true;
              _localaudio = true;
            }
          }

          if (videodir != null) {
            if (compare(videodir, "sendrecv") == 0) {
              usevideo = true;
              _localvideo = true;
            } else if (compare(videodir, "sendonly") == 0) {
              usevideo = true;
              _localvideo = false;
            } else if (compare(videodir, "recvonly") == 0) {
              usevideo = true;
              _localvideo = false;
            } else if (compare(videodir, "true") == 0) {
              usevideo = true;
              _localvideo = true;
            }
          }

          var sessionId = data['sessionId'];
          await _createSession();

          if (usedatachannel == true) {
            _createDataChannel();
          }

          await pc?.setRemoteDescription(RTCSessionDescription(sdp, "offer"));
          await _createAnswer();
          if (remoteCandidates.isNotEmpty) {
            remoteCandidates.forEach((candidate) async {
              await pc?.addCandidate(candidate);
            });
            remoteCandidates.clear();
          }
          if (remoteCandidates.isNotEmpty) {
            remoteCandidates.forEach((candidate) async {
              var candi = candidate.candidate;
              LogUtil.d('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  recv offer addCandidate --- $candi');
              await pc?.addCandidate(candidate);
            });
            remoteCandidates.clear();
          }
        }
        break;
      case '_answer':
        {
          var type = data['type'];
          var sdp = data['sdp'];
          LogUtil.d("_answer $sdp");
          var sessionId = data['sessionId'];
          if (compare(sessionId, _sessionId) == 0) {
            pc?.setRemoteDescription(RTCSessionDescription(sdp, type));
            _can_add_candidate = true;
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
            LogUtil.d('recv candidate-<<<-----------sdpMLineIndex :$nsdpMLineIndex sdpMid: $ssdpMid candidate: $scandidate');
            RTCIceCandidate candidate = RTCIceCandidate(scandidate, ssdpMid, nsdpMLineIndex);

            if (_can_add_candidate == true) {
              LogUtil.d('addCandidate-----------candidate: $scandidate');
              await pc?.addCandidate(candidate);
            } else {
              LogUtil.d('addCandidate-----------add tmp: $scandidate');
              remoteCandidates.add(candidate);
            }
          }
        }
        break;
      case '_disconnected':
        {
          var sessionId = data['sessionId'];
          if (compare(sessionId, _sessionId) == 0) {
            LogUtil.d('_disconnected: $sessionId');
            _stopRecord();
            _closeSession();
          }
        }
        break;
      case '_session_failed':
        {
          var sessionId = data['sessionId'];
          if (compare(sessionId, _sessionId) == 0) {
            LogUtil.d('_session_failed: $sessionId');
            _stopRecord();
            _closeSession();
          }
        }
        break;
      case '_post_message':
        {
          var sessionId = data['sessionId'];
          if (compare(sessionId, _sessionId) == 0) {}
        }
        break;
      case '_connectinfo':
        LogUtil.d('onMessage recv $message');
        break;
      case '_ping':
        {
          LogUtil.d('keepalive response!');
        }
        break;
      default:
        break;
    }
  }

  void startcall() {
    var delay = currentTimeMillis() - _startTime;
    LogUtil.d('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  send call use time  :$delay');

    var datachanneldir = 'true';
    var audiodir = 'sendrecv';
    var videodir = 'sendrecv';
    if (_video == true && _localvideo == false) {
      videodir = 'recvonly';
    } else if (_video == true && _localvideo == true) {
      videodir = 'sendrecv';
    } else {
      videodir = 'false';
    }

    if (_datachannel == true) {
      datachanneldir = 'true';
    } else {
      datachanneldir = 'false';
    }

    if (_audio == true && _localaudio == true) {
      audiodir = 'sendrecv';
    } else if (_audio == true && _localaudio == false) {
      audiodir = 'recvonly';
    } else {
      audiodir = 'false';
    }

    _webSocketSend('__call', {
      'sessionId': _sessionId,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
      'mode': _mode,
      'source': _source,
      'datachannel': datachanneldir,
      'audio': audiodir,
      'video': videodir,
      'user': _user,
      "pwd": _password,
      'iceservers': _encoder.convert(_iceServers_peer),
    });
  }

  _hangUp() {
    bye();
    myTimer!.cancel();
    _stopRecord();
    _closeSession();
  }

  void bye() {
    _webSocketSend('__disconnected', {
      "sessionId": _sessionId,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
    });
  }

  Future<void> _closeSession() async {
    pc?.StopAudioMode();
    if (!_speek_mute) {
      pc?.StopSpeek();
    }

    if (!_mic_mute) {
      pc?.StopMicrophone();
    }

    _localStream?.getTracks().forEach((element) async {
      await element.stop();
    });

    await _localStream?.dispose();
    _localStream = null;
    await dc?.close();
    await pc?.close();
    await pc?.dispose();
    if (widget.onOffline != null) {
      widget.onOffline!();
    }
  }

  Future<void> _createSession() async {
    if (_onlydatachnannel == false && (_localaudio == true || _localvideo == true)) {
      _localStream = await createLocalStream(_localaudio, _localvideo, _usedatachannel);
    }

    pc = await createPeerConnection({
      ..._iceServers,
      ...{'tcpCandidatePolicy': 'disabled'},
      ...{'continualGatheringPolicy': 'gather_continually'},
      ...{'disableIpv6': false},
      ...{'sdpSemantics': sdpSemantics},
    }, _config);

    if (_onlydatachnannel == false) {
      switch (sdpSemantics) {
        case 'plan-b':
          if (_localStream != null) {
            await pc?.addStream(_localStream!);
          }
          break;
        case 'unified-plan':
          if (_localStream != null) {
            _localStream!.getTracks().forEach((track) {
              pc?.addTrack(track, _localStream!);
            });
          }
          break;
      }
      bool? micmuteVar = await pc?.getMicrophoneMute();
      bool? speekmuteVar = await pc?.getSpeakerMute();
      bool micmute = micmuteVar ?? false;
      bool speekmute = speekmuteVar ?? false;
      setState(() {
        _mic_mute = micmute;
        _speek_mute = speekmute;
      });
      LogUtil.d('------------ _mute = $_mic_mute');
    }

    pc?.onIceCandidate = (candidate) async {
      var szcandidate = candidate.candidate;
      var sdpMLineIndex = candidate.sdpMLineIndex;
      var sdpMid = candidate.sdpMid;
      LogUtil.d('send candidate -------------->> sdpMLineIndex: $sdpMLineIndex sdpMid: $sdpMid candidate: $szcandidate');

      // This delay is needed to allow enough time to try an ICE candidate
      // before skipping to the next one. 1 second is just an heuristic value
      // and should be thoroughly tested in your own environment.
      await Future.delayed(
        const Duration(milliseconds: 10),
        () => _webSocketSend('__ice_candidate', {
          'sessionId': _sessionId,
          'sessionType': "flutter",
          'messageId': randomNumeric(32),
          'from': _selfId,
          'to': _peerId,
          "candidate": _encoder.convert({
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }),
        }),
      );
    };

    pc?.onSignalingState = (state) {
      LogUtil.d('onSignalingState: $state');
    };

    pc?.onConnectionState = (state) {
      LogUtil.d('onConnectionState: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _stopRecord();
        _closeSession();
      } else {}
    };

    pc?.onIceGatheringState = (state) {
      LogUtil.d('onIceGatheringState: $state');
    };

    pc?.onIceConnectionState = (state) {
      LogUtil.d('onIceConnectionState: $state');
    };

    pc?.onAddStream = (stream) {
      stream.getVideoTracks().forEach((videoTrack) {
        _remotevideotrack = videoTrack;
      });
      stream.getAudioTracks().forEach((aduioTrack) {
        _remoteaudiotrack = aduioTrack;
      });

      _remoteRenderer.srcObject = stream;
    };

    pc?.onRemoveStream = (stream) {
      stream.getVideoTracks().forEach((videoTrack) {
        if (_remotevideotrack == videoTrack) {
          _remotevideotrack = null;
        }
      });

      stream.getAudioTracks().forEach((audioTrack) {
        if (_remotevideotrack == audioTrack) {
          _remoteaudiotrack = null;
        }
      });

      if (_remoteRenderer.srcObject == stream) {
        _remoteRenderer.srcObject = null;
      }
    };

    pc?.onAddTrack = (stream, track) {
      if (track.kind == "video") {
        _remotevideotrack = track;
      }

      if (track.kind == "audio") {
        _remoteaudiotrack = track;
      }

      _remoteRenderer.srcObject = stream;
    };

    pc?.onRemoveTrack = (stream, track) {
      if (track.kind == "video") {
        if (_remotevideotrack == track) {
          _remotevideotrack = null;
        }
      }

      if (track.kind == "audio") {
        if (_remoteaudiotrack == track) {
          _remoteaudiotrack = null;
        }
      }

      if (_remoteRenderer.srcObject == stream) {
        _remoteRenderer.srcObject = null;
      }
    };

    pc?.onDataChannel = (channel) {
      LogUtil.d('onDataChannel: $channel');
      _addDataChannel(channel);
    };
  }

  Future<MediaStream> createLocalStream(bool audio, bool video, bool datachennel) async {
    LogUtil.d('createLocalStream: audio = $audio  video= $video datachennel = $datachennel');

    Map<String, dynamic> mediaConstraints = {};
    if (audio == false && video == false && datachennel == true) {
      mediaConstraints = {'audio': false, 'video': false};
    } else if (audio == true && video == true && (_localaudio == true || _localvideo == true) && datachennel == true) {
      mediaConstraints = {
        'audio': _localaudio,
        'video': _localvideo
            ? {
                'mandatory': {
                  'minWidth': '1280', // Provide your own width, height and frame rate here
                  'minHeight': '720',
                  'minFrameRate': '30',
                },
                'facingMode': 'user',
                'optional': [],
              }
            : false,
      };
    } else if (audio == true && video == true && (_localaudio == true || _localvideo == true) && datachennel == false) {
      mediaConstraints = {'audio': _localaudio, 'video': _localvideo};
    } else if (audio == true && video == false && (_localaudio == true || _localvideo == true) && datachennel == true) {
      mediaConstraints = {
        'audio': _localaudio,
        'video': _localvideo
            ? {
                'mandatory': {
                  'minWidth': '1280', // Provide your own width, height and frame rate here
                  'minHeight': '720',
                  'minFrameRate': '30',
                },
                'facingMode': 'user',
                'optional': [],
              }
            : false,
      };
    } else {
      mediaConstraints = {'audio': _localaudio, 'video': _localvideo};
    }

    MediaStream stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    return stream;
  }

  Future<void> _createAnswer() async {
    try {
      Map<String, dynamic> dcConstraints = {};

      RTCSessionDescription s = await pc!.createAnswer(_onlydatachnannel ? {} : dcConstraints);
      await pc!.setLocalDescription(s);
      _can_add_candidate = true;

      var delay = currentTimeMillis() - _startTime;
      LogUtil.d('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> send answer  use time  :$delay');
      LogUtil.d("_createAnswer ${s.sdp}");
      _webSocketSend('__answer', {
        "type": s.type,
        "sdp": s.sdp,
        'sessionId': _sessionId,
        'sessionType': "flutter",
        'messageId': randomNumeric(32),
        'from': _selfId,
        'to': _peerId,
      });
    } catch (e) {
      LogUtil.d(e.toString());
    }
  }

  void _addDataChannel(RTCDataChannel channel) {
    channel.onDataChannelState = (e) {
      if (e == RTCDataChannelState.RTCDataChannelOpen) {
        LogUtil.d("datachennel :open");
        LogUtil.d(channel.label);
        LogUtil.d(channel.id);
        dc = channel;
        // _send_datachennel_msg_ex();
      } else if (e == RTCDataChannelState.RTCDataChannelClosing) {
      } else if (e == RTCDataChannelState.RTCDataChannelClosed) {
      } else if (e == RTCDataChannelState.RTCDataChannelConnecting) {}
    };

    channel.onMessage = (RTCDataChannelMessage data) {
      LogUtil.d("datachennel :onMessage");
      LogUtil.d(channel.label);
      LogUtil.d(channel.id);
      onDataChannelMessage(data);
    };
  }

  Future<void> _createDataChannel() async {
    RTCDataChannelInit dataChannelDict = RTCDataChannelInit()..maxRetransmits = 30;
    RTCDataChannel channel = await pc!.createDataChannel("datachannel", dataChannelDict);

    LogUtil.d('_createDataChannel: ');
    _addDataChannel(channel);
  }

  onDataChannelMessage(RTCDataChannelMessage data) async {
    if (data.isBinary) {
    } else {
      onDataChannelTxtMessage(data.text);
    }
  }

  onDataChannelTxtMessage(message) async {
    DateTime now = DateTime.now();
    var dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    LogUtil.d('${dateFormat.format(now)} ondatachennel Message recv len =${message.length}');
  }

  /// WebRTC Message Handler End
  /// ******************************************************

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closeSession();
    _socket?.close();
    eventBus.off(_sendMsgEvent);
    eventBus.off(_delSessionMsgEvent);
    eventBus.off(_newSessionMsgEvent);
    eventBus.off(_recvMsgEvent);
    super.dispose();
  }

  /// ******************************************************
  /// Widget util function Start
  _send(event, data) {
    var request = <String, dynamic>{"eventName": event, "data": data};
    _socket?.send(_encoder.convert(request));
  }

  Future<void> _getAppDocPath() async {
    var appDocDir;
    if (Platform.isIOS) {
      appDocDir = await getApplicationDocumentsDirectory();
    } else if (Platform.isAndroid) {
      appDocDir = await getExternalStorageDirectory();
    } else {
      return;
    }
    setState(() {
      _appPath = appDocDir!.path;
    });
  }

  Future<void> _initEventBus() async {
    LogUtil.d("initEventBus");
    LogUtil.d("******************************************************");

    _recvMsgEvent = eventBus.on<ReciveMsgEvent>((event) {
      LogUtil.d('_recvMsgEvent: ${event.msg}');
      onMessage(event.msg);
    });

    _sendMsgEvent = eventBus.on<SendMsgEvent>((event) {
      LogUtil.d('_sendMsgEvent: ${event.event} - ${event.data}');
      _send(event.event, event.data);
    });

    _delSessionMsgEvent = eventBus.on<DeleteSessionMsgEvent>((event) {
      var session = _sessions.remove(event.msg);
      if (session != null) {
        LogUtil.d('remove session $session');
      }
    });

    _newSessionMsgEvent = eventBus.on<NewSessionMsgEvent>((event) {
      _sessions[event.msg] = event.msg;
    });
  }

  int compare(String str1, String str2) {
    var res = Comparable.compare(str1, str2);
    return res;
  }

  Future<void> _startRecord() async {
    LogUtil.d('_startRecord ------------------------');
    if (redordstate == RecordState.RecordClosed) {
      try {
        LogUtil.d('startRecord appDocPath : $_appPath');
        var peerconnectid = pc!.getPeerConnectionId();

        DateTime now = DateTime.now();
        String strtime = now.toString().replaceAll(" ", "").replaceAll(".", "").replaceAll("-", "").replaceAll(":", "");
        String recordFilepath = "$_appPath" + "/" + strtime + ".mp4";

        List<RTCRtpReceiver> receivers = await pc!.getReceivers();
        bool startrecorded = false;
        receivers.forEach((receive) {
          LogUtil.d('startRecord track ------------------------: ${receive.track}');
          if (receive.track!.kind == "video") {
            if (_remotevideotrack != null) {
              if (_remotevideotrack!.id == receive.track!.id) {
                if (startrecorded == false) {
                  startrecorded = true;
                  if (kIsWeb != true) {
                    RecorderAudioChannel audiochannel = RecorderAudioChannel.OUTPUT;
                    _mediarecoder.start(
                      2,
                      recordFilepath,
                      peerconnectid,
                      videoTrack: receive.track,
                      audioTrack: _remoteaudiotrack,
                      audioChannel: audiochannel,
                    );
                    redordstate = RecordState.Redording;
                    setState(() {
                      _recording = true;
                    });
                  }
                }
              }
            }
          }
        });
      } catch (err) {
        LogUtil.d(err);
      }
    } else {
      LogUtil.d('startRecord  is recording');
    }
  }

  Future<void> _stopRecord() async {
    LogUtil.d('stopRecord  -------------------------------------------');

    if (redordstate == RecordState.Redording) {
      LogUtil.d('stopRecord...');
      await _mediarecoder.stop();
      redordstate = RecordState.RecordClosed;
      setState(() {
        _recording = false;
      });
      LogUtil.d('stopRecord  end');
    }
  }

  Future<void> muteSpeekSession() async {
    if (_inCalling == true) {
      bool enable = await pc!.getSpeakerMute();
      setState(() {
        _speek_mute = !enable;
      });
      LogUtil.d('muteSpeekSession  ----------: $_speek_mute');

      if (_speek_mute) {
        pc?.StopSpeek();
      } else {
        pc?.StartSpeek();
      }
    }
  }

  Future<void> muteLocalStreamSession() async {
    if (_inCalling == true) {
      bool enable = await pc!.getMicrophoneMute();
      setState(() {
        _mic_mute = !enable;
      });
      if (_mic_mute == true) {
        pc!.StopMicrophone();
      } else {
        pc!.StartMicrophone();
      }
    }
  }

  Future<void> captureFrame() async {
    try {
      String captureFilepath = "$_appPath" + "/" + _sessionId + randomNumeric(32) + ".jpg";

      List<RTCRtpReceiver> receivers = await pc!.getReceivers();

      for (int i = 0; i < receivers.length; i++) {
        RTCRtpReceiver receive = receivers[i];
        if (receive.track!.kind!.isNotEmpty) {
          if (receive.track!.kind!.compareTo("video") == 0) {
            if (_remotevideotrack != null) {
              if (_remotevideotrack!.id == receive.track!.id) {
                LogUtil.d('captureFrame track : ${receive.track!.kind}');
                await receive.track!.captureFrame(captureFilepath);
              }
            }
          }
        }
      }
    } catch (err) {
      LogUtil.d(err);
    }
  }

  /// Widget util function End
  /// ******************************************************

  /// ******************************************************
  /// Handler UI Controller Start
  // reset orientation
  Future<void> _resetOrientation() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  // toggle fullscreen
  Future<void> _toggleFullscreen() async {
    final goingFull = !_isFullscreen;
    setState(() => _isFullscreen = goingFull);

    if (_isFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      widget.onFullscreen?.call(true);
    } else {
      await _resetOrientation();
      widget.onFullscreen?.call(false);
    }
  }

  // toggle volume
  _switchVolume() {
    if (_inCalling == true) {
      muteSpeekSession();
    }
  }

  // toggle mic
  _muteMic() {
    if (_inCalling == true) {
      muteLocalStreamSession();
    }
  }

  // capture frame
  Future<void> _captureFrame() async {
    if (!widget.showCapture) return;
  }

  _handlCapture() {
    // captureFrame();
  }

  _handleRecord() {
    if (_inCalling) {
      if (_recording == false) {
        _startRecord();
      } else {
        _stopRecord();
      }
    }
  }

  /// Handler UI Controller End
  /// ******************************************************

  Widget _buildVideoView() {
    return Container(
      color: Colors.black, // Always black background
      margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
      width: MediaQuery.of(context).size.width,
      height: MediaQuery.of(context).size.height,
      child: Stack(children: [RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)]),
    );
  }

  Widget _buildControls() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(0.2)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (widget.showVolume)
            IconButton(
              icon: Icon(_speek_mute ? Icons.volume_off : Icons.volume_up, color: Colors.white),
              onPressed: _switchVolume,
            ),
          if (widget.showMic)
            IconButton(
              icon: Icon(_mic_mute ? Icons.mic_off : Icons.mic, color: Colors.white),
              onPressed: _muteMic,
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
              onPressed: _handleRecord,
            ),
          if (widget.showFullscreen)
            IconButton(
              icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
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
              ? Positioned.fill(child: _buildVideoView())
              : Center(
                  child: AspectRatio(aspectRatio: widget.isVertical ? 9 / 16 : 16 / 9, child: _buildVideoView()),
                ),
          if (widget.showControls)
            _isFullscreen
                ? Positioned(left: 0, right: 0, bottom: 0, child: _buildControls())
                : Positioned(left: 0, right: 0, bottom: 0, child: _buildControls()),
        ],
      ),
    );
  }

  @override
  deactivate() {
    super.deactivate();
    eventBus.off(_recvMsgEvent);
    _remoteRenderer.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      LogUtil.d('App is in background');
      if (!_speek_mute) {
        pc?.StopSpeek();
      }
      pc?.StopAudioMode();
      LogUtil.d('App is in background end');
      // pc?.setSpeakerMute(true);
    } else if (state == AppLifecycleState.resumed) {
      // 应用从后台返回前台
      // pc?.setSpeakerMute(!_speek);
      LogUtil.d('App is in foreground');
      if (_run_first) {
        _run_first = false;
      } else {
        pc?.StartAudioMode();
        if (!_speek_mute) {
          pc?.StartSpeek();
        }
        getAudioButtonState();
      }

      LogUtil.d('App is in foreground end');
    }
  }

  void getAudioButtonState() async {
    if (_inCalling == true) {
      bool mice = await pc!.getMicrophoneMute();
      bool speek = await pc!.getSpeakerMute();
      setState(() {
        _mic_mute = mice;
        _speek_mute = speek;
      });
    }
  }
}
