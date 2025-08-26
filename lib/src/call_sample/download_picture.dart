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
import 'random_string.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' show Platform;

class DataChannelDownloacPic extends StatefulWidget {
  static String tag = 'call_sample';
  final String peerId;
  final String selfId;
  DataChannelDownloacPic({required this.selfId, required this.peerId});

  @override
  _DataChannelDownloacPicState createState() => _DataChannelDownloacPicState();
}

class _DataChannelDownloacPicState extends State<DataChannelDownloacPic> {
  Signaling? _signaling;
  List<dynamic> _peers = [];
  String? _selfId;
  String? _peerId;
  late IOSink _save_file;
  bool _createsavefile = false;
  bool _inCalling = false;
  bool _dataChannelOpened = false;
  RTCDataChannel? _dataChannel;
  Session? _session;
  Timer? _timer;
  var _text = '';
  bool _working = false;
  bool _started = false;
  bool _autodownload = true;
  bool _downloaded = false;
  double _value = 0;
  int _filesize = 0;
  int _recvsize = 0;
  int _preindex = 0;
  int _totlesize = 0;
  int _totle_recvsize = 0;
  Uint8List binaryIntList = Uint8List(0);
  List<int> mutableData = [];

  late String _save_file_path;

  var _recvMsgEvent;
  JsonEncoder _encoder = JsonEncoder();
  JsonDecoder _decoder = JsonDecoder();
  // ignore: unused_element
  _DataChannelDownloacPicState();

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
        if (data.isBinary) {
          setState(() {
            _recvsize = data.binary.length;
            _totle_recvsize += _recvsize;
            if (_totlesize != 0 && _totle_recvsize == _totlesize) {
              _value = _totle_recvsize / _totlesize;
              // _downloaded = true;
            }
          });
          var databuf = data.binary;
          mutableData.addAll(databuf);
          // var len = mutableData.length;
          //  print(' binaryIntList --------------------len ------------------------$_recvsize  ----$len');
          if (_createsavefile && _save_file != null) {
            _save_file..add(databuf);
          }

          // _save_file?.writeAsBytes(data.binary,mode: FileMode.append,flush: true);
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
              setState(() {
                eventBus.emit(NewSessionMsgEvent(session.sid));
                _session = session;
              });
              _timer =
                  Timer.periodic(Duration(seconds: 1), _handleDataChannelTest);
              break;
            }
          case CallState.CallStateBye:
            {
              setState(() {
                _inCalling = false;
                _dataChannel = null;
                _session = null;
                _text = '';
              });
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
          setState(() {
            _dataChannelOpened = true;
          });
          _save_file = await _getSaveFile();
          if (_save_file != null) {
            _createsavefile = true;
            _send_download_open_msg(session, "snap-2022-05-02-17.jpg");
          }
        } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
          setState(() {
            _dataChannelOpened = false;
          });
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

              binaryIntList = Uint8List.fromList(mutableData);
              if (_createsavefile) {
                _save_file.close();
                _createsavefile = false;
              }

              setState(() {
                _downloaded = true;
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
    if (_dataChannelOpened) {}
  }

  _invitePeer(String sessionId, String peerId) async {
    if (peerId != _selfId) {
      _signaling?.invite(sessionId, peerId, false, false, false, false, true,
          "download", "", "admin", "123456");
    }
  }

  _hangUp() {
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
    setState(() {
      _value = 0;
    });

    if (_session != null) {
      _send_download_start_msg(_session!);
    }
  }

  stopWorking() {
    setState(() {
      _working = false;
      _started = false;
    });
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
    //print(' _getSaveFile --------------------------------------------$appDocPath');

    _save_file_path = '$appDocPath/snap-2022-05-02-17.jpg';
    var file_exists = new File(_save_file_path);
    var exists = await file_exists.exists();
    if (exists) {
      file_exists.delete();
    }
    var file = new File(_save_file_path);

    return file.openWrite(mode: FileMode.append, encoding: utf8);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      child: Scaffold(
          appBar: AppBar(
            title: Text('Download Picture' +
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
                    width: double.infinity,
                    height: 200.0,
                    child: _downloaded
                        ? Image.memory(binaryIntList,
                            width: double.infinity,
                            height: 200.0,
                            fit: BoxFit.fitHeight)
                        // ?Image.file(File(_save_file_path),width: double.infinity,height: 200.0,fit: BoxFit.fitHeight)
                        : Container(
                            decoration: new BoxDecoration(color: Colors.black),
                            height: 200.0,
                            width: double.infinity,
                            child: Center(
                              child: new CircularProgressIndicator(
                                backgroundColor: Color(0xffff0000),
                              ),
                            )),
                  ),
                )
              ]),
            );
          })),
      onWillPop: () {
        //监听到退出按键
        _hangUp();
        return Future<bool>.value(true);
      },
    );
  }
}
