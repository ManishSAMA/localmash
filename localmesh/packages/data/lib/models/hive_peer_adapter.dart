import 'package:hive/hive.dart';
import 'package:domain/domain.dart';

class HivePeerAdapter extends TypeAdapter<Peer> {
  @override
  final int typeId = 2;

  @override
  Peer read(BinaryReader reader) {
    final id = reader.readString();
    final displayName = reader.readString();
    final signingPublicKey = reader.readByteList();
    final encryptionPublicKey = reader.readByteList();
    final lastSeen = reader.readInt();
    final isTrusted = reader.readBool();

    return Peer(
      id: id,
      displayName: displayName,
      signingPublicKey: signingPublicKey,
      encryptionPublicKey: encryptionPublicKey,
      lastSeen: lastSeen,
      isConnected: false, // transient — never persisted
      isTrusted: isTrusted,
    );
  }

  @override
  void write(BinaryWriter writer, Peer obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.displayName);
    writer.writeByteList(obj.signingPublicKey);
    writer.writeByteList(obj.encryptionPublicKey);
    writer.writeInt(obj.lastSeen);
    writer.writeBool(obj.isTrusted);
  }
}
