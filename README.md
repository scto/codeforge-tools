# codeforge-tools

Spiegel von Android-Toolchains (aarch64/arm, für Termux) als GitHub-Release-Assets.
Die App CodeForgeMobile (SDK-Manager, `codeforge-env`) lädt die Pakete von hier und hängt so nicht von fünf fremden Repos ab.

Ein Workflow holt alle passenden Releases der Upstream-Repos und legt sie in diesem Repo als Releases an. Er läuft manuell und einmal pro Woche.

## Inhalt

1. [Quellen und Tags](#quellen-und-tags)
2. [Einrichtung](#einrichtung)
3. [Workflow benutzen](#workflow-benutzen)
4. [Eingaben](#eingaben)
5. [Gespiegelte Dateien herunterladen](#gespiegelte-dateien-herunterladen)
6. [Verhalten und Regeln](#verhalten-und-regeln)
7. [Lokal ausführen](#lokal-ausführen)
8. [Fehlersuche](#fehlersuche)
9. [Grenzen](#grenzen)
10. [Lizenz und Herkunft](#lizenz-und-herkunft)

## Quellen und Tags

| Kürzel | Upstream | Tag hier | Asset (Standardvarianten) |
|---|---|---|---|
| `sdk` | [HomuHomu833/android-sdk-custom](https://github.com/HomuHomu833/android-sdk-custom) | `android-sdk-<Version>` (z. B. `android-sdk-37.0.0`) | `android-sdk-aarch64-linux-android.tar.xz` |
| `ndk` | [HomuHomu833/android-ndk-custom](https://github.com/HomuHomu833/android-ndk-custom) | `android-ndk-<Name>` (z. B. `android-ndk-r29`) | `android-ndk-<Name>-aarch64-linux-android.tar.xz` |
| `cmake` | [HomuHomu833/cmake-custom](https://github.com/HomuHomu833/cmake-custom) | `cmake-<Version>` (z. B. `cmake-3.22.1`) | `cmake-aarch64-linux-android.tar.xz` |
| `aide` | [AndroidIDEOfficial/androidide-tools](https://github.com/AndroidIDEOfficial/androidide-tools) (archiviert) | `androidide-tools-v<Version>` (33.0.1 … 34.0.4) | `build-tools-<V>-{aarch64,arm}.tar.xz`, `platform-tools-<V>-{aarch64,arm}.tar.xz` |
| `lzhi` | [Lzhiyong/android-sdk-tools](https://github.com/Lzhiyong/android-sdk-tools) | `lzhiyong-sdk-tools-<Version>` (z. B. `…-35.0.2`) | `android-sdk-tools-static-{aarch64,arm}.zip` |

Asset-Namen bleiben unverändert. Zu jedem Asset liegt eine `<Name>.sha256` im selben Release.

Was die Quellen enthalten (anhand der READMEs, Build-Workflows und je einer Stichprobe geprüft):

- **sdk:** Android-Variante (Bionic) gibt es erst ab SDK 36.0.2. Die Releases 35.0.2 und 36.0.0 haben nur musl-Builds (`*-linux-musl`) und werden deshalb übersprungen.
- **ndk, cmake:** Namen und Aufbau der Archive nicht im Detail geprüft.
- **aide:** Stichprobe `v34.0.4`/aarch64: statisch gelinkte Bionic-Binaries samt `d8`, `apksigner` und `lib/`. Gespiegelt werden nur Tags der Form `v<Zahl>`; die Releases `sdk` und `jdk-11` des Repos nicht.
- **lzhi:** Stichprobe `35.0.2`/aarch64: statisch gelinkte Bionic-Binaries (`aapt`, `aapt2`, `aidl`, `zipalign`, `adb`, `fastboot` …), aber **ohne** `.jar`-Dateien und ohne `source.properties`. Kein vollständiges SDK-Paket; laut Upstream ist nur aarch64 getestet.
- **Nicht aufgenommen:** Repos mit glibc-Binaries (z. B. `nullij/sclrepo`, `soobujmiah/adt`). Sie laufen in Termux nicht nativ.

Ob die Binaries auf einem Gerät laufen, ist nicht getestet.

## Einrichtung

Einmalig:

1. Neues **öffentliches** Repo `codeforge-tools` anlegen. Die App lädt anonym; bei einem privaten Repo schlagen die Downloads fehl.
2. Diese drei Dateien committen und pushen, mit genau diesen Pfaden im **Wurzelverzeichnis** des Repos:
   ```
   .github/workflows/mirror-releases.yml
   scripts/mirror-releases.sh
   README.md
   ```
   Workflows aus Unterordnern führt GitHub nicht aus.
3. *Settings → Actions → General → Workflow permissions*: **Read and write permissions** aktivieren. Sonst darf der eingebaute Token keine Releases anlegen, obwohl der Workflow `contents: write` anfordert.

Kein PAT und keine Secrets nötig: Der Workflow schreibt mit dem eingebauten `GITHUB_TOKEN` ins eigene Repo.

## Workflow benutzen

### Über die Weboberfläche

1. *Actions → Mirror HomuHomu833 Releases → Run workflow*.
2. Beim ersten Mal `dry_run` angehakt lassen (Standard). Der Lauf listet nur, was gespiegelt würde.
3. Im Log prüfen:
   - `•` = Release wird gespiegelt, darunter die einzelnen Assets.
   - `–` = Release wird übersprungen, mit Grund (kein passendes Asset, Beta/RC).
   - Bei "kein Asset mit Variante …" stehen die ähnlichen Asset-Namen dabei.
4. Nochmals starten, diesmal `dry_run` **aus**. Der echte Lauf legt Releases an und lädt Assets hoch.

### Über die GitHub-CLI

```bash
# Trockenlauf, alles
gh workflow run mirror-releases.yml -R <owner>/codeforge-tools -f dry_run=true

# Echter Lauf, nur NDK r29 und CMake 3.22.1
gh workflow run mirror-releases.yml -R <owner>/codeforge-tools \
  -f components=ndk,cmake -f versions=r29,3.22.1 -f dry_run=false

# Fortschritt ansehen
gh run list -R <owner>/codeforge-tools --workflow mirror-releases.yml
gh run watch -R <owner>/codeforge-tools
```

### Zeitplan

Montags um 03:17 UTC läuft der Workflow automatisch als **echter** Lauf mit den Standardwerten und holt neue Upstream-Versionen nach. Bereits vorhandene Assets werden übersprungen.

## Eingaben

| Eingabe | Standard | Bedeutung |
|---|---|---|
| `components` | `sdk,ndk,cmake,aide,lzhi` | Welche Quellen gespiegelt werden |
| `versions` | leer (alle) | Nur diese Release-Namen oder Upstream-Tags, Komma-getrennt, z. B. `r29,3.22.1,37.0.0` |
| `variants` | `aarch64-linux-android` | Varianten für `sdk`/`ndk`/`cmake`, z. B. zusätzlich `armv7a-linux-androideabi` |
| `aide_variants` | `aarch64,arm` | Varianten für `aide` |
| `lzhi_variants` | `aarch64,arm` | Varianten für `lzhi` |
| `include_prerelease` | aus | Beta-/RC-Releases mitspiegeln |
| `dry_run` | an | Nur anzeigen, nichts anlegen oder hochladen |
| `force` | aus | Vorhandene Assets neu hochladen |

Alle Eingaben werden per Regex geprüft; ungültige Werte brechen den Lauf mit einer Fehlermeldung ab.

## Gespiegelte Dateien herunterladen

Jedes Release hat die URL-Form
`https://github.com/<owner>/codeforge-tools/releases/download/<Tag>/<Asset>`.

```bash
BASE=https://github.com/<owner>/codeforge-tools/releases/download

# NDK r29 und Prüfsumme laden
curl -LO $BASE/android-ndk-r29/android-ndk-r29-aarch64-linux-android.tar.xz
curl -LO $BASE/android-ndk-r29/android-ndk-r29-aarch64-linux-android.tar.xz.sha256
sha256sum -c android-ndk-r29-aarch64-linux-android.tar.xz.sha256

# Mit der GitHub-CLI
gh release download android-sdk-37.0.0 -R <owner>/codeforge-tools -p '*.tar.xz'

# Alle Releases auflisten
gh release list -R <owner>/codeforge-tools --limit 100
```

Typische Pfade:

| Was | Release-Tag | Datei |
|---|---|---|
| Android SDK 37.0.0 | `android-sdk-37.0.0` | `android-sdk-aarch64-linux-android.tar.xz` |
| NDK r29 | `android-ndk-r29` | `android-ndk-r29-aarch64-linux-android.tar.xz` |
| CMake 3.22.1 | `cmake-3.22.1` | `cmake-aarch64-linux-android.tar.xz` |
| Build-Tools 34.0.4 (aide) | `androidide-tools-v34.0.4` | `build-tools-34.0.4-aarch64.tar.xz` |
| Platform-Tools 34.0.4 (aide) | `androidide-tools-v34.0.4` | `platform-tools-34.0.4-aarch64.tar.xz` |
| Build-/Platform-Tools 35.0.2 (lzhi) | `lzhiyong-sdk-tools-35.0.2` | `android-sdk-tools-static-aarch64.zip` |

Ein `curl -L` auf diese URLs funktioniert ohne Anmeldung, solange das Repo öffentlich ist.

## Verhalten und Regeln

- **Idempotent:** Vorhandene Assets (samt `.sha256`) werden übersprungen. Ein abgebrochener oder teilweise fehlgeschlagener Lauf wird einfach wiederholt.
- **Prüfung vor dem Upload:** Die Größe wird gegen die API geprüft, die SHA-256 gegen das `digest`-Feld von GitHub, falls Upstream es liefert. Bei Abweichung wird nichts hochgeladen.
- **Fehler:** Der Lauf macht nach einem Fehler mit den übrigen Assets weiter und endet am Schluss mit Fehlerstatus.
- **Beta/RC:** Releases, deren Name oder Upstream-Tag `beta` oder `rc` als eigenes Wort enthält (`r30-beta2`, `4.0.0-rc1`, `beta-1`; nicht `src` oder `arc`), werden übersprungen, außer `include_prerelease` ist an.
- **Nur gewählte Varianten:** Upstream hat je Release oft rund 100 Assets (FreeBSD, Windows, musl, gnu …). Gespiegelt wird nur, was die Variantenliste auswählt.
- **Nichts wird gelöscht:** Das Skript entfernt keine Releases. Eine alte oder ungewollte Version löschst du von Hand:
  ```bash
  gh release delete android-ndk-r30-beta2 --cleanup-tag --yes -R <owner>/codeforge-tools
  ```
- **Releases sind nicht "Latest":** Gespiegelte Releases werden mit `--latest=false` angelegt.

## Lokal ausführen

Voraussetzungen: `bash`, `gh` (angemeldet), `jq`, `curl`, `sha256sum`.

```bash
export GH_TOKEN=$(gh auth token)
export TARGET_REPO=<owner>/codeforge-tools

# Trockenlauf, nur SDK
DRY_RUN=true COMPONENTS=sdk bash scripts/mirror-releases.sh

# Echter Lauf, einzelne Versionen
COMPONENTS=ndk VERSIONS=r29 bash scripts/mirror-releases.sh
```

Umgebungsvariablen des Skripts:

| Variable | Standard | Bedeutung |
|---|---|---|
| `GH_TOKEN` | – (Pflicht) | Token mit Schreibrecht auf `TARGET_REPO` |
| `TARGET_REPO` | – (Pflicht) | `owner/repo`, in das gespiegelt wird |
| `COMPONENTS` | `sdk,ndk,cmake,aide,lzhi` | Quellen |
| `VERSIONS` | leer | Versionsfilter |
| `VARIANTS` / `AIDE_VARIANTS` / `LZ_VARIANTS` | siehe oben | Varianten je Quelle |
| `INCLUDE_PRERELEASE` | `false` | Beta/RC mitnehmen |
| `DRY_RUN` / `FORCE` | `false` | Trockenlauf / Neu hochladen |
| `MAX_ASSET_MB` | `2000` | Größere Assets werden mit Warnung übersprungen |

## Fehlersuche

| Beobachtung | Ursache und Abhilfe |
|---|---|
| Workflow erscheint nicht unter *Actions* | Die Datei liegt nicht in `.github/workflows/` im Wurzelverzeichnis |
| `Resource not accessible by integration` oder HTTP 403 beim Anlegen des Releases | *Workflow permissions* auf "Read and write" stellen (siehe Einrichtung) |
| Release fehlt, Log zeigt "kein Asset mit Variante …" | Upstream nennt das Asset anders oder baut die Variante nicht. Die ähnlichen Asset-Namen stehen im Log. `variants` anpassen oder die Version bleibt draußen |
| Release fehlt, Log zeigt "Beta/RC, übersprungen" | Gewollt. Mit `include_prerelease` spiegelbar |
| `Prüfsumme stimmt nicht` | Datei bei Upstream hat sich geändert oder der Download war beschädigt. Lauf wiederholen; bleibt es, nicht übernehmen |
| `Größe stimmt nicht` | Download unvollständig. Lauf wiederholen |
| Asset wird mit Warnung übersprungen | Größer als `MAX_ASSET_MB` (GitHub erlaubt höchstens 2 GiB je Asset) |
| Lauf endet nach 350 Minuten | Zu viele Varianten auf einmal. In mehreren Läufen über `components` oder `versions` aufteilen |
| Release leer nach einem Fehler | Wiederholen; das Skript lädt nur das Fehlende nach |

## Grenzen

- Ein Job darf bei GitHub höchstens 6 Stunden laufen (Workflow: 350 Minuten).
- Ein Asset darf höchstens 2 GiB groß sein.
- Ohne eigenen Token erlaubt die GitHub-API 60 Anfragen pro Stunde. Der Workflow nutzt `GITHUB_TOKEN` und ist davon nicht betroffen; lokal setzt du `GH_TOKEN`.
- Die Upstream-Repos können Assets umbenennen oder löschen. Gespiegelte Releases bleiben bestehen; neue Namensschemata erkennt das Skript erst nach einer Anpassung.

## Lizenz und Herkunft

Die Inhalte stammen unverändert aus den Upstream-Repos; es gelten deren Lizenzen:

- Android SDK und NDK: Google-Lizenzbedingungen
- CMake: BSD-3-Clause
- `androidide-tools`: GPL-3.0. Bei Weiterverteilung der Binaries gelten die GPL-Pflichten, u. a. das Angebot des Quellcodes.
- `Lzhiyong/android-sdk-tools`: Lizenz im Upstream-Repo prüfen

Prüfe die Bedingungen vor einer öffentlichen Weiterverteilung selbst; das ist keine Rechtsberatung.
