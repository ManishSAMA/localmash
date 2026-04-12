import 'package:meta/meta.dart';

@immutable
class LocalMeshIdentity {
  const LocalMeshIdentity({
    required this.displayName,
    required this.signingPublicKey,
    required this.signingPrivateKey,
    required this.encryptionPublicKey,
    required this.encryptionPrivateKey,
    required this.fingerprint,
  });

  final String displayName;
  final List<int> signingPublicKey;
  final List<int> signingPrivateKey;
  final List<int> encryptionPublicKey;
  final List<int> encryptionPrivateKey;
  final String fingerprint;
}
