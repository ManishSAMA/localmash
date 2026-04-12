class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.name,
    required this.peerIds,
    required this.lastMessageTs,
  });

  final String id;
  final String name;
  final List<String> peerIds;
  final int lastMessageTs;
}
