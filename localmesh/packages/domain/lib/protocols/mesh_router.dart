import '../entities/message.dart';

class MeshRouter {
  MeshRouter({this.maxTtl = 5});

  final int maxTtl;
  final Set<String> _seenMessages = {};

  bool shouldProcess(LocalMeshMessage message) {
    if (_seenMessages.contains(message.id)) return false;
    if (message.hopCount > message.ttl) return false;
    return true;
  }

  bool shouldForward(LocalMeshMessage message) {
    return message.hopCount < message.ttl;
  }

  void markSeen(String messageId) {
    _seenMessages.add(messageId);
  }

  LocalMeshMessage prepareForForward(LocalMeshMessage message) {
    return message.copyWith(hopCount: message.hopCount + 1);
  }
}
