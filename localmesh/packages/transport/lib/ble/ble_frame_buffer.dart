import 'dart:typed_data';

/// Reassembles chunks into complete frames.
///
/// Frame format: [length (2 bytes, big-endian)] [payload (N bytes)]
class BleFrameBuffer {
  final List<int> _buffer = <int>[];
  int? _expectedFrameLength;

  static const int headerSize = 2;

  List<Uint8List> addChunk(Uint8List chunk) {
    _buffer.addAll(chunk);
    final frames = <Uint8List>[];

    while (true) {
      if (_expectedFrameLength == null) {
        if (_buffer.length < headerSize) break;
        _expectedFrameLength = (_buffer[0] << 8) | _buffer[1];
        _buffer.removeRange(0, headerSize);
      }

      if (_buffer.length < _expectedFrameLength!) break;

      frames.add(Uint8List.fromList(_buffer.sublist(0, _expectedFrameLength!)));
      _buffer.removeRange(0, _expectedFrameLength!);
      _expectedFrameLength = null;
    }

    return frames;
  }
}
