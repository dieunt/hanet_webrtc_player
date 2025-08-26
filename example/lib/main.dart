import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hanet_webrtc_player/hanet_webrtc_player.dart';
import 'package:hanet_webrtc_player/hanet_webrtc_multiple.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hanet WebRTC Player Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
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
  bool _showPlayer = true;
  bool _showMultiplePlayer = false;
  Key? _playerKey = UniqueKey();
  Key? _multiplePlayerKey = UniqueKey();

  void _togglePlayer() {
    setState(() {
      _showPlayer = !_showPlayer;
      if (_showPlayer) {
        _playerKey = UniqueKey();
      } else {
        _playerKey = null;
      }
    });
  }

  void _toggleMultiplePlayer() {
    setState(() {
      _showMultiplePlayer = !_showMultiplePlayer;
      if (_showMultiplePlayer) {
        _multiplePlayerKey = UniqueKey();
      } else {
        _multiplePlayerKey = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hanet WebRTC Player Example'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_showPlayer)
              Container(
                // width: 640,
                // height: 360,
                child: HanetWebRTCPlayer(
                  key: _playerKey,
                  peerId: 'HANT-00-TLV3-8V2G-00000109',
                  showFullscreen: true,
                  showCapture: true,
                  showRecord: true,
                  showMic: true,
                  showVolume: true,
                  source: 'MainStream',
                  showControls: true,
                  isVertical: false,
                  onOffline: () {
                    debugPrint('onOffline');
                  },
                  isDebug: false,
                  onFullscreen: (isFullscreen) {
                    debugPrint('onFullscreen: $isFullscreen');
                  },
                ),
              ),
            const SizedBox(height: 20),
            if (_showMultiplePlayer)
              Container(
                width: MediaQuery.of(context).size.width,
                height: 400,
                child: HanetWebRTCMultiple(
                  key: _multiplePlayerKey,
                  peerIds: const [
                    'HANT-00-TLV3-8V2G-00000109',
                    'HANT-00-TLV3-8V2G-00000110',
                    'HANT-00-TLV3-8V2G-00000111',
                    'HANT-00-TLV3-8V2G-00000112',
                  ],
                  onOffline: () {
                    debugPrint('Multiple player offline');
                  },
                ),
              ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _togglePlayer,
                  child: const Text('Toggle Single Player'),
                ),
                ElevatedButton(
                  onPressed: _toggleMultiplePlayer,
                  child: const Text('Toggle Multiple Players'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
