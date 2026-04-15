import 'package:meta/meta.dart';

@immutable
class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.name,
    required this.peerIds,
    required this.lastMessageTs,
    required this.isGroup,
  });

  final String id;
  final String name;
  final List<String> peerIds;
  final int lastMessageTs;
  final bool isGroup;

  ChatRoom copyWith({
    String? id,
    String? name,
    List<String>? peerIds,
    int? lastMessageTs,
    bool? isGroup,
  }) {
    return ChatRoom(
      id: id ?? this.id,
      name: name ?? this.name,
      peerIds: peerIds ?? this.peerIds,
      lastMessageTs: lastMessageTs ?? this.lastMessageTs,
      isGroup: isGroup ?? this.isGroup,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ChatRoom && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
