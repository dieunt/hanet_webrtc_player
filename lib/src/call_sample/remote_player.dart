// ignore_for_file: prefer_typing_uninitialized_variables

import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:core';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'signaling.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'event_bus_util.dart';
import 'event_message.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'random_string.dart';
import 'dart:io' show Platform;
class DataChannelRemotePlayer extends StatefulWidget {
  static String tag = 'RemotePlayer';
  final String peerId;
  final String selfId;
  final String apppath;
  final String filename;
  DataChannelRemotePlayer(
      {required this.apppath,
      required this.filename,
      required this.selfId,
      required this.peerId});

  @override
  _DataChannelRemotePlayerState createState() =>
      _DataChannelRemotePlayerState();
}

class _DataChannelRemotePlayerState extends State<DataChannelRemotePlayer> {
  Signaling? _signaling;
  List<dynamic> _peers = [];
  String? _selfId;
  String? _peerId;
  String? _apppath;
  String? _filename;
  late IOSink _save_file;
  bool _createsavefile = false;
  bool _inCalling = false;
  bool _dataChannelOpened = false;
  RTCDataChannel? _dataChannel;
  Session? _session;
  Timer? _timer;
  var _text = '';
  bool _closeed = false;
  bool _working = false;
  bool _started = false;
  bool _autodownload = true;
  bool _downloaded = false;
  bool _initplayered = false;
  double _value = 0;
  int _filesize = 0;
  int _recvsize = 0;
  int _preindex = 0;
  int _totlesize = 0;
  int _totle_recvsize = 0;
  VideoPlayerController? _videoPlayerController;
  late String _save_file_path;

  var _recvMsgEvent;
  JsonEncoder _encoder = JsonEncoder();
  JsonDecoder _decoder = JsonDecoder();
  // ignore: unused_element
  _DataChannelRemotePlayerState();

  @override
  initState() {
    super.initState();

    _recvMsgEvent = eventBus.on<ReciveMsgEvent>((event) {
      // print('CallSample recive ReciveMsgEvent --> ${event.msg}');
      if (_signaling != null) {
        _signaling?.onMessage(event.msg);
      }
    });

    _selfId = widget.selfId;
    _peerId = widget.peerId;
    _apppath = widget.apppath;
    _filename = widget.filename;
    _connect();
  }

  @override
  deactivate() {
    super.deactivate();
    eventBus.off(_recvMsgEvent);
    _signaling?.close();
    _timer?.cancel();
  }

