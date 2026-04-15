import 'package:get_it/get_it.dart';
import 'package:domain/domain.dart';
import 'package:crypto_layer/crypto_layer.dart';
import 'package:data/data_lib.dart';
import 'package:transport/transport_package.dart';

final getIt = GetIt.instance;

Future<void> setupServiceLocator() async {
  // Crypto services
  getIt.registerLazySingleton<IdentityGenerator>(() => IdentityService());
  getIt.registerLazySingleton<MessageEncryptor>(() => EncryptionService());
  getIt.registerLazySingleton<MessageSigner>(() => SigningService());
  getIt.registerLazySingleton<SessionKeyDeriver>(() => KeyExchangeService());

  // Repositories
  getIt.registerLazySingleton<MessageRepository>(() => HiveMessageRepository());
  getIt.registerLazySingleton<PeerRepository>(() => HivePeerRepository());
  getIt.registerLazySingleton<IdentityRepository>(() => HiveIdentityRepository());
  getIt.registerLazySingleton<ChatRoomRepository>(() => HiveChatRoomRepository());

  // Lamport clock — singleton (one per device)
  getIt.registerLazySingleton<LamportClock>(() => LamportClock());

  // Transport — BLE only for Phase 5
  getIt.registerLazySingleton<BleTransport>(
    () => BleTransport(myDeviceName: 'LocalMesh'),
  );
  getIt.registerLazySingleton<TransportManager>(
    () => TransportManager([getIt<BleTransport>()]),
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
}
