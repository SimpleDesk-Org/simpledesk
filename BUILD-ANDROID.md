# SimpleDesk für Android bauen

Die App heißt auf dem Handy „SimpleDesk“, ihre App-ID ist `com.felixthedev.simpledesk`.
Diese Anleitung baut ein APK für arm64. Das passt auf fast alle Handys.

## 1. Release-Schlüssel anlegen (nur einmal)

Jedes APK muss mit demselben Schlüssel signiert sein, sonst lässt Android kein Update zu.
Den Schlüssel legst du selbst an. Er kommt nie ins Repo.

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v -keystore "$env:USERPROFILE\simpledesk-release.jks" -alias simpledesk -keyalg RSA -keysize 4096 -validity 10000
```

- keytool fragt nach einem Passwort und nach Namen. Als Namen reichen z. B. „SimpleDesk“ und „Amt Eider“.
- Das Passwort gilt für die Datei und für den Schlüssel.
- Sichere die Datei `simpledesk-release.jks` und das Passwort, z. B. im Passwort-Manager und auf einem zweiten Laufwerk.
  Ist der Schlüssel weg, kann niemand mehr Updates installieren. Dann muss jeder die App löschen und neu installieren.

## 2. Weg A: GitHub baut das APK (einfachster Weg)

Einmal die Secrets anlegen: im Repo unter **Settings → Secrets and variables → Actions → New repository secret**.

| Secret | Inhalt |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | die Datei `simpledesk-release.jks` als Base64 (Befehl unten) |
| `ANDROID_KEYSTORE_PASSWORD` | dein Passwort |
| `ANDROID_KEY_ALIAS` | `simpledesk` |
| `ANDROID_KEY_PASSWORD` | dasselbe Passwort |

Die Base64-Zeile legt dieser Befehl in die Zwischenablage:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\simpledesk-release.jks")) | Set-Clipboard
```

Bauen: **Actions → SimpleDesk Android → Run workflow**, Branch `simpledesk`.
Am Ende liegt das APK beim Lauf unter **Artifacts**: `simpledesk-<version>-aarch64.apk`.

Endet der Name auf `-debugkey`, fehlen die Secrets. Ein solches APK taugt nur zum Testen.

## 3. Weg B: Lokal unter Windows bauen

Upstream hat Android immer nur unter Linux gebaut. Klemmt es bei vcpkg oder cargo ndk unter Windows,
nimm Weg A oder WSL2 (Ubuntu) mit denselben Schritten wie im Workflow `.github/workflows/simpledesk-android.yml`.

### Installieren

| Was | Version |
|---|---|
| [Android Studio](https://developer.android.com/studio) | aktuell. Im SDK Manager zusätzlich: **NDK (Side by side) 28.2.13676358** (das ist r28c), Android SDK Platform 36, Command-line Tools |
| [Flutter](https://docs.flutter.dev/release/archive) | genau **3.24.5** |
| [Rust](https://rustup.rs) | Toolchain **1.75** mit Ziel `aarch64-linux-android` |
| cargo-ndk | **3.1.2** |
| [vcpkg](https://github.com/microsoft/vcpkg) | Commit **9e593bb18ea69cc5095e012465dcd675a822ed0d** |
| [LLVM](https://github.com/llvm/llvm-project/releases/tag/llvmorg-15.0.6) | **15.0.6** (für bindgen) |
| Visual Studio Build Tools | mit „Desktopentwicklung mit C++“ (vcpkg baut damit Hilfsprogramme) |

```powershell
rustup toolchain install 1.75 --target aarch64-linux-android
cargo +1.75 install cargo-ndk --version 3.1.2 --locked
git clone https://github.com/microsoft/vcpkg C:\vcpkg
git -C C:\vcpkg checkout 9e593bb18ea69cc5095e012465dcd675a822ed0d
C:\vcpkg\bootstrap-vcpkg.bat -disableMetrics
```

Optional, wie im Workflow: im Flutter-Ordner `git apply <Repo>\.github\patches\flutter_3.24.4_dropdown_menu_enableFilter.diff`.

### Bridge-Dateien holen

Die Dateien zwischen Rust und Dart (`src/bridge_generated.rs`, `flutter/lib/generated_bridge.dart` …) stehen nicht im Repo.
Lade sie von einem Lauf von **SimpleDesk Android** (oder Windows): Artefakt `bridge-artifact` herunterladen und im Hauptordner des Repos entpacken.

### Bauen

Alle Befehle in PowerShell im Hauptordner des Repos. Die Pfade passen, wenn du alles an den Standardort installiert hast.

```powershell
$env:ANDROID_NDK_HOME = "$env:LOCALAPPDATA\Android\Sdk\ndk\28.2.13676358"
$env:VCPKG_ROOT = "C:\vcpkg"
$env:LIBCLANG_PATH = "C:\Program Files\LLVM\bin"
```

C-Bibliotheken (vcpkg, einmal pro vcpkg-Stand):

```powershell
& "$env:VCPKG_ROOT\vcpkg" install --triplet arm64-android --x-install-root="$env:VCPKG_ROOT\installed"
```

Rust-Bibliothek:

```powershell
cargo +1.75 ndk --platform 21 --target aarch64-linux-android build --locked --release --features flutter,hwcodec
New-Item -ItemType Directory -Force flutter\android\app\src\main\jniLibs\arm64-v8a
Copy-Item target\aarch64-linux-android\release\liblibrustdesk.so flutter\android\app\src\main\jniLibs\arm64-v8a\librustdesk.so
Copy-Item "$env:ANDROID_NDK_HOME\toolchains\llvm\prebuilt\windows-x86_64\sysroot\usr\lib\aarch64-linux-android\libc++_shared.so" flutter\android\app\src\main\jniLibs\arm64-v8a\
```

Schlüssel eintragen: Lege `flutter\android\key.properties` an (git ignoriert die Datei):

```properties
storeFile=C:/Users/<dein Name>/simpledesk-release.jks
storePassword=<dein Passwort>
keyAlias=simpledesk
keyPassword=<dein Passwort>
```

APK bauen:

```powershell
cd flutter
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

Das APK liegt dann in `flutter\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`.
Steht beim Bauen die Warnung `no release key`, fehlt `key.properties`. Dann ist das APK nur mit dem Debug-Schlüssel signiert.

## 4. Auf dem Handy installieren

- APK aufs Handy kopieren und öffnen. Android fragt einmal, ob die App „unbekannte Apps installieren“ darf.
- Ist schon ein Test-APK (`-debugkey`) installiert, lösch es vorher. Android nimmt kein Update mit einem anderen Schlüssel an.
- Nach dem Start: Server-Adresse eingeben, mit Eider anmelden. Zum Freigeben unter „Bildschirm freigeben“ den Dienst starten.
