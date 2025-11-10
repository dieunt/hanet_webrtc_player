import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hanet_webrtc_player/hanet_webrtc_multiple.dart';
import 'package:hanet_webrtc_player/hanet_webrtc_single.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hanet WebRTC Player Example',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const PlayerExample(),
    );
  }
}

class PlayerExample extends StatefulWidget {
  const PlayerExample({super.key});

  @override
  State<PlayerExample> createState() => _PlayerExampleState();
}

class _PlayerExampleState extends State<PlayerExample> {
  bool _showPlayer = false;
  bool _showMultiplePlayer = true;
  final GlobalKey _playerKey = GlobalKey();
  Key? _multiplePlayerKey = UniqueKey();
  bool _isFullscreen = false;
  late final HanetWebRTCSingle _player;

  void _togglePlayer() {
    setState(() {
      _showPlayer = !_showPlayer;
    });
  }

  void _toggleMultiplePlayer() {
    setState(() {
      _showMultiplePlayer = !_showMultiplePlayer;
      if (_showMultiplePlayer) {
        _multiplePlayerKey = UniqueKey();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _player = HanetWebRTCSingle(
      key: _playerKey,
      peerId: 'HANT-00-TLV3-8V2G-00000109',
      showFullscreen: true,
      showCapture: false,
      showRecord: false,
      showMic: true,
      showVolume: true,
      showControls: true,
      isVertical: false,
      onOffline: () {
        debugPrint('onOffline');
      },
      isDebug: true,
      onFullscreen: (isFullscreen) {
        debugPrint('onFullscreen: $isFullscreen');
        setState(() {
          _isFullscreen = isFullscreen;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isFullscreen ? null : AppBar(title: const Text('Hanet WebRTC Player Example')),
      extendBodyBehindAppBar: _isFullscreen,
      body: _isFullscreen
          ? SizedBox.expand(child: _player)
          : SingleChildScrollView(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_showPlayer)
                      Align(
                        alignment: Alignment.topCenter,
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: _player,
                        ),
                      ),
                    const SizedBox(height: 20),
                    if (_showMultiplePlayer)
                      Container(
                        width: MediaQuery.of(context).size.width,
                        child: HanetWebRTCMultiple(
                          key: _multiplePlayerKey,
                          sessionIds: const [],
                          peerItems: const [
                            PeerItem(
                              peerId: 'HANT-00-63AH-UZHN-00002471',
                              type: 'camera',
                              name: 'Camera 1',
                              imageUrl: 'assets/icons/camera.png',
                            ),
                            PeerItem(
                              peerId: 'HANT-00-6152-98ZP-00002256',
                              type: 'camera',
                              name: 'Camera 2',
                              imageUrl: 'assets/icons/camera.png',
                            ),
                            PeerItem(
                              peerId: 'HANT-00-03AP-UULP-00000272',
                              type: 'camera',
                              name: 'Camera 3',
                              imageUrl: 'assets/icons/camera.png',
                            ),
                            PeerItem(
                              peerId: 'HANT-00-TLV3-8V2G-00000109',
                              type: 'camera',
                              name: 'Camera 4',
                              imageUrl: 'assets/icons/camera.png',
                            ),
                            PeerItem(
                              peerId: 'HANT-00-LSCF-3K51-00002474',
                              type: 'camera',
                              name: 'Camera 5',
                              imageUrl: 'assets/icons/camera.png',
                            ),
                            PeerItem(
                              peerId: 'HANT-00-OZ9H-D5T1-00002734',
                              type: 'camera',
                              name: 'Camera 6',
                              imageUrl: 'assets/icons/camera.png',
                            ),
                            PeerItem(
                              peerId: 'HANT-00-L2G7-HEDH-00002870',
                              type: 'camera',
                              name: 'Camera 7',
                              imageUrl: 'assets/icons/camera.png',
                            ),
                            PeerItem(
                              peerId: 'HANT-00-S26H-IRCE-00002735',
                              type: 'camera',
                              name: 'Camera 8',
                              imageUrl: 'assets/icons/camera.png',
                            ),
                            PeerItem(
                              peerId: 'HANT-00-5DQT-A9IH-00002736',
                              type: 'camera',
                              name: 'Camera 9',
                              imageUrl: 'assets/icons/camera.png',
                            ),
                            PeerItem(
                              peerId: 'HANT-00-9TQT-Z1OR-00002737',
                              type: 'camera',
                              name: 'Camera 10',
                              imageUrl: 'assets/icons/camera.png',
                            ),
                            PeerItem(
                              peerId: 'HANT-00-15TC-H5NT-00002302',
                              type: 'camera',
                              name: 'Camera 11',
                              imageUrl: 'assets/icons/camera.png',
                            ),
                            PeerItem(
                              peerId: 'HANT-00-9TOE-YORZ-00002321',
                              type: 'camera',
                              name: 'Camera 12',
                              imageUrl: 'assets/icons/camera.png',
                            ),
                            PeerItem(
                              peerId: 'HANT-00-LZY5-28KB-00002057',
                              type: 'camera',
                              name: 'Camera 13',
                              imageUrl: 'assets/icons/camera.png',
                            ),
                            PeerItem(
                              peerId: 'HANT-00-QVZO-EBHG-00002871',
                              type: 'camera',
                              name: 'Camera 14',
                              imageUrl: 'assets/icons/camera.png',
                            ),
                          ],
                          onOffline: (sid) {
                            debugPrint('Multiple player offline');
                          },
                        ),
                      ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(onPressed: _togglePlayer, child: const Text('Toggle Single Player')),
                        ElevatedButton(onPressed: _toggleMultiplePlayer, child: const Text('Toggle Multiple Players')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
