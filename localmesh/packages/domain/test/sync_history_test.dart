import 'package:test/test.dart';
import 'package:domain/domain.dart';
import 'fakes.dart';

LocalMeshMessage _msg(String id, String room, int lamportTs) {
  return LocalMeshMessage(
    id: id,
    version: 1,
    type: MessageType.text,
    senderId: 'alice',
    recipientId: room,
    payload: const [],
    hopCount: 0,
    ttl: 5,
    lamportTs: lamportTs,
    signature: const [],
    createdAt: 0,
  );
}

void main() {
  late FakeMessageRepository messageRepo;
  late SyncHistory syncHistory;

  setUp(() {
    messageRepo = FakeMessageRepository();
    syncHistory = SyncHistory(messageRepo: messageRepo);
  });

  test('1. buildRequest returns 0 for rooms with no messages', () async {
    final request = await syncHistory.buildRequest(['room-a', 'room-b']);
    expect(request.chatRoomTimestamps['room-a'], 0);
    expect(request.chatRoomTimestamps['room-b'], 0);
  });

  test('2. buildRequest returns the highest lamportTs per room', () async {
    await messageRepo.saveMessage(_msg('m1', 'room-a', 3));
    await messageRepo.saveMessage(_msg('m2', 'room-a', 7));
    await messageRepo.saveMessage(_msg('m3', 'room-b', 2));

    final request = await syncHistory.buildRequest(['room-a', 'room-b']);
    expect(request.chatRoomTimestamps['room-a'], 7);
    expect(request.chatRoomTimestamps['room-b'], 2);
  });

  test('3. respondTo returns only messages newer than requested timestamp', () async {
    await messageRepo.saveMessage(_msg('old', 'room-a', 2));
    await messageRepo.saveMessage(_msg('boundary', 'room-a', 3));
    await messageRepo.saveMessage(_msg('new', 'room-a', 5));

    // afterLamportTs: 3 means strictly greater than 3
    final request = SyncRequest(chatRoomTimestamps: {'room-a': 3});
    final response = await syncHistory.respondTo(request);

    expect(response.messages.length, 1);
    expect(response.messages.first.id, 'new');
  });

  test('4. respondTo with empty request returns empty response', () async {
    await messageRepo.saveMessage(_msg('m1', 'room-a', 1));

    final request = SyncRequest(chatRoomTimestamps: {});
    final response = await syncHistory.respondTo(request);
    expect(response.messages, isEmpty);
  });
}
