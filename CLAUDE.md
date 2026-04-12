# LocalMesh — Claude Code Project Instructions

also refer to SKILL.md

## What This Project Is

LocalMesh is a decentralized, offline-first mesh messaging app for Android built with Flutter/Dart. It enables smartphones to form peer-to-peer networks using BLE and Wi-Fi Direct for secure communication without internet, cell towers, or central servers. Messages route via a gossip/flooding protocol with multi-hop relay support.

This is a B.Tech capstone project. The demo scope is 5–10 active nodes. The architecture is intentionally modular to demonstrate clean engineering — don't simplify it into a monolith.

## Architecture Overview

```
┌──────────────────────────────────────────────────┐
│          PRESENTATION LAYER (Flutter UI)          │
│  Screens • Widgets • State Management (Riverpod) │
└───────────────────────┬──────────────────────────┘
                        │ Use Cases
┌───────────────────────┼──────────────────────────┐
│            DOMAIN LAYER (Pure Dart)              │
│  Entities • Repositories (abstract) • UseCases   │
│  MeshRouter • GossipEngine • MessageFormat       │
└───────────┬───────────┴───────────┬──────────────┘
            │                       │
┌───────────┴──────────┐  ┌────────┴──────────────────┐
│    DATA LAYER        │  │    TRANSPORT LAYER         │
│  Hive DB             │  │  ┌───────┐ ┌───────────┐  │
│  Repositories        │  │  │  BLE  │ │ WiFi Direct│  │
│  (concrete impl)     │  │  └───────┘ └───────────┘  │
└──────────────────────┘  └────────────────────────────┘
                                  │
                       ┌──────────┴────────────────────┐
                       │   CRYPTO LAYER                │
                       │   X25519 + AES-256-GCM        │
                       │   Ed25519 Signing             │
                       │   Identity Management         │
                       └───────────────────────────────┘
```

## Project Structure

```
localmesh/
├── android/                     # Android platform config + permissions
├── ios/                         # iOS platform config (future scope)
├── lib/                         # App entry point + DI wiring
│   ├── main.dart
│   └── di/                      # Dependency injection setup (get_it)
├── packages/
│   ├── domain/                  # Pure Dart — ZERO Flutter dependencies
│   │   ├── lib/
│   │   │   ├── entities/        # Message, Peer, Identity, ChatRoom
│   │   │   ├── repositories/    # Abstract interfaces only
│   │   │   ├── usecases/        # SendMessage, ReceiveMessage, SyncHistory
│   │   │   └── protocols/       # MeshRouter, GossipEngine
│   │   └── pubspec.yaml
│   ├── data/                    # Concrete implementations
│   │   ├── lib/
│   │   │   ├── repositories/    # HiveMessageRepo, HivePeerRepo
│   │   │   ├── datasources/     # HiveLocalDataSource
│   │   │   └── models/          # Hive adapters, serialization
│   │   └── pubspec.yaml         # depends on: domain, crypto, hive
│   ├── transport/               # Transport abstraction layer
│   │   ├── lib/
│   │   │   ├── transport.dart   # Abstract Transport interface
│   │   │   ├── transport_manager.dart
│   │   │   ├── ble/             # BleTransport implementation
│   │   │   ├── wifi_direct/     # WifiDirectTransport implementation
│   │   │   └── mock/            # MockTransport for testing
│   │   └── pubspec.yaml         # depends on: domain, flutter_reactive_ble, etc.
│   └── crypto/                  # All cryptographic operations
│       ├── lib/
│       │   ├── identity.dart    # KeyPair generation + LocalMeshIdentity
│       │   ├── encryption.dart  # AES-256-GCM encrypt/decrypt
│       │   └── key_exchange.dart # X25519 ECDH + HKDF-SHA256
│       └── pubspec.yaml         # depends on: domain, cryptography
├── test/                        # Integration tests
├── pubspec.yaml                 # Root: depends on all packages
└── analysis_options.yaml
```

## Dependency Rules — STRICTLY ENFORCED

These are hard rules. Violations break the architecture.

