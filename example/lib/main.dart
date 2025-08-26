import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hanet_webrtc_player/hanet_webrtc_player.dart';

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

  void _togglePlayer() {
    setState(() {
      _showPlayer = false;
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
                  peerId: 'HANT-00-TLV3-8V2G-00000109',
                  showFullscreen: true,
                  showCapture: true,
                  showRecord: true,
                  showMic: true,
                  showVolume: true,
                  source: 'SubStream',
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
            ElevatedButton(
              onPressed: _togglePlayer,
              child: const Text('Dispose Player'),
            ),
          ],
        ),
      ),
    );
  }
}
