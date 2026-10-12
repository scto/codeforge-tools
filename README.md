# codeforge-tools

Spiegel der Android-Toolchains von [HomuHomu833](https://github.com/HomuHomu833) (aarch64-Builds) als Release-Assets.
Quelle für `codeforge-env` in CodeForgeMobile (SDK-Manager), damit die App nicht von drei fremden Repos abhängt.

| Komponente | Upstream | Tag hier | Asset (Standardvariante) |
|---|---|---|---|
| Android SDK | `HomuHomu833/android-sdk-custom` | `android-sdk-<Version>` (z. B. `android-sdk-37.0.0`) | `android-sdk-aarch64-linux-android.tar.xz` |
| Android NDK | `HomuHomu833/android-ndk-custom` | `android-ndk-<Name>` (z. B. `android-ndk-r29`, `android-ndk-r30-beta2`) | `android-ndk-<Name>-aarch64-linux-android.tar.xz` |
| CMake | `HomuHomu833/cmake-custom` | `cmake-<Version>` (z. B. `cmake-3.22.1`) | `cmake-aarch64-linux-android.tar.xz` |

Asset-Namen bleiben unverändert. Zu jedem Asset liegt eine `<Name>.sha256` im selben Release.

## Einrichtung

1. Neues **öffentliches** Repo `codeforge-tools` anlegen (die App lädt anonym; bei privatem Repo scheitern die Downloads).
2. Diese Dateien committen (`.github/workflows/mirror-releases.yml`, `scripts/mirror-releases.sh`, `README.md`) und pushen.
3. *Settings → Actions → General → Workflow permissions*: **Read and write permissions** (sonst darf der Standard-Token keine Releases anlegen, obwohl der Workflow `contents: write` anfordert).
4. *Actions → Mirror HomuHomu833 Releases → Run workflow*:
   - Erst mit `dry_run = true` (Standard): listet nur, was gespiegelt würde.
   - Dann `dry_run = false`.

Kein PAT und keine Secrets nötig: der Workflow schreibt mit `GITHUB_TOKEN` ins eigene Repo.

## Eingaben

| Eingabe | Standard | Bedeutung |
|---|---|---|
| `components` | `sdk,ndk,cmake` | Was gespiegelt wird |
| `versions` | leer (alle) | Nur diese Release-Namen/Tags, z. B. `r29,3.22.1,37.0.0` |
| `variants` | `aarch64-linux-android` | Asset-Varianten, Komma-getrennt (z. B. zusätzlich `x86_64-linux-android`) |
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

Die Inhalte stammen unverändert von HomuHomu833; Lizenzen gelten wie im jeweiligen Upstream-Repo (Android SDK/NDK: Google-Lizenzbedingungen, CMake: BSD-3-Clause). Prüfe vor einer öffentlichen Weiterverteilung die Bedingungen selbst; das ist keine Rechtsberatung.

## Lokal testen

```bash
GH_TOKEN=$(gh auth token) TARGET_REPO=<owner>/codeforge-tools DRY_RUN=true bash scripts/mirror-releases.sh
```