| Package   | Can Depend On          | CANNOT Depend On                    | Flutter Allowed? |
|-----------|------------------------|-------------------------------------|------------------|
| domain    | Nothing (pure Dart)    | data, transport, crypto, Flutter    | NO               |
| crypto    | domain                 | data, transport, Flutter            | NO               |
| data      | domain, crypto         | transport, Flutter (except Hive)    | Minimal          |
| transport | domain, crypto         | data                                | Yes              |
| app (lib/)| All packages           | —                                   | Yes              |

**If you find yourself importing `package:flutter` in domain/ or crypto/, STOP. You are breaking the architecture.**

**If you find yourself importing `package:data` in transport/, STOP. Transport does not know about storage.**

**If you find yourself importing `package:transport` in data/, STOP. Storage does not know about radios.**

## Behavioral Rules

- Do what has been asked; nothing more, nothing less.
- ALWAYS read a file before editing it.
- NEVER create files unless they are necessary for the current task.
- NEVER proactively create documentation files (*.md) or README files unless explicitly asked.
- NEVER put source files in the project root — use the package directories.
- NEVER commit secrets, credentials, or .env files.
- Prefer editing existing files over creating new ones.
- Run `flutter analyze` after making changes to catch import violations.
- Run `flutter test` in the relevant package after implementing anything.

## Key Technical Decisions

### State Management: Riverpod
Use `flutter_riverpod` (not `provider`, not `bloc`, not `getx`). Providers depend on domain use cases, never on data or transport directly.

### Local Storage: Hive
Use `hive` and `hive_flutter`. Encrypted boxes for identity/keys. Regular boxes for messages and peers. Generate type adapters with `hive_generator`.

### BLE: flutter_reactive_ble
Use `flutter_reactive_ble` for Bluetooth Low Energy. It provides reactive streams for scanning, connecting, and data transfer. Do NOT use `flutter_blue_plus` or `flutter_nearby_connections`.

### Wi-Fi Direct: flutter_p2p_connection
Use `flutter_p2p_connection` for Wi-Fi Direct peer-to-peer. Falls back gracefully if Wi-Fi Direct is unavailable.

### Cryptography: cryptography (dart package)
Use the `cryptography` dart package (pure Dart, no native dependencies). It provides X25519, Ed25519, AES-GCM, and HKDF. Do NOT use `pointycastle` — it's lower-level and harder to use correctly.

### Serialization: Custom binary TLV
Messages on the wire use a compact Type-Length-Value binary encoding, NOT JSON. JSON is too verbose for BLE's ~247-byte MTU. Use `dart:typed_data` (ByteData, Uint8List) for serialization.

### DI: get_it + injectable
Use `get_it` as the service locator. Register all implementations in `lib/di/`. The domain layer uses constructor injection via abstract interfaces.

## The Transport Interface Contract

Every transport (BLE, Wi-Fi Direct, Mock, future TCP/LoRa) MUST implement this interface:

```dart
abstract class Transport {
  String get name;
  Future<void> start();
  Future<void> stop();
  Stream<PeerEvent> get peerEvents;
  Stream<TransportPayload> get incomingData;
  Future<void> sendTo(String peerId, Uint8List data);
  Future<void> broadcast(Uint8List data);
  TransportState get state;
}
```

The `TransportManager` aggregates multiple transports and presents a single merged stream to the domain layer. The domain layer NEVER knows which radio is active.

## The Message Schema

Every message on the mesh uses this envelope:

```dart
class LocalMeshMessage {
  final String id;           // UUIDv4
  final int version;         // Protocol version (1)
  final MessageType type;    // TEXT, FILE_CHUNK, LOCATION, SYNC_REQUEST, SYNC_RESPONSE, PEER_ANNOUNCE
  final String senderId;     // Ed25519 public key fingerprint (first 16 hex chars of SHA-256)
  final String recipientId;  // Recipient fingerprint, or '*' for broadcast
  final Uint8List payload;   // AES-256-GCM encrypted content
  int hopCount;              // Starts at 0, incremented per relay
  final int ttl;             // Max hops (default: 5)
  final int lamportTs;       // Lamport logical timestamp
  final Uint8List signature; // Ed25519 signature over [id + senderId + payload + ttl + lamportTs]
  final int createdAt;       // Unix epoch ms (advisory)
}
```

