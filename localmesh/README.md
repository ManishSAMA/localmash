# localmesh

## Local toolchain helper

This repo can be built with the checked-in helper script even if `flutter`,
`dart`, or `java` are not on your shell `PATH`.

Examples:

```sh
./tool/with-local-android-env.sh flutter analyze
./tool/with-local-android-env.sh ./android/gradlew -p android :app:assembleDebug
```

Defaults used by the helper:

- `FLUTTER_SDK=/home/Manu/Software/Flutter_SDK/flutter`
- `JAVA_HOME=/home/Manu/.antigravity/extensions/redhat.java-1.12.0-linux-x64/jre/17.0.4.1-linux-x86_64`

You can override either path per shell session before running it.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
