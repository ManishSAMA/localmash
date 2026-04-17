import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/domain.dart';

/// Binary codec for [LocalMeshMessage] on the wire.
///
/// Layout (all big-endian):
/// ```
///  1  version          uint8
///  1  type             uint8  (MessageType index)
///  1  hopCount         uint8
///  1  ttl              uint8
///  8  lamportTs        int64
///  8  createdAt        int64
///  1  idLen            uint8
///  N  id               UTF-8
///  1  senderIdLen      uint8
///  N  senderId         UTF-8
///  1  recipientIdLen   uint8
///  N  recipientId      UTF-8
///  2  payloadLen       uint16
///  N  payload          bytes
///  2  sigLen           uint16
///  N  signature        bytes
/// ```
///
/// Total fixed overhead (empty variable fields): 4 + 8 + 8 + 3 + 2 + 2 = 27 bytes.
/// A typical text message fits well within the BLE 244-byte usable MTU after
/// chunking in [BleTransport].
class WireCodec {
  WireCodec._();

  static const int _minBytes = 27; // absolute minimum

  /// Encode a [LocalMeshMessage] into a [Uint8List].
  static Uint8List encode(LocalMeshMessage msg) {
    final idBytes = utf8.encode(msg.id);
    final senderBytes = utf8.encode(msg.senderId);
    final recipientBytes = utf8.encode(msg.recipientId);

    assert(idBytes.length <= 255, 'id too long for wire format');
    assert(senderBytes.length <= 255, 'senderId too long for wire format');
    assert(recipientBytes.length <= 255, 'recipientId too long for wire format');

    final totalLen = 4 + // version, type, hopCount, ttl
        8 + // lamportTs
        8 + // createdAt
        1 + idBytes.length +
        1 + senderBytes.length +
        1 + recipientBytes.length +
        2 + msg.payload.length +
        2 + msg.signature.length;

    final buf = ByteData(totalLen);
    var offset = 0;

    buf.setUint8(offset++, msg.version);
    buf.setUint8(offset++, msg.type.index);
    buf.setUint8(offset++, msg.hopCount);
    buf.setUint8(offset++, msg.ttl);
    buf.setInt64(offset, msg.lamportTs, Endian.big);
    offset += 8;
    buf.setInt64(offset, msg.createdAt, Endian.big);
    offset += 8;

    // id
    buf.setUint8(offset++, idBytes.length);
    buf.buffer.asUint8List(offset, idBytes.length).setAll(0, idBytes);
    offset += idBytes.length;

    // senderId
    buf.setUint8(offset++, senderBytes.length);
    buf.buffer.asUint8List(offset, senderBytes.length).setAll(0, senderBytes);
    offset += senderBytes.length;

    // recipientId
    buf.setUint8(offset++, recipientBytes.length);
    buf.buffer
        .asUint8List(offset, recipientBytes.length)
        .setAll(0, recipientBytes);
    offset += recipientBytes.length;

    // payload
    buf.setUint16(offset, msg.payload.length, Endian.big);
    offset += 2;
    buf.buffer.asUint8List(offset, msg.payload.length).setAll(0, msg.payload);
    offset += msg.payload.length;

    // signature
    buf.setUint16(offset, msg.signature.length, Endian.big);
    offset += 2;
    buf.buffer
        .asUint8List(offset, msg.signature.length)
        .setAll(0, msg.signature);

    return buf.buffer.asUint8List();
  }

  /// Decode a [Uint8List] back into a [LocalMeshMessage].
  /// Throws [FormatException] if the data is malformed.
  static LocalMeshMessage decode(Uint8List bytes) {
    if (bytes.length < _minBytes) {
      throw FormatException(
          'WireCodec: too short (${bytes.length} < $_minBytes)');
    }

    final buf = ByteData.sublistView(bytes);
    var offset = 0;

    final version = buf.getUint8(offset++);
    final typeIndex = buf.getUint8(offset++);
    final hopCount = buf.getUint8(offset++);
    final ttl = buf.getUint8(offset++);
    final lamportTs = buf.getInt64(offset, Endian.big);
    offset += 8;
    final createdAt = buf.getInt64(offset, Endian.big);
    offset += 8;

    // id
    final idLen = buf.getUint8(offset++);
    _checkBounds(bytes, offset, idLen, 'id');
    final id = utf8.decode(bytes.sublist(offset, offset + idLen));
    offset += idLen;

    // senderId
    final senderLen = buf.getUint8(offset++);
    _checkBounds(bytes, offset, senderLen, 'senderId');
    final senderId = utf8.decode(bytes.sublist(offset, offset + senderLen));
    offset += senderLen;

    // recipientId
    final recipientLen = buf.getUint8(offset++);
    _checkBounds(bytes, offset, recipientLen, 'recipientId');
    final recipientId =
        utf8.decode(bytes.sublist(offset, offset + recipientLen));
    offset += recipientLen;

    // payload
    if (offset + 2 > bytes.length) {
      throw const FormatException('WireCodec: truncated before payloadLen');
    }
    final payloadLen = buf.getUint16(offset, Endian.big);
    offset += 2;
    _checkBounds(bytes, offset, payloadLen, 'payload');
    final payload = bytes.sublist(offset, offset + payloadLen);
    offset += payloadLen;

    // signature
    if (offset + 2 > bytes.length) {
      throw const FormatException('WireCodec: truncated before sigLen');
    }
    final sigLen = buf.getUint16(offset, Endian.big);
    offset += 2;
    _checkBounds(bytes, offset, sigLen, 'signature');
    final signature = bytes.sublist(offset, offset + sigLen);

    if (typeIndex >= MessageType.values.length) {
      throw FormatException('WireCodec: unknown MessageType index $typeIndex');
    }

    return LocalMeshMessage(
      id: id,
      version: version,
      type: MessageType.values[typeIndex],
      senderId: senderId,
      recipientId: recipientId,
      payload: payload,
      hopCount: hopCount,
      ttl: ttl,
      lamportTs: lamportTs,
      signature: signature,
      createdAt: createdAt,
    );
  }

  static void _checkBounds(
      Uint8List bytes, int offset, int length, String field) {
    if (offset + length > bytes.length) {
      throw FormatException(
          'WireCodec: buffer underflow reading $field '
          '(need ${offset + length}, have ${bytes.length})');
    }
  }
}