Do NOT change this schema without explicit instruction. Do NOT add fields. Do NOT use JSON for wire format.

## The Gossip Router Algorithm

```
onMessageReceived(message, fromPeerId):
  1. if message.id in seenSet → drop, return
  2. if not verify(message.signature, message.senderId) → drop, return
  3. seenSet.add(message.id)
  4. if message.recipientId == myId OR recipientId == '*':
       decrypt payload, deliver to UI, persist to Hive
  5. if message.hopCount < message.ttl:
       message.hopCount += 1
       broadcast to all connected peers EXCEPT fromPeerId
```

The seen-set uses an LRU cache (last 10,000 message IDs). This is sufficient for demo scale.

## Common Pitfalls

### BLE MTU Limits
BLE's negotiated MTU is typically 247 bytes after headers (~244 usable). Messages larger than this MUST be chunked by the transport layer before sending, and reassembled on receipt. The domain layer should not care about MTU — chunking is a transport concern.

### flutter_reactive_ble Permissions
On Android 12+ (API 31+), you need BLUETOOTH_SCAN, BLUETOOTH_CONNECT, BLUETOOTH_ADVERTISE permissions AND they must be requested at runtime, not just declared in the manifest. Also need ACCESS_FINE_LOCATION for BLE scanning on Android 10+.

### Hive Box Initialization
Hive boxes MUST be opened before use. Open all boxes in main.dart during app initialization, before runApp(). Don't open boxes lazily in repository constructors — it causes race conditions.

### Riverpod Provider Disposal
Transport streams (peerEvents, incomingData) are long-lived. Use `StreamProvider.autoDispose` carefully — if the provider disposes while the app is still listening, you'll lose the mesh connection. Prefer non-autoDispose for transport-level providers.

### Wi-Fi Direct Group Owner
In Wi-Fi Direct, one device must be the Group Owner (GO). The GO acts as a soft AP. If both devices try to be GO, the connection fails. Use `flutter_p2p_connection`'s automatic GO negotiation and don't force roles.

### Testing Without Phones
Build `MockTransport` first. It should simulate:
- Multiple virtual nodes in a single process
- Configurable latency per link
- Random disconnections
- Message delivery between nodes via in-memory queues

This lets you test the entire gossip router, sync protocol, and message pipeline with `flutter test` — no phones needed. Write mock tests BEFORE touching real BLE code.

### Lamport Timestamp Ordering
Lamport timestamps provide causal ordering, not wall-clock ordering. Two messages from different nodes with the same Lamport timestamp are concurrent — break ties deterministically using the message ID (lexicographic comparison). Never use `DateTime.now()` for ordering — it's unreliable across devices without NTP.

## Android Permissions (AndroidManifest.xml)

```xml
<!-- BLE -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

<!-- Wi-Fi Direct -->
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" />

<!-- General -->
<uses-permission android:name="android.permission.INTERNET" />
```

Request BLUETOOTH_SCAN, BLUETOOTH_CONNECT, BLUETOOTH_ADVERTISE, ACCESS_FINE_LOCATION, and NEARBY_WIFI_DEVICES at runtime using `permission_handler`.

## Build & Test Commands

```bash
# Run all tests across all packages
flutter test

# Run tests for a specific package
cd packages/domain && flutter test
cd packages/crypto && flutter test

# Analyze for import violations and lint errors
flutter analyze

# Run on a connected Android device
flutter run

# Build release APK
flutter build apk --release
```

## Phase Order

Build in this order. Do not skip ahead.

1. **Scaffold** — Create the package structure. All pubspec.yaml files. Empty interfaces. It must compile with `flutter analyze` passing.
2. **Crypto** — Key generation, encryption, signing. Full unit test coverage. No Flutter deps.
3. **Domain** — Entities, MeshRouter, repository interfaces, use cases. Full unit test coverage. No Flutter deps.
4. **Transport** — Transport interface, MockTransport, BleTransport. Test MeshRouter against MockTransport.
5. **Data + UI** — Hive repositories, chat screen, Riverpod wiring. 2-phone BLE test.
6. **Multi-hop + Sync** — 3-phone relay, sync protocol, Wi-Fi Direct transport, network health UI.