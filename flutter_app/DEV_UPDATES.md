# NASQO Flutter development updates (Android)

The development APK checks https://erp.indexesstore.com/flutter-updates/manifest.json once when the main screen opens and via the update button in the top bar. A newer `versionCode` prompts for consent; the app downloads the APK over HTTPS, checks its exact byte count and SHA-256, then opens the Android package installer. Android verifies the signing certificate and requests user approval. No automatic silent installation is attempted.

The existing SQLite data remains in the app sandbox. An in-place upgrade requires the same `applicationId` (`com.indexesstore.nasqo_qa`) and the same signing certificate as the APK already installed. **Do not uninstall the existing app** to update it. Back up local data before schema-changing releases.

Server directory: `/home/chatgpt-admin/nasqo-flutter-updates`; reverse proxy: `/flutter-updates/*` to the isolated `nasqo-flutter-update-files` container. Until a signed APK is published, the manifest has `enabled: false`. The server does not host or access the phone's SQLite data.

## Publishing a development APK

1. Configure a **persistent development signing key** in the Android build system. GitHub Actions currently builds a debug APK; a GitHub-hosted ephemeral debug key is **not suitable** for consistent in-place updates.
2. Build with the same signing key each time, increase the `+buildNumber` in `flutter_app/pubspec.yaml`, and confirm the installed app uses the same signing identity.
3. On a machine with Android SDK `apksigner` and `aapt`, run:
   `NASQO_DEV_UPDATE_DIR=/home/chatgpt-admin/nasqo-flutter-updates scripts/publish-flutter-dev-apk.sh path/to/signed.apk 19 1.0.18 "Changes"`
   The script checks the APK signature, package ID, versionCode, signer continuity, size and SHA-256; then publishes an atomic manifest.
4. Install the **first signed development build** once. Later updates can install over it from the app's update button.

The app is not hot-reloading Dart from the server. Flutter code and native changes require a new signed APK and user confirmation. During development, `flutter run` on a connected device still provides Flutter hot reload.

**Security:** Only publish trusted APKs. Keep the signing keystore and passwords outside the repository. The update server is currently a publicly reachable development download endpoint; do not publish proprietary builds without access controls. Use a separate internal distribution domain with authentication before distributing sensitive builds.
