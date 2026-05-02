# LocalMesh

LocalMesh is an offline-first Flutter chat app for nearby devices. It creates a local identity, discovers peers over local transports, asks users to verify peer fingerprints before trusting them, and exchanges encrypted messages without depending on an internet service.

The Flutter app lives in [`localmesh/`](localmesh/). The code is split into small local Dart packages for domain logic, crypto, storage, and transport.

## What works today

- Identity setup with generated Ed25519 signing keys, X25519 encryption keys, and a short fingerprint.
- Permission flow for Bluetooth scan/connect/advertise and Android location requirements.
- Mesh startup from the home screen, including transport status and retry handling.
- Nearby peer discovery with provisional peers while key exchange/announce data is still arriving.
- Fingerprint verification before a peer is moved into the trusted chat list.
- One-to-one text chat through the mesh controller.
- Message signing, encryption, local persistence, Lamport timestamps, relay routing, and sync-on-connect.
- Network health screen showing active transports, trusted connected peers, and stored message count.

## Architecture

```text
localmesh/
|-- lib/                    Flutter app, screens, Riverpod providers, get_it DI
|-- packages/domain/        Pure Dart entities, repository interfaces, use cases, router
|-- packages/crypto/        Pure Dart identity, signing, encryption, key exchange
|-- packages/data/          Hive-backed repositories and adapters
|-- packages/transport/     Transport interface, manager, BLE, LAN, Wi-Fi Direct stub, mock
`-- test/                   App-level and integration tests
```

### App flow

1. `main.dart` initializes Hive, opens local boxes, sets up service registration, and starts the Riverpod app.
2. `AppRouter` checks for an identity, then required permissions, then routes to `HomeScreen`.
3. `HomeScreen` starts `TransportManager` and `MessageController`.
4. `MessageController` bridges transports to domain use cases:
   - incoming bytes are decoded by `WireCodec`;
   - peer announces update the peer repository;
   - text messages go through `ReceiveMessage`;
   - relay decisions come from `MeshRouter`;
   - sync requests replay missing history.
5. `ChatScreen` sends plaintext through `SendMessage`, which encrypts, signs, persists, and broadcasts the message envelope.

### Packages

- `domain`: immutable entities, repository contracts, `CreateIdentity`, `SendMessage`, `ReceiveMessage`, `SyncHistory`, `LamportClock`, and `MeshRouter`.
- `crypto_layer`: Ed25519 signing, X25519 session key derivation with HKDF-SHA256, AES-256-GCM encryption, and identity fingerprint generation.
- `data`: Hive implementations for messages, peers, identity, and chat rooms. The identity box is encrypted with a generated Hive AES key.
- `transport`: common `Transport` interface, `TransportManager`, custom wire codec, BLE transport, LAN transport, Wi-Fi Direct transport scaffold, and mock transport for tests.
- `app`: Flutter screens, Riverpod providers, and dependency wiring.

## Transports

The active app wiring currently registers LAN and BLE in `TransportManager`.

- `TcpLanTransport`: uses UDP broadcast for discovery and TCP on port `45678` for framed payloads on a shared network.
- `BleTransport`: scans and advertises a shared LocalMesh BLE service UUID, uses Android native GATT server support for the peripheral role, and chunks payloads for BLE transfer.
- `WifiDirectTransport`: present in the transport package and service locator, but not included in the active manager list yet.
- `MockTransport`: used by tests to simulate multi-node topologies.

## Security model

- Each device creates an Ed25519 signing key pair and an X25519 key pair.
- The peer fingerprint is the first 16 hex characters of `SHA-256(Ed25519 public key)`.
- Text payloads are encrypted with AES-256-GCM.
- Session keys are derived with X25519 plus HKDF-SHA256 over sorted peer fingerprints.
- Messages are signed with Ed25519 over canonical message fields.
- New peers are untrusted until the user verifies their displayed public-key fingerprint.

## Requirements

- Flutter SDK compatible with Dart `^3.11.3`.
- Java 17 for Android builds.
- Android devices need BLE support for the Bluetooth transport.

The repo includes a helper script for this local machine setup. It adds Flutter and Java to `PATH` for a single command:

```sh
cd localmesh
./tool/with-local-android-env.sh flutter --version
```

Defaults used by the helper:

- `FLUTTER_SDK=/home/Manu/Software/Flutter_SDK/flutter`
- `JAVA_HOME=/home/Manu/.antigravity/extensions/redhat.java-1.12.0-linux-x64/jre/17.0.4.1-linux-x86_64`

Override either variable before running the helper if your paths differ.

## Development

Install dependencies:

```sh
cd localmesh
flutter pub get
```

Run the app:

```sh
cd localmesh
flutter run
```

Build a debug Android APK with the local helper:

```sh
cd localmesh
./tool/with-local-android-env.sh ./android/gradlew -p android :app:assembleDebug
```

Analyze and test:

```sh
cd localmesh
flutter analyze
flutter test
flutter test packages/domain
flutter test packages/crypto
flutter test packages/data
flutter test packages/transport
```

## Android permissions

The Android manifest requests:

- Bluetooth scan, connect, and advertise permissions.
- Fine/coarse location for BLE scanning requirements on older Android versions.
- Wi-Fi state and nearby Wi-Fi device permissions for Wi-Fi Direct/LAN-adjacent work.
- Internet permission for socket-based LAN transport.

At runtime, the app blocks startup until Bluetooth scan/connect/advertise and location permissions are granted. Nearby Wi-Fi devices is requested opportunistically after the required BLE permissions.

## Notes

- The project is not a stock Flutter starter app; the default README content has been replaced with the actual LocalMesh structure.
- Some message types are modeled (`fileChunk`, `location`) but the current UI implements text chat.
- LAN startup errors are handled as non-fatal so BLE can still run when socket binding is unavailable.
