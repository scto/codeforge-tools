#!/usr/bin/env bash
# =============================================================================
# Spiegelt Releases von HomuHomu833 (android-sdk-custom, android-ndk-custom, cmake-custom)
# als Release-Assets in dieses Repo (codeforge-tools).
#
# Pro Upstream-Release entsteht ein Release hier:
#   android-sdk-<Name>   (z. B. android-sdk-37.0.0)
#   android-ndk-<Name>   (z. B. android-ndk-r29, android-ndk-r30-beta2)
#   cmake-<Name>         (z. B. cmake-3.22.1)
# Assets behalten ihren Namen; zu jedem Asset kommt eine <Name>.sha256-Datei.
# Gespiegelt werden nur Assets der gewünschten Varianten (Standard: aarch64-linux-android),
# nicht die ~100 Varianten je Release (FreeBSD, Windows …).
#
# Läuft idempotent: Vorhandene Assets werden übersprungen (FORCE=true lädt sie neu hoch),
# ein abgebrochener Lauf kann einfach wiederholt werden.
#
# Umgebung (alle außer GH_TOKEN und TARGET_REPO optional):
#   GH_TOKEN     Token mit Schreibrecht auf TARGET_REPO (im Workflow: github.token)
#   TARGET_REPO  owner/repo, in das gespiegelt wird
#   COMPONENTS   sdk,ndk,cmake                 (Standard: alle)
#   VERSIONS     Release-Namen/Tags, Komma-getrennt; leer = alle
#   VARIANTS     z. B. aarch64-linux-android,arm-linux-androideabi
#   DRY_RUN      true = nur anzeigen, nichts anlegen oder hochladen
#   FORCE        true = vorhandene Assets neu hochladen
# =============================================================================
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN fehlt}"
: "${TARGET_REPO:?TARGET_REPO fehlt (owner/repo)}"
COMPONENTS="${COMPONENTS:-sdk,ndk,cmake}"
VERSIONS="${VERSIONS:-}"
VARIANTS="${VARIANTS:-aarch64-linux-android}"
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"
MAX_ASSET_MB="${MAX_ASSET_MB:-2000}"            # GitHub erlaubt höchstens 2 GiB je Asset
WORK="${RUNNER_TEMP:-/tmp}/mirror-work"

die() { echo "::error::$*" >&2; exit 1; }

# ---- Eingaben prüfen (kommen aus Workflow-Eingaben, nie ungeprüft in Shell/Regex) ----
[[ "$TARGET_REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "Ungültiges TARGET_REPO"
[[ "$COMPONENTS" =~ ^[a-z]+(,[a-z]+)*$ ]] || die "Ungültige COMPONENTS (erlaubt: sdk,ndk,cmake)"
[[ -z "$VERSIONS" || "$VERSIONS" =~ ^[A-Za-z0-9._-]+(,[A-Za-z0-9._-]+)*$ ]] || die "Ungültige VERSIONS (nur Release-Namen, Komma-getrennt)"
[[ "$VARIANTS" =~ ^[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+)*$ ]] || die "Ungültige VARIANTS"
[[ "$MAX_ASSET_MB" =~ ^[0-9]+$ ]] || die "Ungültiges MAX_ASSET_MB"
for b in DRY_RUN FORCE; do [[ "${!b}" == true || "${!b}" == false ]] || die "$b muss true oder false sein"; done

declare -A UPSTREAM=( [sdk]=HomuHomu833/android-sdk-custom [ndk]=HomuHomu833/android-ndk-custom [cmake]=HomuHomu833/cmake-custom )
declare -A PREFIX=(   [sdk]=android-sdk                      [ndk]=android-ndk                      [cmake]=cmake )

# Regex für Asset-Namen: *-<variante>.(tar.xz|tar.gz|zip|7z)
variant_alt="$(tr ',' '\n' <<<"$VARIANTS" | sed 's/\./\\./g' | paste -sd'|')"
VARIANT_RE="-(${variant_alt})\\.(tar\\.xz|tar\\.gz|zip|7z)\$"
max_bytes=$(( MAX_ASSET_MB * 1024 * 1024 ))

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
  [[ -n "${UPSTREAM[$comp]:-}" ]] || die "Unbekannte Komponente '$comp' (erlaubt: sdk, ndk, cmake)"
  repo=${UPSTREAM[$comp]}
  echo "::group::$comp ($repo)"
  releases=$(gh api --paginate "repos/$repo/releases?per_page=100" | jq -s 'add // []') \
    || die "Releases von $repo nicht abrufbar"
  total=$(jq length <<<"$releases")
  echo "Upstream-Releases: $total, Varianten: $VARIANTS"
  c_rel=0; c_none=0

  while IFS= read -r rel; do
    name=$(jq -r .name <<<"$rel"); utag=$(jq -r .tag <<<"$rel")
    want_version "$name" "$utag" || continue
    nassets=$(jq '.assets | length' <<<"$rel")
    if (( nassets == 0 )); then echo "– $name: kein Asset mit Variante $VARIANTS, übersprungen"; c_none=$((c_none + 1)); continue; fi
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
Gespiegelte Varianten: $VARIANTS. Assets unverändert, SHA-256 in den .sha256-Dateien.
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
  done < <(jq -c --arg re "$VARIANT_RE" '
      .[] | select(.draft | not)
      | { name: (if (.name // "") != "" then .name else .tag_name end), tag: .tag_name, pre: .prerelease,
          date: .published_at, url: .html_url,
          assets: [ .assets[] | select(.name | test($re)) | { name, size, digest: (.digest // "") } ] }' <<<"$releases")

  summary+=("| $comp | $total | $c_rel | $c_none |")
  echo "::endgroup::"
done

echo "Neu angelegte Releases: $n_rel_new · hochgeladene Assets: $n_up · übersprungen: $n_skip · Fehler: $n_fail"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Spiegelung HomuHomu833 → $TARGET_REPO"
    echo "Varianten: \`$VARIANTS\` · Trockenlauf: $DRY_RUN · Neu laden: $FORCE"
    echo
    echo "| Komponente | Upstream-Releases | verarbeitet | ohne passendes Asset |"
    echo "|---|---|---|---|"
    printf '%s\n' "${summary[@]}"
    echo
    echo "Neue Releases: **$n_rel_new** · hochgeladene Assets: **$n_up** · übersprungen: **$n_skip** · Fehler: **$n_fail**"
  } >> "$GITHUB_STEP_SUMMARY"
fi
(( n_fail == 0 )) || exit 1
