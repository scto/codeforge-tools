#!/usr/bin/env bash
# =============================================================================
# Spiegelt Releases von HomuHomu833 (android-sdk-custom, android-ndk-custom, cmake-custom)
# als Release-Assets in dieses Repo (codeforge-tools).
#
# Pro Upstream-Release entsteht ein Release hier:
#   android-sdk-<Name>          (HomuHomu833/android-sdk-custom,  z. B. android-sdk-37.0.0)
#   android-ndk-<Name>          (HomuHomu833/android-ndk-custom,  z. B. android-ndk-r29, android-ndk-r30-beta2)
#   cmake-<Name>                (HomuHomu833/cmake-custom,        z. B. cmake-3.22.1)
#   androidide-tools-<Tag>      (AndroidIDEOfficial/androidide-tools, z. B. androidide-tools-v34.0.4)
#   lzhiyong-sdk-tools-<Tag>    (Lzhiyong/android-sdk-tools,      z. B. lzhiyong-sdk-tools-35.0.2)
# Assets behalten ihren Namen; zu jedem Asset kommt eine <Name>.sha256-Datei.
# Gespiegelt werden nur Assets der gewünschten Varianten, nicht die ~100 Varianten je Release
# (FreeBSD, Windows …). Standard: sdk/ndk/cmake = aarch64-linux-android,armv7a-linux-androideabi; aide/lzhi = aarch64,arm.
#
# Läuft idempotent: Vorhandene Assets werden übersprungen (FORCE=true lädt sie neu hoch),
# ein abgebrochener Lauf kann einfach wiederholt werden.
#
# Umgebung (alle außer GH_TOKEN und TARGET_REPO optional):
#   GH_TOKEN     Token mit Schreibrecht auf TARGET_REPO (im Workflow: github.token)
#   TARGET_REPO  owner/repo, in das gespiegelt wird
#   COMPONENTS   sdk,ndk,cmake,aide,lzhi       (Standard: alle)
#   VERSIONS     Release-Namen/Tags, Komma-getrennt; leer = alle
#   VARIANTS     nur sdk/ndk/cmake (Standard aarch64-linux-android,armv7a-linux-androideabi)
#                Upstream-Namen: android-sdk-<variante>.tar.xz, android-ndk-<name>-<variante>.tar.xz,
#                cmake-<variante>.tar.xz (CMake-Assets tragen keine Versionsnummer im Dateinamen)
#   AIDE_VARIANTS  nur aide (Standard aarch64,arm)
#   LZ_VARIANTS    nur lzhi (Standard aarch64,arm)
#   DRY_RUN      true = nur anzeigen, nichts anlegen oder hochladen
#   FORCE        true = vorhandene Assets neu hochladen
#   INCLUDE_PRERELEASE  true = auch Beta-/RC-Releases spiegeln (Standard: false).
#                Übersprungen wird, wenn Release-Name oder Upstream-Tag "beta" oder "rc"
#                als eigenes Wort enthält (r30-beta2, 4.0.0-rc1, beta-1; nicht src/arc).
# =============================================================================
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN fehlt}"
: "${TARGET_REPO:?TARGET_REPO fehlt (owner/repo)}"
COMPONENTS="${COMPONENTS:-sdk,ndk,cmake,aide,lzhi}"
VERSIONS="${VERSIONS:-}"
VARIANTS="${VARIANTS:-aarch64-linux-android,armv7a-linux-androideabi}"
AIDE_VARIANTS="${AIDE_VARIANTS:-aarch64,arm}"
LZ_VARIANTS="${LZ_VARIANTS:-aarch64,arm}"
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"
INCLUDE_PRERELEASE="${INCLUDE_PRERELEASE:-false}"
MAX_ASSET_MB="${MAX_ASSET_MB:-2000}"            # GitHub erlaubt höchstens 2 GiB je Asset
WORK="${RUNNER_TEMP:-/tmp}/mirror-work"

die() { echo "::error::$*" >&2; exit 1; }

