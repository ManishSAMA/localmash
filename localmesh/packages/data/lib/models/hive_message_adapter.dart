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
  }
}
