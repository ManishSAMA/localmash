import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/ble/ble_frame_buffer.dart';

void main() {
  group('BleFrameBuffer', () {
    late BleFrameBuffer buffer;

    setUp(() {
      buffer = BleFrameBuffer();
    });

    test('reassembles a single-chunk frame', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final framed = Uint8List(2 + payload.length);
      ByteData.sublistView(framed).setUint16(0, payload.length, Endian.big);
      framed.setRange(2, framed.length, payload);

      final frames = buffer.addChunk(framed);

      expect(frames.length, 1);
      expect(frames.first, payload);
    });

    test('reassembles multi-chunk frame', () {
      final payload = Uint8List.fromList(List.generate(10, (i) => i));
      final framed = Uint8List(2 + payload.length);
      ByteData.sublistView(framed).setUint16(0, payload.length, Endian.big);
      framed.setRange(2, framed.length, payload);

      final chunk1 = framed.sublist(0, 5);
      final chunk2 = framed.sublist(5);

      expect(buffer.addChunk(chunk1).isEmpty, true);
      final frames = buffer.addChunk(chunk2);

      expect(frames.length, 1);
      expect(frames.first, payload);
    });

    test('handles multiple frames in chunks', () {
      final p1 = Uint8List.fromList([1, 1]);
      final f1 = Uint8List.fromList([0, 2, 1, 1]);
      final p2 = Uint8List.fromList([2, 2, 2]);
      final f2 = Uint8List.fromList([0, 3, 2, 2, 2]);

      final combined = Uint8List.fromList([...f1, ...f2]);
      
      final chunk1 = combined.sublist(0, 6); // [0, 2, 1, 1, 0, 3]
      final chunk2 = combined.sublist(6);    // [2, 2, 2]

      final res1 = buffer.addChunk(chunk1);
      expect(res1.length, 1);
      expect(res1.first, p1);

      final res2 = buffer.addChunk(chunk2);
      expect(res2.length, 1);
      expect(res2.first, p2);
    });
  });
}
