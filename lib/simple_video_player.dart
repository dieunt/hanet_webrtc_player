import 'package:flutter/material.dart';

/// A simple video player widget that currently displays a black rectangle.
/// This widget can be extended to implement actual video playback functionality.
class SimpleVideoPlayer extends StatelessWidget {
  /// The width of the video player widget.
  final double width;

  /// The height of the video player widget.
  final double height;

  /// Creates a new instance of [SimpleVideoPlayer].
  ///
  /// [width] and [height] are optional parameters that default to 300 and 200 respectively.
  const SimpleVideoPlayer({super.key, this.width = 300, this.height = 200});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Colors.black,
      child: const Center(
        child: Text(
          'Video Player',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }
}