# ---- Eingaben prüfen (kommen aus Workflow-Eingaben, nie ungeprüft in Shell/Regex) ----
[[ "$TARGET_REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "Ungültiges TARGET_REPO"
[[ "$COMPONENTS" =~ ^[a-z]+(,[a-z]+)*$ ]] || die "Ungültige COMPONENTS (erlaubt: sdk,ndk,cmake,aide,lzhi)"
[[ -z "$VERSIONS" || "$VERSIONS" =~ ^[A-Za-z0-9._-]+(,[A-Za-z0-9._-]+)*$ ]] || die "Ungültige VERSIONS (nur Release-Namen, Komma-getrennt)"
for b in VARIANTS AIDE_VARIANTS LZ_VARIANTS; do
  [[ "${!b}" =~ ^[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+)*$ ]] || die "Ungültige $b"
done
[[ "$MAX_ASSET_MB" =~ ^[0-9]+$ ]] || die "Ungültiges MAX_ASSET_MB"
for b in DRY_RUN FORCE INCLUDE_PRERELEASE; do [[ "${!b}" == true || "${!b}" == false ]] || die "$b muss true oder false sein"; done

declare -A UPSTREAM=( [sdk]=HomuHomu833/android-sdk-custom [ndk]=HomuHomu833/android-ndk-custom [cmake]=HomuHomu833/cmake-custom
                      [aide]=AndroidIDEOfficial/androidide-tools [lzhi]=Lzhiyong/android-sdk-tools )
declare -A PREFIX=(   [sdk]=android-sdk [ndk]=android-ndk [cmake]=cmake
                      [aide]=androidide-tools [lzhi]=lzhiyong-sdk-tools )
# Release-Name für den Ziel-Tag: aus dem Release-Namen (HomuHomu833) oder aus dem Upstream-Tag
declare -A NAMEFROM=( [sdk]=name [ndk]=name [cmake]=name [aide]=tag [lzhi]=tag )
# Nur Upstream-Tags, die passen (aide hat daneben die Releases "sdk" und "jdk-11")
declare -A TAGRE=(    [aide]='^v[0-9]' )

alt() { tr ',' '\n' <<<"$1" | sed 's/\./\\./g' | paste -sd'|'; }
variants_of() { case $1 in aide) echo "$AIDE_VARIANTS" ;; lzhi) echo "$LZ_VARIANTS" ;; *) echo "$VARIANTS" ;; esac; }
# Regex für Asset-Namen je Quelle
asset_re() {
  case $1 in
    aide) echo "-($(alt "$AIDE_VARIANTS"))\\.tar\\.xz\$" ;;                       # build-tools-34.0.4-aarch64.tar.xz
    lzhi) echo "^android-sdk-tools-static-($(alt "$LZ_VARIANTS"))\\.zip\$" ;;       # android-sdk-tools-static-aarch64.zip
    *)    echo "-($(alt "$VARIANTS"))\\.(tar\\.xz|tar\\.gz|zip|7z)\$" ;;          # *-aarch64-linux-android.tar.xz
  esac
}
max_bytes=$(( MAX_ASSET_MB * 1024 * 1024 ))

# "beta"/"rc" nur als eigenes Wort (Buchstaben davor/danach ausgeschlossen), Groß-/Kleinschreibung egal
SKIP_RE='(^|[^a-z])(beta|rc)([^a-z]|$)'
[[ "$INCLUDE_PRERELEASE" == true ]] && SKIP_RE=""

mkdir -p "$WORK"
n_rel_new=0; n_up=0; n_skip=0; n_fail=0
summary=()

retry() { # retry <n> <befehl…>
  local n=$1 i; shift
  for ((i = 1; i <= n; i++)); do "$@" && return 0; echo "  Versuch $i/$n fehlgeschlagen: $1 $2" >&2; sleep $((i * 5)); done
  return 1
}