  void _connect() async {
    _signaling ??= Signaling(widget.selfId, widget.peerId, true, false);
    _signaling?.onSendSignalMessge = (String eventName, dynamic data) {
      //print('onSendSignalMessge --> $eventName');
      eventBus.emit(SendMsgEvent(eventName, data));
    };
    _signaling?.onSessionCreate =
        (String sessionId, String peerId, OnlineState state) {
      //print('onSessionCreateMessge sessionId = $sessionId   peerId = $peerId   $state');
      if (state == OnlineState.OnLine) {
        _invitePeer(sessionId, peerId);
      }
      _signaling?.onDataChannelMessage =
          (Session session, dc, RTCDataChannelMessage data) {
        if (data.isBinary && !_closeed) {
          setState(() {
            _recvsize = data.binary.length;
            _totle_recvsize += _recvsize;
          });
          var databuf = data.binary;
          if (_createsavefile && _save_file != null) {
            _save_file..add(databuf);
          }
        } else {
          onDataChannelTxtMessage(data.text);
        }
      };

      _signaling?.onDataChannel = (Session session, channel) {
        _dataChannel = channel;
      };

      _signaling?.onSignalingStateChange = (SignalingState state) {
        switch (state) {
          case SignalingState.ConnectionClosed:
          case SignalingState.ConnectionError:
          case SignalingState.ConnectionOpen:
            break;
        }
      };

      _signaling?.onCallStateChange = (Session session, CallState state) {
        switch (state) {
          case CallState.CallStateNew:
            {
              if (!_closeed) {
                setState(() {
                  eventBus.emit(NewSessionMsgEvent(session.sid));
                  _session = session;
                });
              }
              _timer =
                  Timer.periodic(Duration(seconds: 1), _handleDataChannelTest);
              break;
            }
          case CallState.CallStateBye:
            {
              if (!_closeed) {
                setState(() {
                  _inCalling = false;
                  _dataChannel = null;
                  _session = null;
                  _text = '';
                });
              }
              eventBus.emit(DeleteSessionMsgEvent(session.sid));

              _hangUp();
              break;
            }
          case CallState.CallStateInvite:
          case CallState.CallStateConnected:
          case CallState.CallStateRinging:
        }
      };
      _signaling?.onDataChannelState =
          (Session session, RTCDataChannelState state) async {
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          if (!_closeed) {
            setState(() {
              _dataChannelOpened = true;
            });
          }
          _save_file = await _getSaveFile();
          if (_save_file != null) {
            _createsavefile = true;
            _send_download_open_msg(session, _filename!);
          }
        } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
          if (!_closeed) {
            setState(() {
              _dataChannelOpened = false;
            });
          }
        }
      };
    };
    _signaling?.connect();
  }

  void onDataChannelTxtMessage(message) async {
    print('ondatachennel Message recv $message');
    Map<String, dynamic> mapData = _decoder.convert(message);
    var data = mapData['data'];
    var eventName = mapData['eventName'];
    if (eventName == "_download") {
      var datamsg = data['message'];
      if (datamsg != null) {
        var datresponse = datamsg['response'];
        //
        List<dynamic> list = datresponse;
        list.forEach((element) {
          Map<String, dynamic> content = element;
          content.forEach((key, value) {
            if (key == "getfilelist") {
              Map<String, dynamic> getfilelists = value;
              getfilelists.forEach((key_getfile, value_getfile) {
                if (key_getfile == "code") {
                } else if (key_getfile == "state") {
                } else if (key_getfile == "filelists") {
                  List<dynamic> filelists = value_getfile;
                  filelists.forEach((item) {
                    Map<String, dynamic> fileitem = item;
                  });
                }
              });
            } else if (key == "open") {
              Map<String, dynamic> openvalue = value;
              openvalue.forEach((key_open, value_open) {
                // print("k=$key_open,v=$value_open");
                if (key_open == "filesize") {
                  setState(() {
                    _filesize = value_open;
                    _totlesize = value_open;
                    _value = 0;
                    if (!_autodownload) {
                      _started = true;
                    }
                  });
                }
              });
              if (_autodownload) {
                startWorking();
              }
            } else if (key == "start") {
              setState(() {
                _started = false;
                _working = true;
              });
            } else if (key == "pause") {
            } else if (key == "stop") {
              print("k=$key,v=$value");
              setState(() {
                _started = false;
                _working = false;
                _value = _totle_recvsize / _totlesize;
              });

              if (_createsavefile) {
                _save_file.close();
                _createsavefile = false;
              }
            } else if (key == "currentstate") {
              Map<String, dynamic> currentstatevalue = value;
              currentstatevalue.forEach((key_currentstate, value_currentstate) {
                // print("k=$key_currentstate,v=$value_currentstate");
                if (key_currentstate == "position") {
                  Map<String, dynamic> positionvalue = value_currentstate;
                  positionvalue.forEach((key_position, value_position) {
                    if (key_position == "filesize") {
                      _totlesize = value_position;
                    }
                    if (key_position == "cursize") {
                      // var cursize = value_position;
                    }
                  });
                  setState(() {
                    _value = _totle_recvsize / _totlesize;
                  });
                }
              });
            }
          });
        });
      }
    }
  }

  _handleDataChannelTest(Timer timer) async {
    if (_dataChannelOpened) {
      if (_initplayered == false) {
        if (_totle_recvsize > 3 * 1024) {
          bool fileisreddy = await _checkFileSize();
          if (fileisreddy) {
            _createRemotePlayer();
          }
        }
      }
    }
  }

  _invitePeer(String sessionId, String peerId) async {
    if (peerId != _selfId) {
      _signaling?.invite(sessionId, peerId, false, false, false, false, true,
          "download", "MainStream", "admin", "123456");
    }
  }

  _hangUp() {
    _closeed = true;
    _timer?.cancel();
    if (_createsavefile) {
      _save_file.close();
      _createsavefile = false;
    }
    if (_session != null) {
      _signaling?.bye(_session!.sid);
    }
    Navigator.pop(context, true);
  }

  // ignore: non_constant_identifier_names
  _send_download_open_msg(Session session, String file) {
    _send_datachannel_txt_msg('__download', {
      "sessionId": session.sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': session.pid,
      'message': {
        "request": [
          {"open": file}
        ]
      }
    });
  }

  // ignore: non_constant_identifier_names
  _send_download_start_msg(Session session) {
    _send_datachannel_txt_msg('__download', {
      "sessionId": session.sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': session.pid,
      'message': {
        "request": [
          {"start": 0}
        ]
      }
    });
  }

  // ignore: non_constant_identifier_names
  _send_download_pause_msg(Session session, bool pause) {
    _send_datachannel_txt_msg('__download', {
      "sessionId": session.sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': session.pid,
      'message': {
        "request": [
          {"pause": pause}
        ]
      }
    });
  }

  // ignore: non_constant_identifier_names
  _send_download_stop_msg(Session session) {
    _send_datachannel_txt_msg('__download', {
      "sessionId": session.sid,
      'sessionType': "flutter",
      'messageId': randomNumeric(32),
      'from': _selfId,
      'to': session.pid,
      'message': {
        "request": [
          {"stop": "cancel"}
        ]
      }
    });
  }

  _send_datachannel_txt_msg(event, data) {
    if (_dataChannelOpened) {
      var request = Map();
      request["eventName"] = event;
      request["data"] = data;
      _dataChannel?.send(RTCDataChannelMessage(_encoder.convert(request)));
    }
  }


  startWorking() async {
    if (!_closeed) {
      setState(() {
        _value = 0;
      });
    }
    /*
    var request = Map();
    request["cmd"] = "start";
    _send_txt_msg('__download', {
      "sessionId": _session!.sid,
      'sessionType': "flutter",
      'from': _selfId,
      'to': _session!.pid,
      "message": _encoder.convert(request)
    });
    */
    if (_session != null) {
      _send_download_start_msg(_session!);
    }
  }

  stopWorking() {
    if (!_closeed) {
      setState(() {
        _working = false;
        _started = false;
      });
    }

    if (_session != null) {
      _send_download_stop_msg(_session!);
    }
  }

  Future<IOSink> _getSaveFile() async {
        var appDocDir;
    if (Platform.isIOS) {
      appDocDir = await getApplicationDocumentsDirectory();
    } else if (Platform.isAndroid) {
      appDocDir = await getExternalStorageDirectory();
    } else {}
    String appDocPath = appDocDir!.path;

    _save_file_path = '$appDocPath/$_filename';
    var file_exists = new File(_save_file_path);
    var exists = await file_exists.exists();
    if (exists) {
      file_exists.delete();
    }
    var file = new File(_save_file_path);

    return file.openWrite(mode: FileMode.append, encoding: utf8);
  }

  videoPlayerControllerCallBack() {
    int pseconds = _videoPlayerController!.value.position.inSeconds;
    int dseconds = _videoPlayerController!.value.duration.inSeconds;
    if (!_closeed) {
      setState(() {
        if (dseconds > 0) {
          _value = pseconds / dseconds;
        }
      });
    }
  }

  Future<void> _releaseRemotePlayer() async {
    await _videoPlayerController!.pause();
    _videoPlayerController!.removeListener(videoPlayerControllerCallBack);
  }

  Future<void> _createRemotePlayer() async {
    var file = new File(_save_file_path);
    _videoPlayerController = await VideoPlayerController.file(file);

    _videoPlayerController!.addListener(videoPlayerControllerCallBack);

    await _videoPlayerController!.setLooping(false);
    await _videoPlayerController!.initialize().then((_) => setState(() {
          _initplayered = true;
        }));
    await _videoPlayerController!.play();
  }

  Future<bool> _checkFileSize() async {
    var fileExists = new File(_save_file_path);
    var exists = await fileExists.exists();
    if (exists) {
      var bytes = await fileExists.readAsBytes();
      if (bytes.length > 2 * 1024) {
        return Future<bool>.value(true);
      }
    }
    return Future<bool>.value(false);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text('Remote Player' +
              (_selfId != null ? ' [Your ID ($_selfId)] ' : '')),
        ),
        body: OrientationBuilder(builder: (context, orientation) {
          return Container(
            child: Stack(children: <Widget>[
              Positioned(
                  left: 0.0,
                  right: 0.0,
                  top: 0.0,
                  height: 200.0,
                  child: Container(
                    margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                    decoration: BoxDecoration(color: Colors.black),
                    child: _initplayered &&
                            _videoPlayerController!.value.isInitialized
                        ? AspectRatio(
                            aspectRatio:
                                _videoPlayerController!.value.aspectRatio,
                            child: VideoPlayer(_videoPlayerController!),
                          )
                        : Container(
                            decoration: new BoxDecoration(color: Colors.black),
                            height: 200.0,
                            width: double.infinity,
                            child: Center(
                              child: new CircularProgressIndicator(
                                backgroundColor: Color(0xffff0000),
                              ),
                            )),
                  )),
              Positioned(
                left: 0.0,
                right: 0.0,
                top: 200.0,
                height: 5.0,
                child: LinearProgressIndicator(
                  value: _value,
                  backgroundColor: Colors.cyan[100],
                  valueColor: new AlwaysStoppedAnimation<Color>(Colors.green),
                ),
              ),
            ]),
          );
        }),
      ),
      onWillPop: () {
        print(' onWillPop --------------------------------------------');
        //监听到退出按键
        if (_initplayered) {
          _releaseRemotePlayer();

          print(' onWillPop -------------------------------------pause-------');

          _closeed = true;
        }
        _hangUp();
        return Future<bool>.value(true);
      },
    );
  }

  @override
  void dispose() {
    if (_initplayered) {
      print(' dispose --------------------------------------------');
    }

    super.dispose();
    _videoPlayerController!.dispose();
  }
}
