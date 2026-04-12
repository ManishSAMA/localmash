import 'package:domain/domain.dart';

class HiveMessageRepository implements MessageRepository {
  @override
  Future<void> saveMessage(LocalMeshMessage message) {
    throw UnimplementedError();
  }

  @override
  Future<List<LocalMeshMessage>> getMessages(String chatRoomId, {int? afterLamportTs}) {
    throw UnimplementedError();
  }

  @override
  Future<LocalMeshMessage?> getMessageById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<bool> hasMessage(String id) {
    throw UnimplementedError();
  }
}
