import 'package:meta/meta.dart';

@immutable
class Peer {
  const Peer({
    required this.id,
    required this.displayName,
    required this.signingPublicKey,
    required this.encryptionPublicKey,
    required this.lastSeen,
    required this.isConnected,
    required this.isTrusted,
  });

  final String id;
  final String displayName;
  final List<int> signingPublicKey;
  final List<int> encryptionPublicKey;
  final int lastSeen;
  final bool isConnected;
  final bool isTrusted;

  Peer copyWith({
    String? id,
    String? displayName,
    List<int>? signingPublicKey,
    List<int>? encryptionPublicKey,
    int? lastSeen,
    bool? isConnected,
    bool? isTrusted,
  }) {
    return Peer(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      signingPublicKey: signingPublicKey ?? this.signingPublicKey,
      encryptionPublicKey: encryptionPublicKey ?? this.encryptionPublicKey,
      lastSeen: lastSeen ?? this.lastSeen,
      isConnected: isConnected ?? this.isConnected,
      isTrusted: isTrusted ?? this.isTrusted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Peer && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
