# codeforge-tools

Spiegel von Android-Toolchains (aarch64/arm, für Termux) als Release-Assets.
Quelle für `codeforge-env` in CodeForgeMobile (SDK-Manager), damit die App nicht von fünf fremden Repos abhängt.

| Komponente | Upstream | Tag hier | Asset (Standardvarianten) |
|---|---|---|---|
| `sdk` | [HomuHomu833/android-sdk-custom](https://github.com/HomuHomu833/android-sdk-custom) | `android-sdk-<Version>` | `android-sdk-aarch64-linux-android.tar.xz` |
| `ndk` | [HomuHomu833/android-ndk-custom](https://github.com/HomuHomu833/android-ndk-custom) | `android-ndk-<Name>` (z. B. `android-ndk-r29`) | `android-ndk-<Name>-aarch64-linux-android.tar.xz` |
| `cmake` | [HomuHomu833/cmake-custom](https://github.com/HomuHomu833/cmake-custom) | `cmake-<Version>` | `cmake-aarch64-linux-android.tar.xz` |
| `aide` | [AndroidIDEOfficial/androidide-tools](https://github.com/AndroidIDEOfficial/androidide-tools) (archiviert, GPL-3.0) | `androidide-tools-v<Version>` (33.0.1 … 34.0.4) | `build-tools-<V>-{aarch64,arm}.tar.xz`, `platform-tools-<V>-{aarch64,arm}.tar.xz` |
| `lzhi` | [Lzhiyong/android-sdk-tools](https://github.com/Lzhiyong/android-sdk-tools) | `lzhiyong-sdk-tools-<Version>` (z. B. 35.0.2) | `android-sdk-tools-static-{aarch64,arm}.zip` |

Asset-Namen bleiben unverändert. Zu jedem Asset liegt eine `<Name>.sha256` im selben Release.

### Was die Quellen enthalten (geprüft nur anhand der README/Workflows und je einer Stichprobe)

- **HomuHomu833:** Android-Variante (Bionic) ab SDK 36.0.2. Die Releases 35.0.2 und 36.0.0 haben nur musl-Builds und werden deshalb übersprungen. NDK und CMake: Namen und Layout nicht im Detail geprüft.
- **aide:** Stichprobe `v34.0.4` aarch64: statisch gelinkte Bionic-Binaries, mit `d8`, `apksigner`, `lib/`. Nur die Tags `v<Zahl>`; die Releases `sdk` und `jdk-11` des Repos werden nicht gespiegelt.
- **lzhi:** Stichprobe `35.0.2` aarch64: statisch gelinkte Bionic-Binaries (`aapt`, `aapt2`, `aidl`, `zipalign`, `adb`, `fastboot` …), **ohne** `.jar`-Dateien und ohne `source.properties`. Kein vollständiges SDK-Paket. Das README des Upstream-Repos sagt: nur aarch64 getestet.
- Nicht aufgenommen, weil nicht für Termux geeignet: `nullij/sclrepo` und `soobujmiah/adt` (glibc-Binaries, laufen nur in PRoot-Debian).
- Ob die Binaries auf dem Gerät laufen, ist **nicht** getestet.

## Einrichtung

1. Neues **öffentliches** Repo `codeforge-tools` anlegen (die App lädt anonym; bei privatem Repo scheitern die Downloads).
2. Diese Dateien committen (`.github/workflows/mirror-releases.yml`, `scripts/mirror-releases.sh`, `README.md`) und pushen.
3. Die Workflow-Datei muss im **Wurzelverzeichnis** des Repos unter `.github/workflows/` liegen, nicht in einem Unterordner.
4. *Settings → Actions → General → Workflow permissions*: **Read and write permissions** (sonst darf der Standard-Token keine Releases anlegen, obwohl der Workflow `contents: write` anfordert).
5. *Actions → Mirror HomuHomu833 Releases → Run workflow*:
   - Erst mit `dry_run = true` (Standard): listet nur, was gespiegelt würde.
   - Dann `dry_run = false`.

Kein PAT und keine Secrets nötig: der Workflow schreibt mit `GITHUB_TOKEN` ins eigene Repo.

## Eingaben

| Eingabe | Standard | Bedeutung |
|---|---|---|
| `components` | `sdk,ndk,cmake,aide,lzhi` | Was gespiegelt wird |
| `versions` | leer (alle) | Nur diese Release-Namen/Tags, z. B. `r29,3.22.1,37.0.0` |
| `variants` | `aarch64-linux-android` | Varianten für `sdk`/`ndk`/`cmake` (z. B. zusätzlich `armv7a-linux-androideabi`) |
| `aide_variants` | `aarch64,arm` | Varianten für `aide` |
| `lzhi_variants` | `aarch64,arm` | Varianten für `lzhi` |
| `dry_run` | an | Nur anzeigen |
| `force` | aus | Vorhandene Assets neu hochladen |

Der Zeitplan (montags 03:17 UTC) startet echte Läufe mit den Standardwerten und holt neue Upstream-Versionen nach.

## Verhalten

- **Idempotent:** vorhandene Assets (samt `.sha256`) werden übersprungen. Ein abgebrochener oder fehlgeschlagener Lauf wird einfach wiederholt.
- **Prüfung vor dem Upload:** Größe gegen die API; SHA-256 gegen das `digest`-Feld von GitHub, falls Upstream es liefert.
- **Fehler:** Der Lauf macht bei einem Fehler mit den übrigen Assets weiter und endet am Schluss mit Exit-Code 1.
- **Nur eine Variante:** Upstream hat je Release etwa 94–101 Assets (FreeBSD, Windows, musl, gnu …). Gespiegelt wird nur, was `variants` auswählt.
- **Limits:** Assets über 2 GiB lehnt GitHub ab (Skript überspringt sie mit Warnung). Ein Job darf höchstens 6 Stunden laufen (Workflow: 350 Minuten). Bei vielen Varianten besser in mehreren Läufen über `components`/`versions`.

## Lizenz und Herkunft

Die Inhalte stammen unverändert aus den Upstream-Repos; Lizenzen gelten wie dort (Android SDK/NDK: Google-Lizenzbedingungen, CMake: BSD-3-Clause, androidide-tools: GPL-3.0 – bei Weiterverteilung der Binaries gelten die GPL-Pflichten, u. a. Quellcode-Angebot). Prüfe vor einer öffentlichen Weiterverteilung die Bedingungen selbst; das ist keine Rechtsberatung.

## Lokal testen

```bash
GH_TOKEN=$(gh auth token) TARGET_REPO=<owner>/codeforge-tools DRY_RUN=true bash scripts/mirror-releases.sh
```
