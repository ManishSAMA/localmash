import 'package:test/test.dart';
import 'package:domain/domain.dart';
import 'package:data/data_lib.dart';
import 'test_helpers.dart';

LocalMeshIdentity makeIdentity(String name, String fp) => LocalMeshIdentity(
      displayName: name,
      signingPublicKey: List.filled(32, 1),
      signingPrivateKey: List.filled(64, 2),
      encryptionPublicKey: List.filled(32, 3),
      encryptionPrivateKey: List.filled(32, 4),
      fingerprint: fp,
    );

void main() {
  late HiveIdentityRepository repo;

  setUpAll(setupHiveForTest);
  tearDownAll(tearDownHive);

  setUp(() {
    repo = HiveIdentityRepository();
  });

  tearDown(HiveLocalDataSource.clearAll);

  test('hasIdentity returns false on empty box', () async {
    expect(await repo.hasIdentity(), isFalse);
  });

  test('save then retrieve — getIdentity returns identity with matching fingerprint',
      () async {
    final identity = makeIdentity('Alice', 'fp-alice');
    await repo.saveIdentity(identity);

    expect(await repo.hasIdentity(), isTrue);
    final retrieved = await repo.getIdentity();
    expect(retrieved, isNotNull);
    expect(retrieved!.fingerprint, equals('fp-alice'));
    expect(retrieved.displayName, equals('Alice'));
  });

  test('save twice — getIdentity returns second identity (overwrite)', () async {
    final first = makeIdentity('Alice', 'fp-alice');
    final second = makeIdentity('Bob', 'fp-bob');

    await repo.saveIdentity(first);
    await repo.saveIdentity(second);

    final retrieved = await repo.getIdentity();
    expect(retrieved, isNotNull);
    expect(retrieved!.fingerprint, equals('fp-bob'));
    expect(retrieved.displayName, equals('Bob'));
  });

  test('deleteIdentity removes it — hasIdentity false, getIdentity null',
      () async {
    final identity = makeIdentity('Charlie', 'fp-charlie');
    await repo.saveIdentity(identity);
    expect(await repo.hasIdentity(), isTrue);

    await repo.deleteIdentity();

    expect(await repo.hasIdentity(), isFalse);
    expect(await repo.getIdentity(), isNull);
  });
}
