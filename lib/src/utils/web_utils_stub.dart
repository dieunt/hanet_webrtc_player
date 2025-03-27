import 'dart:typed_data';

/// Stub function for non-web platforms
void downloadFile(Uint8List bytes, String filename) {
  throw UnsupportedError('downloadFile is only supported on web platform');
}
