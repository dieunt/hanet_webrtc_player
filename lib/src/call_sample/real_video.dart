// ignore_for_file: avoid_print, prefer_typing_uninitialized_variables
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'dart:core';
import 'dart:async';
import 'dart:io';
import 'event_bus_util.dart';
import 'event_message.dart';
import 'random_string.dart';
import '../utils/LogUtil.dart';
import 'dart:io' show Platform;

enum RecordState { Redording, RecordClosed }

class RealVideo extends StatefulWidget {
  static String tag = 'call_sample';
  final String peerId;
  final String selfId;
  final bool usedatachannel;

  RealVideo({
    required this.selfId,
    required this.peerId,
    required this.usedatachannel,
  });

  @override
  _RealVideoState createState() => _RealVideoState();
}

class _RealVideoState extends State<RealVideo> with WidgetsBindingObserver {
  String? _selfId;
  String? _peerId;
  bool _dataChannelOpened = false;
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  String _SessionId = randomNumeric(32);
  bool _onlydatachnannel = false;
  MediaStream? _localStream;
  String _User = "admin";
  String _Password = "123456";
  String _Mode = "live";
  String _Source = "MainStream";

  bool _localaudio = true;
  bool _localvideo = false;
  int sendsequence = 0;
  bool _video = true;
  bool _audio = true;
  bool _datachannel = true;

  bool _showremotevideo = false;
  bool _usedatachannel = false;
  bool _inCalling = false;
  bool _mic_mute = false;
  bool _speek_mute = false;
  Timer? myTimer;
  bool _inited = false;
  bool _can_add_candidate = false;
  bool _run_first = true;

  bool _recording = false;
  bool _senddatachannelmsg = false;
  JsonEncoder _encoder = JsonEncoder();
  JsonDecoder _decoder = JsonDecoder();

  RTCPeerConnection? pc;
  RTCDataChannel? dc;
  MediaStreamTrack? _remotevideotrack;
  MediaStreamTrack? _remoteaudiotrack;
  RecordState redordstate = RecordState.RecordClosed;
  MediaRecorder _mediarecoder = MediaRecorder();
  List<RTCIceCandidate> remoteCandidates = [];

