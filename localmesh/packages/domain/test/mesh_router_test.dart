import 'package:test/test.dart';
import 'package:domain/domain.dart';
import 'fakes.dart';

LocalMeshMessage makeMessage({
  String id = 'msg-1',
  String senderId = 'peer-a',
  String recipientId = 'me',
  int hopCount = 0,
  int ttl = 5,
  List<int>? signature,
}) {
  return LocalMeshMessage(
    id: id,
    version: 1,
    type: MessageType.text,
    senderId: senderId,
    recipientId: recipientId,
    payload: const [1, 2, 3],
    hopCount: hopCount,
    ttl: ttl,
    lamportTs: 1,
    signature: signature ?? const [1, 2, 3, 4],
    createdAt: 0,
  );
}

MeshRouter makeRouter({
  String myFingerprint = 'me',
  Map<String, List<int>>? peerKeys,
  int maxSeenMessages = 10000,
}) {
  final keys = peerKeys ?? {'peer-a': const [1, 2, 3]};
  return MeshRouter(
    signer: FakeMessageSigner(),
    myFingerprint: myFingerprint,
    lookupSenderPublicKey: (id) async => keys[id],
    maxSeenMessages: maxSeenMessages,
  );
}

void main() {
  group('MeshRouter', () {
    test('1. drops duplicate messages', () async {
      final router = makeRouter();
      final msg = makeMessage();

      final first = await router.handleIncoming(msg);
      expect(first.action, isNot(RouterAction.drop));

      final second = await router.handleIncoming(msg);
      expect(second.action, RouterAction.drop);
      expect(second.reason, 'duplicate');
    });

    test('2. drops messages from self', () async {
      final router = makeRouter(myFingerprint: 'me');
      final msg = makeMessage(senderId: 'me');

      final result = await router.handleIncoming(msg);
      expect(result.action, RouterAction.drop);
      expect(result.reason, 'self-origin');
    });

    test('3. drops messages from unknown senders', () async {
      final router = makeRouter(peerKeys: {}); // empty lookup
      final msg = makeMessage(senderId: 'unknown');

      final result = await router.handleIncoming(msg);
      expect(result.action, RouterAction.drop);
      expect(result.reason, 'unknown-sender');
    });

    test('4. drops messages with invalid signature', () async {
      final router = makeRouter();
      final msg = makeMessage(signature: const [9, 9, 9, 9]);

      final result = await router.handleIncoming(msg);
      expect(result.action, RouterAction.drop);
      expect(result.reason, 'invalid-signature');
    });

    test('5. delivers and forwards message addressed to me with hopCount < ttl', () async {
      final router = makeRouter(myFingerprint: 'me');
      final msg = makeMessage(recipientId: 'me', hopCount: 0, ttl: 5);

      final result = await router.handleIncoming(msg);
      expect(result.action, RouterAction.deliverAndForward);
      expect(result.forwardMessage, isNotNull);
      expect(result.forwardMessage!.hopCount, 1);
    });

    test('6. delivers and forwards broadcast messages', () async {
      final router = makeRouter(myFingerprint: 'me');
      final msg = makeMessage(recipientId: '*', hopCount: 0, ttl: 5);

      final result = await router.handleIncoming(msg);
      expect(result.action, RouterAction.deliverAndForward);
      expect(result.forwardMessage!.hopCount, 1);
    });

    test('7. forwards only when message is not for me and TTL not exhausted', () async {
      final router = makeRouter(myFingerprint: 'me');
      final msg = makeMessage(
        senderId: 'peer-a',
        recipientId: 'peer-b',
        hopCount: 0,
        ttl: 5,
      );

      final result = await router.handleIncoming(msg);
      expect(result.action, RouterAction.forwardOnly);
      expect(result.forwardMessage!.hopCount, 1);
    });

    test('8. delivers only when TTL exhausted and message is for me', () async {
      final router = makeRouter(myFingerprint: 'me');
      final msg = makeMessage(recipientId: 'me', hopCount: 5, ttl: 5);

      final result = await router.handleIncoming(msg);
      expect(result.action, RouterAction.deliverOnly);
    });

    test('9. drops when TTL exhausted and message is not for me', () async {
      final router = makeRouter(myFingerprint: 'me');
      final msg = makeMessage(
        senderId: 'peer-a',
        recipientId: 'peer-b',
        hopCount: 5,
        ttl: 5,
      );

      final result = await router.handleIncoming(msg);
      expect(result.action, RouterAction.drop);
    });

    test('10. LRU eviction removes oldest entry when maxSeenMessages exceeded', () async {
      final router = makeRouter(maxSeenMessages: 5);

      // Fill seen set with 5 distinct messages (all forwarded to peer-b, valid)
      for (var i = 0; i < 5; i++) {
        await router.handleIncoming(
          makeMessage(id: 'msg-$i', recipientId: 'peer-b'),
        );
      }
      expect(router.seenCount, 5);

      // Push one more — msg-0 (oldest) should be evicted
      await router.handleIncoming(makeMessage(id: 'msg-5', recipientId: 'peer-b'));
      expect(router.seenCount, 5);

      // Re-send msg-0: should NOT be treated as duplicate (was evicted)
      final result = await router.handleIncoming(
        makeMessage(id: 'msg-0', recipientId: 'peer-b'),
      );
      expect(result.action, isNot(RouterAction.drop));
    });

    test('11. dedup set not polluted by messages with invalid signatures', () async {
      final router = makeRouter();
      const contested = 'contested-id';

      // Send with invalid signature — dropped, must NOT be marked seen
      final invalid = await router.handleIncoming(
        makeMessage(id: contested, signature: const [9, 9, 9, 9]),
      );
      expect(invalid.action, RouterAction.drop);
      expect(invalid.reason, 'invalid-signature');

      // Same ID with valid signature — must NOT be dropped as duplicate
      final valid = await router.handleIncoming(
        makeMessage(id: contested, signature: const [1, 2, 3, 4]),
      );
      expect(valid.action, isNot(RouterAction.drop));
    });
  });
}
