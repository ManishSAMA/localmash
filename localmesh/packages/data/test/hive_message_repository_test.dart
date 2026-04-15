import 'package:test/test.dart';
import 'package:domain/domain.dart';
import 'package:data/data_lib.dart';
import 'test_helpers.dart';

LocalMeshMessage _makeMessage({
  required String id,
  required String senderId,
  required String recipientId,
  required int lamportTs,
}) {
  return LocalMeshMessage(
    id: id,
    version: 1,
    type: MessageType.text,
    senderId: senderId,
    recipientId: recipientId,
    payload: const [1, 2, 3],
    hopCount: 0,
    ttl: 5,
    lamportTs: lamportTs,
    signature: const [4, 5, 6],
    createdAt: 1000,
  );
}

void main() {
  setUpAll(setupHiveForTest);
  tearDown(HiveLocalDataSource.clearAll);
  tearDownAll(tearDownHive);

  final repo = HiveMessageRepository();
  const chatId = 'chat-room-1';
  const otherId = 'other-peer';

  test('save then retrieve by id returns equal message', () async {
    final msg = _makeMessage(
      id: 'msg-1',
      senderId: chatId,
      recipientId: otherId,
      lamportTs: 10,
    );
    await repo.saveMessage(msg);
    final retrieved = await repo.getMessageById('msg-1');
    expect(retrieved, isNotNull);
    expect(retrieved!.id, equals('msg-1'));
    expect(retrieved.senderId, equals(chatId));
    expect(retrieved.lamportTs, equals(10));
  });

  test('hasMessage returns false before save, true after', () async {
    expect(await repo.hasMessage('msg-2'), isFalse);
    final msg = _makeMessage(
      id: 'msg-2',
      senderId: chatId,
      recipientId: otherId,
      lamportTs: 20,
    );
    await repo.saveMessage(msg);
    expect(await repo.hasMessage('msg-2'), isTrue);
  });

  test('getMessagesForChat returns messages sorted by lamportTs ascending',
      () async {
    final m1 = _makeMessage(
      id: 'sort-1',
      senderId: chatId,
      recipientId: otherId,
      lamportTs: 30,
    );
    final m2 = _makeMessage(
      id: 'sort-2',
      senderId: otherId,
      recipientId: chatId,
      lamportTs: 10,
    );
    final m3 = _makeMessage(
      id: 'sort-3',
      senderId: chatId,
      recipientId: otherId,
      lamportTs: 20,
    );
    await repo.saveMessage(m1);
    await repo.saveMessage(m2);
    await repo.saveMessage(m3);

    final messages = await repo.getMessagesForChat(chatId);
    expect(messages.map((m) => m.lamportTs).toList(), equals([10, 20, 30]));
  });

  test('afterLamportTs filter excludes messages with ts <= filter value',
      () async {
    final m1 = _makeMessage(
      id: 'filter-1',
      senderId: chatId,
      recipientId: otherId,
      lamportTs: 5,
    );
    final m2 = _makeMessage(
      id: 'filter-2',
      senderId: chatId,
      recipientId: otherId,
      lamportTs: 10,
    );
    final m3 = _makeMessage(
      id: 'filter-3',
      senderId: chatId,
      recipientId: otherId,
      lamportTs: 15,
    );
    await repo.saveMessage(m1);
    await repo.saveMessage(m2);
    await repo.saveMessage(m3);

    final messages = await repo.getMessagesForChat(chatId, afterLamportTs: 10);
    expect(messages.length, equals(1));
    expect(messages.first.lamportTs, equals(15));
  });

  test('limit caps results to last N by lamportTs', () async {
    for (int i = 1; i <= 5; i++) {
      await repo.saveMessage(
        _makeMessage(
          id: 'limit-$i',
          senderId: chatId,
          recipientId: otherId,
          lamportTs: i * 10,
        ),
      );
    }

    final messages = await repo.getMessagesForChat(chatId, limit: 3);
    expect(messages.length, equals(3));
    // Should be the last 3 by lamportTs: 30, 40, 50
    expect(messages.map((m) => m.lamportTs).toList(), equals([30, 40, 50]));
  });

  test(
    'getHighestLamportTsForChat returns max ts; returns 0 when no messages',
    () async {
      expect(await repo.getHighestLamportTsForChat('empty-chat'), equals(0));

      final m1 = _makeMessage(
        id: 'high-1',
        senderId: chatId,
        recipientId: otherId,
        lamportTs: 100,
      );
      final m2 = _makeMessage(
        id: 'high-2',
        senderId: chatId,
        recipientId: otherId,
        lamportTs: 42,
      );
      await repo.saveMessage(m1);
      await repo.saveMessage(m2);

      expect(await repo.getHighestLamportTsForChat(chatId), equals(100));
    },
  );

  test('deleteMessage removes message; getMessageById returns null after delete',
      () async {
    final msg = _makeMessage(
      id: 'del-1',
      senderId: chatId,
      recipientId: otherId,
      lamportTs: 1,
    );
    await repo.saveMessage(msg);
    expect(await repo.hasMessage('del-1'), isTrue);

    await repo.deleteMessage('del-1');
    expect(await repo.getMessageById('del-1'), isNull);
    expect(await repo.hasMessage('del-1'), isFalse);
  });
}