  int _start_time_ = currentTimeMillis();
  var _recvMsgEvent;
  String get sdpSemantics =>
      WebRTC.platformIsWindows ? 'plan-b' : 'unified-plan';
      
  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:webrtc.qq-kan.com:3478'},
    ],
  };

  Map<String, dynamic> _iceServers_peer = {
    'iceServers': [
      {'url': 'stun:webrtc.qq-kan.com:3478'},
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

  final Map<String, dynamic> _dcConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
      'iceRestart': true,
    },
    'optional': [],
  };

  // ignore: unused_element
  _RealVideoState();

  @override
  initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_inited == false) {
      _inited = true;
      _selfId = widget.selfId;
      _peerId = widget.peerId;
      _usedatachannel = widget.usedatachannel;
      _recvMsgEvent = eventBus.on<ReciveMsgEvent>((event) {
        onMessage(event.msg);
      });

      initRenderers();
      _initWebrtc();
      connect();
      myTimer = Timer.periodic(const Duration(seconds: 5), onTimer);
    }
  }

  void onTimer(Timer t) {
    if (_senddatachannelmsg) {
      _send_datachennel_msg_ex();
    }
  }

  bool _isWeb() {
    return kIsWeb == true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      // 应用退到后台
      print('App is in background');
      if (!_speek_mute) {
        pc?.StopSpeek();
      }
      pc?.StopAudioMode();
      print('App is in background end');
      // pc?.setSpeakerMute(true);
    } else if (state == AppLifecycleState.resumed) {
      // 应用从后台返回前台
      // pc?.setSpeakerMute(!_speek);
      print('App is in foreground');
      if (_run_first) {
        _run_first = false;
      } else {
        pc?.StartAudioMode();
        if (!_speek_mute) {
          pc?.StartSpeek();
        }
        getAudioButtonState();
      }

      print('App is in foreground end');
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

  void onMessage(message) async {
    print('onMessage recv $message');
    Map<String, dynamic> mapData = _decoder.convert(message);
    var data = mapData['data'];
    var eventName = mapData['eventName'];
    switch (eventName) {
      case '_create':
        {
          var sessionId = data['sessionId'];
          //var peerId = data['from'];
          if (compare(sessionId, _SessionId) == 0) {
            var iceServers = data['iceServers'];
            var domainnameiceServers = data['domainnameiceServers'];
            if (domainnameiceServers != null) {
              if (domainnameiceServers is String) {
                print('onMessage domainnameiceServers $domainnameiceServers');
                _iceServers = _decoder.convert(domainnameiceServers);
              } else {
                var subiceServers = domainnameiceServers['iceServers'];
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
                  print('onMessage iceServers $iceServers');
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
            } else {
              // print('_create sessionId = $sessionId   _SessionId = $_SessionId');
            }
          } else {
            //print('_create sessionId ----------=$sessionId   _SessionId =$_SessionId');
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
            print('_call iceServers ----------=$iceServers');
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

          if (videodir == null) {
          } else {
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
          var delay = currentTimeMillis() - _start_time_;
          print(
            '<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  recv offer use time  :$delay',
          );
          var iceServers = data['iceservers'];
          //  print('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  recv offer iceServers  :$iceServers');
          if (iceServers != null && iceServers.toString().isNotEmpty) {
            _iceServers = _decoder.convert(iceServers);
          }
          var peerId = data['from'];
          var sdp = data['sdp'];
          LogUtil.v("_offer $sdp");
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
          if (videodir == null) {
          } else {
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
              print(
                '<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  recv offer addCandidate --- $candi',
              );
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
          LogUtil.v("_answer $sdp");
          var sessionId = data['sessionId'];
          if (compare(sessionId, _SessionId) == 0) {
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
          if (compare(sessionId, _SessionId) == 0) {
            print(
              'recv candidate-<<<-----------sdpMLineIndex :$nsdpMLineIndex sdpMid: $ssdpMid candidate: $scandidate',
            );
            RTCIceCandidate candidate = RTCIceCandidate(
              scandidate,
              ssdpMid,
              nsdpMLineIndex,
            );

            if (_can_add_candidate == true) {
              print('addCandidate-----------candidate: $scandidate');
              await pc?.addCandidate(candidate);
            } else {
              print('addCandidate-----------add tmp: $scandidate');
              remoteCandidates.add(candidate);
            }
          }
        }
        break;
      case '_disconnected':
        {
          var sessionId = data['sessionId'];
          if (compare(sessionId, _SessionId) == 0) {
            print('_disconnected: ' + sessionId);
            _stopRecord();
            _closeSession();
          }
        }
        break;
      case '_session_failed':
        {
          var sessionId = data['sessionId'];
          if (compare(sessionId, _SessionId) == 0) {
            print('_session_failed: ' + sessionId);
            _stopRecord();
            _closeSession();
          }
        }
        break;
      case '_post_message':
        {
          var sessionId = data['sessionId'];
          if (compare(sessionId, _SessionId) == 0) {}
        }
        break;
      case '_connectinfo':
        print('onMessage recv $message');
        break;
      case '_ping':
        {
          print('keepalive response!');
        }
        break;
      default:
        break;
    }
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
    print(
      '${dateFormat.format(now)} ondatachennel Message recv len =${message.length}',
    );
    //print('ondatachennel Message recv $message');
  }

  /*
    注：初始化显示控件
  */
  initRenderers() async {
    await _remoteRenderer.initialize();
    _remoteRenderer.onFirstFrameRendered = () {
      print(
        '------------------------------video frame onFirstFrameRendered------------------------------',
      );
      setState(() {
        _showremotevideo = true;
        _inCalling = true;
      });
    };
    _remoteRenderer.onResize = () {};
  }

  @override
  deactivate() {
    super.deactivate();
    eventBus.off(_recvMsgEvent);
    _remoteRenderer.dispose();
  }

  /*
  函数 ：初始化
  注 ：生成一个 Signaling 类，并实现相应回调函数

*/
  void _initWebrtc() async {}
  websocket_send(eventName, data) {
    eventBus.emit(SendMsgEvent(eventName, data));
  }

  void startcall() {
    var delay = currentTimeMillis() - _start_time_;
    print(
      '<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  send call use time  :$delay',
    );
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

    websocket_send('__call', {
      "sessionId": _SessionId,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
      "mode": _Mode,
      "source": _Source,
      "datachannel": datachanneldir,
      "audio": audiodir,
      "video": videodir,
      "user": _User,
      "pwd": _Password,
      "iceservers": _encoder.convert(_iceServers_peer),
    });
  }

  // ignore: non_constant_identifier_names
  _send_live_ptz_msg(int x, int y, int timedelay) {
    _send_datachennel_msg('ptz_set', {
      "sessionId": _SessionId,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
      'message': {
        "request": [
          {
            "ptz_control": {
              "directionx": x,
              "directiony": y,
              "timedelay": timedelay,
            },
          },
        ],
      },
    });
  }

  _send_datachennel_msg(event, data) {
    if (_dataChannelOpened) {
      print("datachennel :_send_datachennel_msg");
      var request = Map();
      request["eventName"] = event;
      request["data"] = data;
      dc?.send(RTCDataChannelMessage(_encoder.convert(request)));
    }
  }

  _send_datachennel_msg_ex() {
    if (_dataChannelOpened) {
      // var request = {"title":"config_get"};
      final now = DateTime.now();
      final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
      final formattedTime = formatter.format(now);
      sendsequence++;
      var request = {
        "title": "config_get",
        "sequence": sendsequence,
        "time": formattedTime,
        "channel": -1,
        "payload": {
          "data":
              "fdsafdsafdsafdsafdsdsafdsafdsafdsafdafdsafdsafdafdafdsafdfdsafdsafdfdsfafdsafdafdafdafdfdafd",
        },
      };
      dc?.send(RTCDataChannelMessage(_encoder.convert(request)));
      print('${formattedTime} send datachannel  Message');
      //dc?.send(RTCDataChannelMessage(
      //    "fdsafdsafdsafkdjsakfjdskafdsfjdsfjdsfjdsfjdshjafhdsjafhdsjafhdjsahgfsgfdsgfdsgfdsgfdsgfsgfgfsgfdsgfsdgfdsgfdsgfdsgfdsgfsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfsdgfdfdsafdsafgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfgfdgsfdsgfgfdsgfdsgfdsgfdsgfdsgfdsgfgfgsgfdsgfdsgfsdgfdsgfdsgfdsgfdsgfsdgfdsgdafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdrrrrrrrrrrrfdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdff" +
      //        "fdsafdsafdsafkdjsakfjdskafdsfjdsfjdsfjdsfjdshjafhdsjafhdsjafhdjsahgfsgfdsgfdsgfdsgfdsgfsgfgfsgfdsgfsdgfdsgfdsgfdsgfdsgfsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfsdgfdfdsafdsafgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfdsgfgfdgsfdsgfgfdsgfdsgfdsgfdsgfdsgfdsgfgfgsgfdsgfdsgfsdgfdsgfdsgfdsgfdsgfsdgfdsgdafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdrrrrrrrrrrrfdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdsafdff"));
    }
  }

  /*
    函数 ： 挂起通话
    注： 发送一个__disconnect 消息 并返回上一页面
*/
  _hangUp() {
    bye();
    myTimer!.cancel();
    _stopRecord();
    _closeSession();
    Navigator.pop(context, true);
  }

  _datachannelSentTextMsg() {
    _send_datachennel_msg_ex();
  }

  _handlerecord() {
    if (_inCalling) {
      if (_recording == false) {
        _startRecord();
      } else {
        _stopRecord();
      }
    }
  }

  _handlcapture() {
    // captureFrame();
  }

  /*
    函数： 关闭所有声音
*/
  _switchVolume() {
    if (_inCalling == true) {
      muteSpeekSession();
    }
  }

  /*
    函数： 静音
*/
  _muteMic() {
    if (_inCalling == true) {
      muteLocalStreamSession();
    }
  }

  Future<void> muteSpeekSession() async {
    if (_inCalling == true) {
      bool enable = await pc!.getSpeakerMute();
      setState(() {
        _speek_mute = !enable;
      });
      print('muteSpeekSession  ----------: $_speek_mute');
      //
      //*******************************************
      // if have setup audioDeviceModule.setSpeakerEnable(false);
      //*******************************************

      if (_speek_mute) {
        pc?.StopSpeek();
      } else {
        pc?.StartSpeek();
      }

      /*
      List<RTCRtpReceiver> receivers = await pc!.getReceivers();
      for (var i = 0; i < receivers.length; i++) {
        RTCRtpReceiver receive = receivers[i];
        if (receive.track!.kind == "audio") {
          setState(() {
            _speek_mute = !_speek_mute;
          });
          receive.track!.enabled = _speek_mute;
          print(
              'muteSpeekSession track  ------------------------: ${receive.track}');
        }
      }
      */
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

  /*
  函数： 通过信令通道发送消息
  注：
  */
  _postmessage(String message) async {
    websocket_send('__post_message', {
      "sessionId": _SessionId,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
      "message": message,
    });
  }

  Future<void> connect() async {
    websocket_send('__connectto', {
      'sessionId': _SessionId,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
    });
  }

  void bye() {
    websocket_send('__disconnected', {
      "sessionId": _SessionId,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': _peerId,
    });
  }

  int compare(String str1, String str2) {
    var res = Comparable.compare(str1, str2);
    return res;
  }

  /*
    发送 使用 datachennel 发送 文本数据
  */
  Future<void> dataChannelSendTextMsg(String msg) async {
    if (_dataChannelOpened == true) {
      await dc?.send(RTCDataChannelMessage(msg));
    }
  }

  /*
    发送 使用 datachennel 发送 原始
  */
  Future<void> dataChannelSendRawMsg(Uint8List data) async {
    if (_dataChannelOpened == true) {
      await dc?.send(RTCDataChannelMessage.fromBinary(data));
    }
  }

  Future<MediaStream> createLocalStream(
    bool audio,
    bool video,
    bool datachennel,
  ) async {
    print(
      'createLocalStream: audio = $audio  video= $video datachennel = $datachennel',
    );
    Map<String, dynamic> mediaConstraints = {};
    if (audio == false && video == false && datachennel == true) {
      mediaConstraints = {'audio': false, 'video': false};
    } else if (audio == true &&
        video == true &&
        (_localaudio == true || _localvideo == true) &&
        datachennel == true) {
      mediaConstraints = {
        'audio': _localaudio,
        'video': _localvideo
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
            : false,
      };
    } else if (audio == true &&
        video == true &&
        (_localaudio == true || _localvideo == true) &&
        datachennel == false) {
      mediaConstraints = {'audio': _localaudio, 'video': _localvideo};
    } else if (audio == true &&
        video == false &&
        (_localaudio == true || _localvideo == true) &&
        datachennel == true) {
      mediaConstraints = {
        'audio': _localaudio,
        'video': _localvideo
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
            : false,
      };
    } else {
      mediaConstraints = {'audio': _localaudio, 'video': _localvideo};
    }

    MediaStream stream = await navigator.mediaDevices.getUserMedia(
      mediaConstraints,
    );

    return stream;
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
  }

  Future<void> _createSession() async {
    if (_onlydatachnannel == false &&
        (_localaudio == true || _localvideo == true)) {
      _localStream = await createLocalStream(
        _localaudio,
        _localvideo,
        _usedatachannel,
      );
    }

    //print(_iceServers);
    //  ...{'tcpCandidatePolicy':'disabled'},
    //  ...{'disableIpv6':true},
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
          // Unified-Plan
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
      print('------------ _mute = $_mic_mute');

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

    pc?.onIceCandidate = (candidate) async {
      if (candidate == null) {
        print('onIceCandidate: complete!');
        return;
      }
      var szcandidate = candidate.candidate;
      var sdpMLineIndex = candidate.sdpMLineIndex;
      var sdpMid = candidate.sdpMid;
      print(
        'send candidate -------------->> sdpMLineIndex: $sdpMLineIndex sdpMid: $sdpMid candidate: $szcandidate',
      );

      // This delay is needed to allow enough time to try an ICE candidate
      // before skipping to the next one. 1 second is just an heuristic value
      // and should be thoroughly tested in your own environment.
      await Future.delayed(
        const Duration(milliseconds: 10),
        () => websocket_send('__ice_candidate', {
          'sessionId': _SessionId,
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
      print('onSignalingState: $state');
    };
    pc?.onConnectionState = (state) {
      print('onConnectionState: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _stopRecord();
        _closeSession();
      } else {}
    };
    pc?.onIceGatheringState = (state) {
      print('onIceGatheringState: $state');
    };
    pc?.onIceConnectionState = (state) {
      print('onIceConnectionState: $state');
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
      print('onDataChannel: $channel');
      _addDataChannel(channel);
    };
  }

  void _addDataChannel(RTCDataChannel channel) {
    channel.onDataChannelState = (e) {
      if (e == RTCDataChannelState.RTCDataChannelOpen) {
        print("datachennel :open");
        print(channel.label);
        print(channel.id);
        _dataChannelOpened = true;
        dc = channel;
        _send_datachennel_msg_ex();
      } else if (e == RTCDataChannelState.RTCDataChannelClosing) {
      } else if (e == RTCDataChannelState.RTCDataChannelClosed) {
      } else if (e == RTCDataChannelState.RTCDataChannelConnecting) {}
    };
    channel.onMessage = (RTCDataChannelMessage data) {
      //print("datachennel :onMessage");
      //print(channel.label);
      //print(channel.id);
      onDataChannelMessage(data);
    };
  }

  Future<void> _createDataChannel() async {
    RTCDataChannelInit dataChannelDict = RTCDataChannelInit()
      ..maxRetransmits = 30;
    RTCDataChannel channel = await pc!.createDataChannel(
      "datachannel",
      dataChannelDict,
    );

    print('_createDataChannel: ');

    _addDataChannel(channel);
  }

  Future<void> _createOffer(String mode, String source) async {
    try {
      Map<String, dynamic> dcConstraints = {
        'mandatory': {
          'OfferToReceiveAudio': _audio,
          'OfferToReceiveVideo': _video,
          'iceRestart': true,
        },
        'optional': [],
      };

      RTCSessionDescription s = await pc!.createOffer(
        _onlydatachnannel ? {} : dcConstraints,
      );
      await pc!.setLocalDescription(s);
      LogUtil.v("_createOffer ${s.sdp}");

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
      websocket_send('__offer', {
        'sessionId': _SessionId,
        'sessionType': "flutter",
        'messageId': randomNumeric(32),
        'from': _selfId,
        'to': _peerId,
        "type": s.type,
        "sdp": s.sdp,
        "mode": mode,
        "source": source,
        "datachannel": datachanneldir,
        "audio": audiodir,
        "video": videodir,
        "user": _User,
        "pwd": _Password,
        "iceservers": _encoder.convert(_iceServers),
      });
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> _createAnswer() async {
    try {
      Map<String, dynamic> dcConstraints = {};

      RTCSessionDescription s = await pc!.createAnswer(
        _onlydatachnannel ? {} : dcConstraints,
      );
      await pc!.setLocalDescription(s);
      _can_add_candidate = true;
      var delay = currentTimeMillis() - _start_time_;
      print(
        '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> send answer  use time  :$delay',
      );
      LogUtil.v("_createAnswer ${s.sdp}");
      websocket_send('__answer', {
        "type": s.type,
        "sdp": s.sdp,
        'sessionId': _SessionId,
        'sessionType': "flutter",
        'messageId': randomNumeric(32),
        'from': _selfId,
        'to': _peerId,
      });
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> captureFrame() async {
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
      String captureFilepath =
          "$appDocPath" + "/" + _SessionId + randomNumeric(32) + ".jpg";

      List<RTCRtpReceiver> receivers = await pc!.getReceivers();

      for (int i = 0; i < receivers.length; i++) {
        RTCRtpReceiver receive = receivers[i];
        if (receive.track!.kind!.isNotEmpty) {
          if (receive.track!.kind!.compareTo("video") == 0) {
            if (_remotevideotrack != null) {
              if (_remotevideotrack!.id == receive.track!.id) {
                print('captureFrame track : ${receive.track!.kind}');
                await receive.track!.captureFrame(captureFilepath);
              }
            }
          }
        }
      }
    } catch (err) {
      print(err);
    }
  }

  /*
    开始录像
  */
  Future<void> _startRecord() async {
    print('_startRecord ------------------------');
    if (redordstate == RecordState.RecordClosed) {
      try {
        var peerconnectid = pc!.getPeerConnectionId();
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

        DateTime now = DateTime.now();
        String strtime = now
            .toString()
            .replaceAll(" ", "")
            .replaceAll(".", "")
            .replaceAll("-", "")
            .replaceAll(":", "");
        String recordFilepath = "$appDocPath" + "/" + strtime + ".mp4";

        List<RTCRtpReceiver> receivers = await pc!.getReceivers();
        bool startrecorded = false;
        receivers.forEach((receive) {
          print('startRecord track ------------------------: ${receive.track}');
          if (receive.track!.kind == "video") {
            if (_remotevideotrack != null) {
              if (_remotevideotrack!.id == receive.track!.id) {
                if (startrecorded == false) {
                  startrecorded = true;
                  if (_isWeb()) {
                  } else {
                    RecorderAudioChannel audiochannel =
                        RecorderAudioChannel.OUTPUT;
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
        print(err);
      }
    } else {
      print('startRecord  is recording');
    }
  }

  /*
    停止录像
  */
  Future<void> _stopRecord() async {
    print('stopRecord  -------------------------------------------');

    if (redordstate == RecordState.Redording) {
      print('stopRecord  ');
      await _mediarecoder.stop();
      redordstate = RecordState.RecordClosed;
      setState(() {
        _recording = false;
      });
      print('stopRecord  end');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'P2P Call Sample' +
                (_selfId != null ? ' [Your ID ($_selfId)] ' : ''),
          ),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: null,
              tooltip: 'setup',
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: SizedBox(
          width: 300.0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              FloatingActionButton(
                child: const Icon(Icons.video_camera_back),
                onPressed: _handlerecord,
                heroTag: 'record',
                backgroundColor: _inCalling
                    ? _recording
                          ? Colors.pink
                          : Colors.blue
                    : Colors.grey,
              ),
              FloatingActionButton(
                child: _speek_mute
                    ? const Icon(Icons.volume_off)
                    : const Icon(Icons.volume_up),
                onPressed: _switchVolume,
                heroTag: 'switch_volume',
              ),
              FloatingActionButton(
                onPressed: _hangUp,
                tooltip: 'Hangup',
                heroTag: 'Hangup',
                child: const Icon(Icons.call_end),
                backgroundColor: Colors.pink,
              ),
              FloatingActionButton(
                child: _mic_mute
                    ? const Icon(Icons.mic_off)
                    : const Icon(Icons.mic),
                onPressed: _muteMic,
                heroTag: 'muteMic',
              ),
              FloatingActionButton(
                child: const Icon(Icons.photo_camera),
                onPressed: _handlcapture,
                heroTag: 'capture',
                backgroundColor: _inCalling ? Colors.blue : Colors.grey,
              ),
            ],
          ),
        ),
        body: OrientationBuilder(
          builder: (context, orientation) {
            return Container(
              child: Stack(
                children: <Widget>[
                  Positioned(
                    left: 0.0,
                    right: 0.0,
                    top: 0.0,
                    height: 200.0,
                    child: _showremotevideo
                        ? Container(
                            margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                            width: MediaQuery.of(context).size.width,
                            height: MediaQuery.of(context).size.height,
                            child: RTCVideoView(_remoteRenderer),
                            decoration: BoxDecoration(color: Colors.black),
                          )
                        : Container(
                            decoration: new BoxDecoration(color: Colors.black),
                            height: 300.0,
                            width: double.infinity,
                            child: Center(
                              child: new CircularProgressIndicator(
                                backgroundColor: Color(0xffff0000),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      onWillPop: () {
        //监听到退出按键
        _hangUp();
        return Future<bool>.value(true);
      },
    );
  }
}
