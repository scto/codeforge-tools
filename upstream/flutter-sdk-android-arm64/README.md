# Flutter for Android ARM64 hosts

An unofficial Flutter SDK build for Android ARM64 hosts, including Termux. It lets you run Flutter and Dart commands on the device and build Android apps for `armeabi-v7a`, `arm64-v8a`, and `x86_64`.

This SDK is based on Flutter 3.47.8 and Dart 3.13.7. It is intended to run on an Android ARM64 host and it does not provide host support for other Android architectures or desktop operating systems.

## Download and install

1. From the repository's **Releases** page, download `flutter-android-arm64.tar.xz`.
2. Extract it to a directory you can write to. The archive creates a `flutter/` directory:

   ```sh
   mkdir -p "$HOME/opt/flutter-android-arm64"
   tar -xJf "$HOME/Downloads/flutter-android-arm64.tar.xz" \
     -C "$HOME/opt/flutter-android-arm64"
   ```

3. Add Flutter to your current shell's `PATH`:

   ```sh
   export FLUTTER_ROOT="$HOME/opt/flutter-android-arm64/flutter"
   export PATH="$FLUTTER_ROOT/bin:$PATH"
   ```

   To make these settings persist, add the two `export` lines to your shell startup file, such as `~/.bashrc` or `~/.zshrc`.

4. Confirm the commands use this SDK:

   ```sh
   flutter --version
   dart --version
   ```

## Build an Android app

From the root of a Flutter project, fetch its packages and build a release APK for all three supported Android ABIs:

```sh
flutter pub get
flutter build apk --release \
  --target-platform android-arm,android-arm64,android-x64
```

Flutter writes the APKs to `build/app/outputs/flutter-apk/`.

For a debug APK, use `--debug` instead of `--release`.

## Licenses

The project files are licensed under BSD-3-Clause; see [LICENSE](LICENSE). The SDK also contains software under other licenses, so keep all license and notice files included with it when redistributing. This is an unofficial community build and is not endorsed by Google or the Flutter project.
