class Peer {
  const Peer({
    required this.id,
    required this.displayName,
    required this.publicKey,
    required this.lastSeen,
    required this.isConnected,
  });

  final String id;
  final String displayName;
  final List<int> publicKey;
  final int lastSeen;
  final bool isConnected;
}
