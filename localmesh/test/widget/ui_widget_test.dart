import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:domain/domain.dart';
import 'package:localmesh/providers/providers.dart';
import 'package:localmesh/screens/identity_setup_screen.dart';
import 'package:localmesh/screens/network_health_screen.dart';
import 'package:localmesh/widgets/chat_message_row.dart';
import 'package:localmesh/widgets/mesh_topology_canvas.dart';
import 'package:localmesh/widgets/signal_strength_bars.dart';
import 'package:transport/transport_package.dart';

// ── Fakes for T5.1 ───────────────────────────────────────────────────────────

class _MemIdentityRepo implements IdentityRepository {
  LocalMeshIdentity? _id;

  @override
  Future<void> deleteIdentity() async => _id = null;

  @override
  Future<LocalMeshIdentity?> getIdentity() async => _id;

  @override
  Future<bool> hasIdentity() async => _id != null;

  @override
  Future<void> saveIdentity(LocalMeshIdentity identity) async => _id = identity;
}

class _QuickIdentityGen implements IdentityGenerator {
  @override
  Future<String> computeFingerprint(List<int> signingPublicKey) async =>
      signingPublicKey.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  Future<LocalMeshIdentity> generate(String displayName) async {
    final fp = await computeFingerprint(List.filled(32, 7));
    return LocalMeshIdentity(
      displayName: displayName,
      signingPublicKey: List.filled(32, 7),
      signingPrivateKey: List.filled(64, 8),
      encryptionPublicKey: List.filled(32, 9),
      encryptionPrivateKey: List.filled(32, 10),
      fingerprint: fp,
    );
  }
}

// ── Fake repo for T5.4 ───────────────────────────────────────────────────────

class _EmptyMessageRepo implements MessageRepository {
  @override
  Future<void> deleteMessage(String id) async {}

  @override
  Future<LocalMeshMessage?> getMessageById(String id) async => null;

  @override
  Future<int> getHighestLamportTsForChat(String chatRoomId) async => 0;

  @override
  Future<List<LocalMeshMessage>> getMessagesForChat(
    String chatRoomId, {
    int? afterLamportTs,
    int limit = 100,
  }) async =>
      [];

  @override
  Future<bool> hasMessage(String id) async => false;

  @override
  Future<void> saveMessage(LocalMeshMessage message) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('T5 widget tests', () {
    testWidgets('T5.1 IdentitySetupScreen — name field and generate control',
        (tester) async {
      final repo = _MemIdentityRepo();
      final create = CreateIdentity(
        generator: _QuickIdentityGen(),
        repository: repo,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            createIdentityProvider.overrideWithValue(create),
          ],
          child: const MaterialApp(
            home: IdentitySetupScreen(),
          ),
        ),
      );

      expect(find.text('LOCAL_MESH'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'TestUser');
      await tester.tap(find.text('GENERATE IDENTITY'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('GENERATING'), findsWidgets);
      expect(await repo.hasIdentity(), isTrue);
    });

    testWidgets('T5.2 ChatMessageRow — mine vs theirs layout', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ChatMessageRow(
                  isMine: false,
                  plaintext: 'Hello mesh',
                  timeLabel: '09:42Z',
                  senderLabel: 'NODE_ALPHA',
                  hopCount: 2,
                ),
                ChatMessageRow(
                  isMine: true,
                  plaintext: 'Ack',
                  timeLabel: '09:43Z',
                  hopCount: 0,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Hello mesh'), findsOneWidget);
      expect(find.text('Ack'), findsOneWidget);
      expect(find.text('VIA 2 HOPS'), findsOneWidget);
      expect(find.text('DIRECT'), findsNothing);
    });

    testWidgets('T5.3 MeshTopologyCanvas — renders topology paint', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MeshTopologyCanvas(peers: []),
            ),
          ),
        ),
      );
      expect(find.byType(MeshTopologyCanvas), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('T5.4 NetworkHealthBody — diagnostics sections', (tester) async {
      final mock = MockTransport(peerId: 'device-a', displayName: 'A');
      await mock.start();
      final manager = TransportManager([mock]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transportManagerProvider.overrideWithValue(manager),
            allPeersProvider.overrideWith((ref) async => []),
            peerEventsProvider.overrideWith((ref) => const Stream<PeerEvent>.empty()),
            incomingDataProvider.overrideWith(
              (ref) => const Stream<TransportPayload>.empty(),
            ),
            messageRepoProvider.overrideWithValue(_EmptyMessageRepo()),
            batterySaverProvider.overrideWith((ref) => false),
          ],
          child: const MaterialApp(
            home: Scaffold(body: NetworkHealthBody()),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.textContaining('DIAGNOSTICS_ACTIVE'), findsOneWidget);
      expect(find.textContaining('LATENCY_PER_HOP'), findsOneWidget);
      expect(find.textContaining('ROUTING_EVENTS_LOG'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('TRANSPORTS'),
        400,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('TRANSPORTS'), findsOneWidget);
      expect(find.textContaining('MOCK'), findsOneWidget);
    });

    testWidgets('T5.5 SignalStrengthBars — level renders bars', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SignalStrengthBars(level: 3),
          ),
        ),
      );
      expect(find.byType(SignalStrengthBars), findsOneWidget);
      // 4 bar containers in a row
      expect(find.byType(Container), findsWidgets);
    });

  });
}
