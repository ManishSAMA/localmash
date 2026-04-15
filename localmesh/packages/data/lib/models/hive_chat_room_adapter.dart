import 'package:hive/hive.dart';
import 'package:domain/domain.dart';

class HiveChatRoomAdapter extends TypeAdapter<ChatRoom> {
  @override
  final int typeId = 4;

  @override
  ChatRoom read(BinaryReader reader) {
    final id = reader.readString();
    final name = reader.readString();
    final peerIds = reader.readList().cast<String>();
    final lastMessageTs = reader.readInt();
    final isGroup = reader.readBool();

    return ChatRoom(
      id: id,
      name: name,
      peerIds: peerIds,
      lastMessageTs: lastMessageTs,
      isGroup: isGroup,
    );
  }

  @override
  void write(BinaryWriter writer, ChatRoom obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.name);
    writer.writeList(obj.peerIds);
    writer.writeInt(obj.lastMessageTs);
    writer.writeBool(obj.isGroup);
  }
}
