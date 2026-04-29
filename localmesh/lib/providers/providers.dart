import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domain/domain.dart';
import 'package:transport/transport_package.dart';
import '../controllers/message_controller.dart';
import '../di/service_locator.dart';

// ── Repository providers ──
final messageRepoProvider = Provider<MessageRepository>(
  (ref) => getIt<MessageRepository>(),
);
final peerRepoProvider = Provider<PeerRepository>(
  (ref) => getIt<PeerRepository>(),
);
final identityRepoProvider = Provider<IdentityRepository>(
  (ref) => getIt<IdentityRepository>(),
);

// ── Identity state ──
final currentIdentityProvider = FutureProvider<LocalMeshIdentity?>(
  (ref) async => ref.read(identityRepoProvider).getIdentity(),
);

// ── Transport ──
final transportManagerProvider = Provider<TransportManager>(
  (ref) => getIt<TransportManager>(),
);

// NOT autoDispose — losing these drops the mesh connection
final peerEventsProvider = StreamProvider<PeerEvent>(
  (ref) => ref.read(transportManagerProvider).peerEvents,
);

final incomingDataProvider = StreamProvider<TransportPayload>(
  (ref) => ref.read(transportManagerProvider).incomingData,
);

// ── Connected peer list ──
final connectedPeersProvider = FutureProvider<List<Peer>>(
  (ref) async {
    ref.watch(peerEventsProvider); // refresh fast on transport connect/disconnect
    ref.watch(peerRepositoryRevisionProvider); // refresh after repo writes complete
    return ref.read(peerRepoProvider).getConnectedPeers();
  },
);

// ── Chat messages for a peer ──
final chatMessagesProvider =
    FutureProvider.family<List<LocalMeshMessage>, String>(
  (ref, peerId) async {
    ref.watch(incomingDataProvider); // refresh fast on transport data
    ref.watch(messageRepositoryRevisionProvider); // refresh after repo writes complete
    return ref.read(messageRepoProvider).getMessagesForChat(peerId);
  },
);

// ── MessageController ──
final messageControllerProvider = FutureProvider<MessageController>(
  (ref) => getIt.getAsync<MessageController>(),
);

// Convenience sync accessor — only safe after MessageController is resolved
final messageControllerSyncProvider = Provider<MessageController>(
  (ref) => getIt<MessageController>(),
);

final peerRepositoryRevisionProvider = StreamProvider<int>(
  (ref) async* {
    final ctrl = await getIt.getAsync<MessageController>();
    yield* ctrl.peerRevisions;
  },
);

final messageRepositoryRevisionProvider = StreamProvider<int>(
  (ref) async* {
    final ctrl = await getIt.getAsync<MessageController>();
    yield* ctrl.messageRevisions;
  },
);

// ── Decrypted message stream — triggers chat UI updates ──
final decryptedMessagesProvider = StreamProvider<DecryptedMessage>(
  (ref) async* {
    final ctrl = await getIt.getAsync<MessageController>();
    yield* ctrl.decryptedMessages;
  },
);

// ── Use case providers ──
final createIdentityProvider = Provider<CreateIdentity>(
  (ref) => getIt<CreateIdentity>(),
);

final sendMessageProvider = Provider<SendMessage>(
  (ref) => getIt<SendMessage>(),
);

// ── Async transport errors (e.g. BLE advertise failure after start()) ──
final transportErrorsProvider = StreamProvider<String>(
  (ref) => ref.read(transportManagerProvider).transportErrors,
);
