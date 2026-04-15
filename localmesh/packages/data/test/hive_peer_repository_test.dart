import 'package:test/test.dart';
import 'package:domain/domain.dart';
import 'package:data/data_lib.dart';
import 'test_helpers.dart';

Peer makePeer(String id, {bool isTrusted = false}) => Peer(
      id: id,
      displayName: 'Test $id',
      signingPublicKey: const [1, 2, 3],
      encryptionPublicKey: const [4, 5, 6],
      lastSeen: 0,
      isConnected: false,
      isTrusted: isTrusted,
    );

void main() {
  late HivePeerRepository repo;

  setUpAll(setupHiveForTest);
  tearDownAll(tearDownHive);

  setUp(() {
    repo = HivePeerRepository();
  });

  tearDown(HiveLocalDataSource.clearAll);

  test('save and retrieve peer by id — fingerprints/ids match', () async {
    final peer = makePeer('peer-1');
    await repo.savePeer(peer);
    final retrieved = await repo.getPeerById('peer-1');
    expect(retrieved, isNotNull);
    expect(retrieved!.id, equals('peer-1'));
    expect(retrieved.displayName, equals('Test peer-1'));
    expect(retrieved.signingPublicKey, equals([1, 2, 3]));
    expect(retrieved.encryptionPublicKey, equals([4, 5, 6]));
  });

  test('retrieved peer always has isConnected == false (not persisted)',
      () async {
    final peer = makePeer('peer-2');
    await repo.savePeer(peer);
    final retrieved = await repo.getPeerById('peer-2');
    expect(retrieved!.isConnected, isFalse);
  });

  test(
      'after updatePeerConnectionStatus(id, true), getPeerById returns isConnected == true',
      () async {
    final peer = makePeer('peer-3');
    await repo.savePeer(peer);
    await repo.updatePeerConnectionStatus('peer-3', true);
    final retrieved = await repo.getPeerById('peer-3');
    expect(retrieved!.isConnected, isTrue);
  });

  test('getConnectedPeers returns only peers marked connected', () async {
    final p1 = makePeer('conn-1');
    final p2 = makePeer('conn-2');
    final p3 = makePeer('conn-3');
    await repo.savePeer(p1);
    await repo.savePeer(p2);
    await repo.savePeer(p3);

    await repo.updatePeerConnectionStatus('conn-1', true);
    await repo.updatePeerConnectionStatus('conn-3', true);

    final connected = await repo.getConnectedPeers();
    final ids = connected.map((p) => p.id).toSet();
    expect(ids, equals({'conn-1', 'conn-3'}));
    expect(connected.every((p) => p.isConnected), isTrue);
  });

  test('getTrustedPeers returns only peers with isTrusted == true', () async {
    await repo.savePeer(makePeer('trust-1', isTrusted: true));
    await repo.savePeer(makePeer('trust-2', isTrusted: false));
    await repo.savePeer(makePeer('trust-3', isTrusted: true));

    final trusted = await repo.getTrustedPeers();
    final ids = trusted.map((p) => p.id).toSet();
    expect(ids, equals({'trust-1', 'trust-3'}));
    expect(trusted.every((p) => p.isTrusted), isTrue);
  });

  test('removePeer deletes peer and removes from connected set', () async {
    final peer = makePeer('remove-1');
    await repo.savePeer(peer);
    await repo.updatePeerConnectionStatus('remove-1', true);

    // Peer is connected before removal
    final before = await repo.getConnectedPeers();
    expect(before.any((p) => p.id == 'remove-1'), isTrue);

    await repo.removePeer('remove-1');

    // getPeerById returns null
    expect(await repo.getPeerById('remove-1'), isNull);

    // getAllPeers no longer includes it
    final all = await repo.getAllPeers();
    expect(all.any((p) => p.id == 'remove-1'), isFalse);

    // getConnectedPeers no longer includes it
    final connected = await repo.getConnectedPeers();
    expect(connected.any((p) => p.id == 'remove-1'), isFalse);
  });
}
