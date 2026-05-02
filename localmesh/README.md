# LocalMesh Flutter App

This directory contains the LocalMesh Flutter application and its local Dart packages. See the root [`README.md`](../README.md) for the full project overview.

## Layout

```text
lib/                    Flutter UI, providers, message controller, DI
packages/domain/        Pure Dart entities, repository interfaces, use cases
packages/crypto/        Identity, signing, encryption, session key derivation
packages/data/          Hive data source and repository implementations
packages/transport/     Transport manager, BLE, LAN, Wi-Fi Direct scaffold, mock
test/                   Widget and integration tests
```

## Local toolchain helper

This repo can be built with the checked-in helper script even if `flutter`, `dart`, or `java` are not on your shell `PATH`.

```sh
./tool/with-local-android-env.sh flutter analyze
./tool/with-local-android-env.sh flutter test
./tool/with-local-android-env.sh ./android/gradlew -p android :app:assembleDebug
```

Defaults used by the helper:

- `FLUTTER_SDK=/home/Manu/Software/Flutter_SDK/flutter`
- `JAVA_HOME=/home/Manu/.antigravity/extensions/redhat.java-1.12.0-linux-x64/jre/17.0.4.1-linux-x86_64`

Override either path in your shell before running the helper when needed.

## Common commands

```sh
flutter pub get
flutter run
flutter analyze
flutter test
flutter test packages/domain
flutter test packages/crypto
flutter test packages/data
flutter test packages/transport
```

## Runtime flow

The app initializes Hive, opens local boxes, creates or loads an identity, requests required BLE/location permissions, starts the LAN and BLE transports, then displays nearby untrusted peers and trusted chats. Messages are signed, encrypted, persisted locally, encoded with `WireCodec`, and sent through `TransportManager`.
