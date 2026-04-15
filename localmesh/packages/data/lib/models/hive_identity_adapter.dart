import 'package:hive/hive.dart';
import 'package:domain/domain.dart';

class HiveIdentityAdapter extends TypeAdapter<LocalMeshIdentity> {
  @override
  final int typeId = 3;

  @override
  LocalMeshIdentity read(BinaryReader reader) {
    final displayName = reader.readString();
    final signingPublicKey = reader.readByteList();
    final signingPrivateKey = reader.readByteList();
    final encryptionPublicKey = reader.readByteList();
    final encryptionPrivateKey = reader.readByteList();
    final fingerprint = reader.readString();

    return LocalMeshIdentity(
      displayName: displayName,
      signingPublicKey: signingPublicKey,
      signingPrivateKey: signingPrivateKey,
      encryptionPublicKey: encryptionPublicKey,
      encryptionPrivateKey: encryptionPrivateKey,
      fingerprint: fingerprint,
    );
  }

  @override
  void write(BinaryWriter writer, LocalMeshIdentity obj) {
    writer.writeString(obj.displayName);
    writer.writeByteList(obj.signingPublicKey);
    writer.writeByteList(obj.signingPrivateKey);
    writer.writeByteList(obj.encryptionPublicKey);
    writer.writeByteList(obj.encryptionPrivateKey);
    writer.writeString(obj.fingerprint);
  }
}