want_version() { # name tag
  [[ -z "$VERSIONS" ]] && return 0
  local v; for v in ${VERSIONS//,/ }; do [[ "$v" == "$1" || "$v" == "$2" ]] && return 0; done
  return 1
}

mirror_asset() { # comp upstream_repo upstream_tag target_tag asset size digest
  local comp=$1 repo=$2 utag=$3 ttag=$4 aname=$5 size=$6 digest=$7 file sha got
  if (( size > max_bytes )); then
    echo "::warning::$aname ($((size / 1048576)) MB) überschreitet ${MAX_ASSET_MB} MB – übersprungen"; n_skip=$((n_skip + 1)); return 0
  fi
  if [[ "$DRY_RUN" == true ]]; then echo "  [dry-run] würde laden und hochladen: $aname ($((size / 1048576)) MB)"; return 0; fi

  rm -f "$WORK/$aname" "$WORK/$aname.sha256"
  if ! retry 3 gh release download "$utag" -R "$repo" -p "$aname" -D "$WORK" --clobber; then
    echo "::error::Download fehlgeschlagen: $repo $utag $aname"; n_fail=$((n_fail + 1)); return 0
  fi
  file="$WORK/$aname"
  [[ -f "$file" ]] || { echo "::error::Datei fehlt nach Download: $aname"; n_fail=$((n_fail + 1)); return 0; }
  got=$(stat -c %s "$file")
  if [[ "$got" != "$size" ]]; then
    echo "::error::Größe stimmt nicht für $aname (API $size, geladen $got)"; rm -f "$file"; n_fail=$((n_fail + 1)); return 0
  fi
  sha=$(sha256sum "$file" | cut -d' ' -f1)
  if [[ -n "$digest" && "${digest#sha256:}" != "$sha" ]]; then
    echo "::error::Prüfsumme stimmt nicht für $aname (Upstream ${digest#sha256:}, berechnet $sha)"; rm -f "$file"; n_fail=$((n_fail + 1)); return 0
  fi
  printf '%s  %s\n' "$sha" "$aname" > "$file.sha256"
  if retry 3 gh release upload "$ttag" "$file" "$file.sha256" -R "$TARGET_REPO" --clobber; then
    echo "  hochgeladen: $aname ($((size / 1048576)) MB, sha256 ${sha:0:12}…)"; n_up=$((n_up + 1))
  else
    echo "::error::Upload fehlgeschlagen: $aname"; n_fail=$((n_fail + 1))
  fi
  rm -f "$file" "$file.sha256"
}

for comp in ${COMPONENTS//,/ }; do
  [[ -n "${UPSTREAM[$comp]:-}" ]] || die "Unbekannte Komponente '$comp' (erlaubt: sdk, ndk, cmake, aide, lzhi)"
  repo=${UPSTREAM[$comp]}; vlabel=$(variants_of "$comp"); asset_regex=$(asset_re "$comp"); tag_regex=${TAGRE[$comp]:-.}
  echo "::group::$comp ($repo)"
  releases=$(gh api --paginate "repos/$repo/releases?per_page=100" | jq -s 'add // []') \
    || die "Releases von $repo nicht abrufbar"
  total=$(jq length <<<"$releases")
  echo "Upstream-Releases: $total, Varianten: $vlabel"
  c_rel=0; c_none=0; c_pre=0

  while IFS= read -r rel; do
    name=$(jq -r .name <<<"$rel"); utag=$(jq -r .tag <<<"$rel")
    want_version "$name" "$utag" || continue
    if [[ "$(jq -r .skip <<<"$rel")" == true ]]; then
      echo "– $name: Beta/RC, übersprungen (INCLUDE_PRERELEASE=true schaltet das ab)"; c_pre=$((c_pre + 1)); continue
    fi
    nassets=$(jq '.assets | length' <<<"$rel")
    if (( nassets == 0 )); then
      echo "– $name: kein Asset mit Variante $vlabel, übersprungen (Upstream-Assets: $(jq -r .total <<<"$rel"))"
      echo "    ähnliche Asset-Namen (aarch64/android): $(jq -r '.similar | if length == 0 then "keine" else join(", ") end' <<<"$rel")"
      c_none=$((c_none + 1)); continue
    fi
    safe=$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')
    ttag="${PREFIX[$comp]}-$safe"
    echo "• $name → $ttag ($nassets Asset(s))"

    existing=""
    if gh release view "$ttag" -R "$TARGET_REPO" >/dev/null 2>&1; then
      existing=$(gh release view "$ttag" -R "$TARGET_REPO" --json assets -q '.assets[].name')
    elif [[ "$DRY_RUN" == true ]]; then
      echo "  [dry-run] würde Release $ttag anlegen"
    else
      notes="Spiegel von $(jq -r .url <<<"$rel")
Upstream-Tag: $utag · veröffentlicht: $(jq -r .date <<<"$rel")
Gespiegelte Varianten: $vlabel. Assets unverändert, SHA-256 in den .sha256-Dateien.
Lizenz und Herkunft siehe Upstream-Repo https://github.com/$repo."
      args=(--repo "$TARGET_REPO" --title "$name" --notes "$notes" --latest=false)
      [[ "$(jq -r .pre <<<"$rel")" == true ]] && args+=(--prerelease)
      retry 3 gh release create "$ttag" "${args[@]}" || { echo "::error::Release $ttag konnte nicht angelegt werden"; n_fail=$((n_fail + 1)); continue; }
      n_rel_new=$((n_rel_new + 1))
    fi
    c_rel=$((c_rel + 1))

    while IFS= read -r asset; do
      aname=$(jq -r .name <<<"$asset"); asize=$(jq -r .size <<<"$asset"); adigest=$(jq -r .digest <<<"$asset")
      if [[ "$FORCE" != true ]] && grep -qxF "$aname" <<<"$existing" && grep -qxF "$aname.sha256" <<<"$existing"; then
        echo "  vorhanden: $aname"; n_skip=$((n_skip + 1)); continue
      fi
      mirror_asset "$comp" "$repo" "$utag" "$ttag" "$aname" "$asize" "$adigest"
    done < <(jq -c '.assets[]' <<<"$rel")
  done < <(jq -c --arg re "$asset_regex" --arg tre "$tag_regex" --arg by "${NAMEFROM[$comp]}" --arg skip "$SKIP_RE" '
      .[] | select(.draft | not) | select(.tag_name | test($tre))
      | { name: (if $by == "tag" or (.name // "") == "" then .tag_name else .name end), tag: .tag_name, pre: .prerelease,
          date: .published_at, url: .html_url, total: (.assets | length),
          skip: ($skip != "" and ([(.name // ""), .tag_name] | map(test($skip; "i")) | any)),
          similar: [ .assets[] | select(.name | test("aarch64|android"; "i")) | select(.name | test($re) | not) | .name ][0:8],
          assets: [ .assets[] | select(.name | test($re)) | { name, size, digest: (.digest // "") } ] }' <<<"$releases")

  summary+=("| $comp | $total | $c_rel | $c_none | $c_pre |")
  echo "::endgroup::"
done

echo "Neu angelegte Releases: $n_rel_new · hochgeladene Assets: $n_up · übersprungen: $n_skip · Fehler: $n_fail"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Spiegelung HomuHomu833 → $TARGET_REPO"
    echo "Varianten (sdk/ndk/cmake): \`$VARIANTS\` · aide/lzhi: \`$AIDE_VARIANTS\` / \`$LZ_VARIANTS\` · Trockenlauf: $DRY_RUN · Neu laden: $FORCE · Beta/RC mitnehmen: $INCLUDE_PRERELEASE"
    echo
    echo "| Komponente | Upstream-Releases | verarbeitet | ohne passendes Asset | Beta/RC übersprungen |"
    echo "|---|---|---|---|---|"
    printf '%s\n' "${summary[@]}"
    echo
    echo "Neue Releases: **$n_rel_new** · hochgeladene Assets: **$n_up** · übersprungen: **$n_skip** · Fehler: **$n_fail**"
  } >> "$GITHUB_STEP_SUMMARY"
fi
(( n_fail == 0 )) || exit 1
