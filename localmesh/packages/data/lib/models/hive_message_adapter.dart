import 'package:hive/hive.dart';
import 'package:domain/domain.dart';

class HiveMessageAdapter extends TypeAdapter<LocalMeshMessage> {
  @override
  final int typeId = 1;

  @override
  LocalMeshMessage read(BinaryReader reader) {
    final id = reader.readString();
    final version = reader.readInt();
    final typeIndex = reader.readInt();
    final senderId = reader.readString();
    final recipientId = reader.readString();
    final payload = reader.readByteList();
    final hopCount = reader.readInt();
    final ttl = reader.readInt();
    final lamportTs = reader.readInt();
    final signature = reader.readByteList();
    final createdAt = reader.readInt();
    var deliveryStatus = MessageDeliveryStatus.received;
    String? plaintext;
    try {
      final statusIndex = reader.readInt();
      if (statusIndex >= 0 &&
          statusIndex < MessageDeliveryStatus.values.length) {
        deliveryStatus = MessageDeliveryStatus.values[statusIndex];
      }
      plaintext = reader.readBool() ? reader.readString() : null;
    } catch (_) {
      deliveryStatus = MessageDeliveryStatus.received;
      plaintext = null;
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
      deliveryStatus: deliveryStatus,
      plaintext: plaintext,
    );
  }

  @override
  void write(BinaryWriter writer, LocalMeshMessage obj) {
    writer.writeString(obj.id);
    writer.writeInt(obj.version);
    writer.writeInt(obj.type.index);
    writer.writeString(obj.senderId);
    writer.writeString(obj.recipientId);
    writer.writeByteList(obj.payload);
    writer.writeInt(obj.hopCount);
    writer.writeInt(obj.ttl);
    writer.writeInt(obj.lamportTs);
    writer.writeByteList(obj.signature);
    writer.writeInt(obj.createdAt);
    writer.writeInt(obj.deliveryStatus.index);
    writer.writeBool(obj.plaintext != null);
    if (obj.plaintext != null) {
      writer.writeString(obj.plaintext!);
    }
  }
}
