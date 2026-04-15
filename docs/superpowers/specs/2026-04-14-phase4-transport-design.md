# Phase 4 — Transport Package Design

**Date:** 2026-04-14  
**Status:** Approved

---

## Goal

Implement the `transport` package: a pluggable transport abstraction with a fully functional `MockTransport` for in-process mesh simulation, a `TransportManager` that aggregates multiple transports, a binary `WireCodec` for on-wire serialization, and stub implementations for `BleTransport` / `WifiDirectTransport`. Prove the gossip router works via a 5-node simulated mesh — no phones.

---

## Scope

Build in this order:

1. `pubspec.yaml` — add `flutter_reactive_ble`, `uuid`
2. `lib/transport.dart` — extend interface with `connectedPeers`, `hasPeer`, `TransportException`
3. `lib/mock/mock_transport.dart` — full `MockNetwork` + `MockTransport` impl
4. `lib/transport_manager.dart` — constructor-injected, merges streams, `connectedPeers`, `dispose`
5. `lib/ble/ble_transport.dart` — Phase 5 stub, descriptive `UnimplementedError`
6. `lib/wifi_direct/wifi_direct_transport.dart` — Phase 6 stub
7. `lib/wire_codec.dart` — TLV binary encoder/decoder
8. `lib/transport_lib.dart` — new barrel (delete `transport_package.dart`)
9. Tests (unit + integration)

---

## Architecture

### Transport Interface

```
abstract class Transport
  name: String
  state: TransportState
  start() / stop()
  peerEvents: Stream<PeerEvent>
  incomingData: Stream<TransportPayload>
  connectedPeers: List<String>        ← NEW vs scaffold
  hasPeer(peerId): bool               ← NEW vs scaffold
  sendTo(peerId, data) / broadcast(data)
```

`TransportException(transportName, message)` replaces silent failures.

### MockNetwork + MockTransport

`MockNetwork` is a shared registry. Each `MockTransport` represents one virtual node. Topology is wired via `network.link(a, b)` (bidirectional). Delivery honors configurable `latency` and `dropRate`. `MockTransport` notifies peer events to both sides on link/unlink.

### TransportManager

Constructor-injected `List<Transport>`. On `start()`, subscribes to all transport streams via `StreamGroup.merge` before starting each transport. Routes `sendTo` to the first transport that `hasPeer`. `broadcast` is best-effort across all transports.

### WireCodec (TLV binary)

Big-endian. Format:

```
version(1) | type(1) | id_len(2) | id | sender_len(2) | sender |
recipient_len(2) | recipient | payload_len(4) | payload |
hopCount(1) | ttl(1) | lamportTs(8) | sig_len(2) | sig | createdAt(8)
```

**Type adaptations vs `LocalMeshMessage`:**
- `payload: List<int>` → `setRange` accepts `List<int>` directly on a `Uint8List` target. No explicit conversion needed unless linter complains.
- `signature: List<int>` → same.
- `MessageType` enum: index-based round-trip (`MessageType.values[typeIdx]`) is safe regardless of naming.
- Decoded `bytes.sublist(...)` returns `Uint8List` which satisfies `List<int>` — assigns directly to entity fields.

---

## Test Plan

### Unit: `test/wire_codec_test.dart` (6 tests)
- Round-trip encode→decode
- Empty payload
- Empty signature
- 10 KB payload
- All 6 `MessageType` variants
- Negative `lamportTs`

### Unit: `test/mock_transport_test.dart` (10 tests)
- `start()` registers, state → running
- `stop()` unregisters, state → idle
- Send before start throws `TransportException`
- Linked pair: A sends to B → B receives
- Broadcast delivers to all linked peers
- `link()` fires `PeerEvent(connected: true)` on both sides
- `unlink()` fires `PeerEvent(connected: false)` on both sides
- `dropRate=1.0` → silent drop
- `latency=50ms` → measurable delay
- `connectedPeers` reflects current links

### Unit: `test/transport_manager_test.dart` (7 tests)
- Merges peer events from 2 transports
- Merges incoming data from 2 transports
- `sendTo` routes via transport with peer
- `sendTo` throws if no transport reaches peer
- `broadcast` calls all transports
- `stop()` stops all transports
- `connectedPeers` = union across transports

### Integration: `test/integration/mesh_simulation_test.dart`
5-node line topology A–B–C–D–E. A sends encrypted text to E. Assertions:
- E receives exactly 1 message
- `hopCount == 4`
- E decrypts plaintext successfully
- A does NOT deliver to itself (self-origin drop)

### Integration: `test/integration/dedup_test.dart`
Star topology (B=hub, A/C/D/E=leaves). A broadcasts. Assertions:
- C, D, E each receive exactly 1 message (LRU dedup prevents duplicates)

---

## Key Adaptations from Spec

| Item | Spec | Actual | Resolution |
|---|---|---|---|
| `MessageType` | `.TEXT` | `.text` | Use lowercase in tests |
| `IdentityService` | `.generateIdentity(name)` | `.generate(name)` | Use `.generate` in tests |
| `payload`/`signature` | `Uint8List` | `List<int>` | `setRange` works; no cast needed |
| Barrel file | `transport_lib.dart` | `transport_package.dart` | Create `transport_lib.dart`, delete old barrel |
| Package name | `transport` | `transport` | Import `package:transport/transport_lib.dart` — filename ≠ package name |

---

## Dependency Rules

- `transport` depends on: `domain`, `crypto_layer`, `async`, `flutter_reactive_ble`, `uuid`
- `transport` NEVER imports `data`
- `MockTransport` is pure Dart — testable with `flutter test` (package has Flutter dep via `flutter_reactive_ble`)

---

## Acceptance Criteria

```bash
cd packages/transport && flutter pub get
flutter analyze          # zero issues
flutter test             # all tests pass
grep -r "package:data" packages/transport/lib/   # empty
```
