# Bumble E2E (Flutter)

Client-side (end-to-end) file encryption/decryption. The UI is kept as-is; the main improvement in this package is **production-safe file export**:

- **Web:** download via browser (no extra packages).
- **Android (v1):** **share-only** (writes to temp + opens system share sheet via `share_plus`).
- Other IO platforms: share as well (safe default).

## What changed vs your original lib/main.dart

- Removed `universal_html` (it breaks mobile builds) and replaced it with a conditional exporter in `lib/platform/`.
- File export now works on **Android** (share sheet) and **Web** (download).
- Safer file-name sanitization & temp-file handling.

## Build / Publish (Google Play)

This zip contains the Dart sources + pubspec. To generate the platform folders (android/ios/web/), run this **once** on your machine where Flutter is installed:

```bash
flutter create .
flutter pub get
```

Then build a release app bundle:

```bash
flutter build appbundle --release
```

Upload the generated `.aab` in:
`build/app/outputs/bundle/release/app-release.aab`

### Notes

- Use a proper applicationId/package name before publishing:
  - After `flutter create .`, edit `android/app/build.gradle` and set `applicationId`.
- Configure signing (keystore) for Play release. Flutter docs explain the `key.properties` setup.
