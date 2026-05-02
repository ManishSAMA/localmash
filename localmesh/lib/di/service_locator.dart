import 'package:get_it/get_it.dart';
import 'package:domain/domain.dart';
import 'package:crypto_layer/crypto_layer.dart';
import 'package:data/data_lib.dart';
import 'package:transport/transport_package.dart';
import '../controllers/message_controller.dart';

final getIt = GetIt.instance;

Future<void> setupServiceLocator() async {
  // Crypto services
  getIt.registerLazySingleton<IdentityGenerator>(() => IdentityService());
  getIt.registerLazySingleton<MessageEncryptor>(() => EncryptionService());
  getIt.registerLazySingleton<MessageSigner>(() => SigningService());
  getIt.registerLazySingleton<SessionKeyDeriver>(
    () => CachingSessionKeyDeriver(KeyExchangeService()),
  );

  // Repositories
  getIt.registerLazySingleton<MessageRepository>(() => HiveMessageRepository());
  getIt.registerLazySingleton<PeerRepository>(() => HivePeerRepository());
  getIt.registerLazySingleton<IdentityRepository>(
      () => HiveIdentityRepository());
  getIt.registerLazySingleton<ChatRoomRepository>(
      () => HiveChatRoomRepository());

  // Lamport clock — one per device
  getIt.registerLazySingleton<LamportClock>(() => LamportClock());

  // Transport
  getIt.registerLazySingleton<BleTransport>(
    () => BleTransport(myDeviceName: 'LocalMesh'),
  );
  getIt.registerLazySingleton<WifiDirectTransport>(
    () => WifiDirectTransport(myDeviceName: 'LocalMesh'),
  );
  getIt.registerLazySingleton<TcpLanTransport>(
    () => TcpLanTransport(myDeviceName: 'LocalMesh'),
  );
  getIt.registerLazySingleton<TransportManager>(
    () => TransportManager([
      getIt<TcpLanTransport>(),
      getIt<BleTransport>(),
    ]),
  );

  // Use cases
  getIt.registerFactory<CreateIdentity>(() => CreateIdentity(
        generator: getIt<IdentityGenerator>(),
        repository: getIt<IdentityRepository>(),
      ));

  getIt.registerFactory<SendMessage>(() => SendMessage(
        identityRepo: getIt<IdentityRepository>(),
        peerRepo: getIt<PeerRepository>(),
        messageRepo: getIt<MessageRepository>(),
        encryptor: getIt<MessageEncryptor>(),
        signer: getIt<MessageSigner>(),
        keyDeriver: getIt<SessionKeyDeriver>(),
        clock: getIt<LamportClock>(),
      ));

  // MeshRouter — needs identity fingerprint and peer key lookup.
  // Registered as async singleton; resolved lazily on first access.
  getIt.registerLazySingletonAsync<MeshRouter>(() async {
    final identity = await getIt<IdentityRepository>().getIdentity();
    if (identity == null) {
      throw StateError('Cannot create MeshRouter — no identity');
    }
    final peerRepo = getIt<PeerRepository>();
    return MeshRouter(
      signer: getIt<MessageSigner>(),
      myFingerprint: identity.fingerprint,
      lookupSenderPublicKey: (senderId) async {
        final peer = await peerRepo.getPeerById(senderId);
        return peer?.signingPublicKey;
      },
    );
  });

  getIt.registerFactoryAsync<ReceiveMessage>(() async => ReceiveMessage(
        router: await getIt.getAsync<MeshRouter>(),
        identityRepo: getIt<IdentityRepository>(),
        peerRepo: getIt<PeerRepository>(),
        messageRepo: getIt<MessageRepository>(),
        encryptor: getIt<MessageEncryptor>(),
        keyDeriver: getIt<SessionKeyDeriver>(),
        clock: getIt<LamportClock>(),
      ));

  getIt.registerFactory<SyncHistory>(() => SyncHistory(
        messageRepo: getIt<MessageRepository>(),
      ));

  // MessageController — singleton; depends on async MeshRouter.
  getIt.registerLazySingletonAsync<MessageController>(() async =>
      MessageController(
        transportManager: getIt<TransportManager>(),
        receiveMessage: await getIt.getAsync<ReceiveMessage>(),
        sendMessage: getIt<SendMessage>(),
        syncHistory: getIt<SyncHistory>(),
        peerRepo: getIt<PeerRepository>(),
        identityRepo: getIt<IdentityRepository>(),
        signer: getIt<MessageSigner>(),
        identityGenerator: getIt<IdentityGenerator>(),
      ));
}
