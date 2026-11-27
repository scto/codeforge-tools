#!/usr/bin/env bash
# =============================================================================
# build-catalog.sh – erzeugt catalog.json: alle veröffentlichten Releases dieses Repos in kompakter Form.
#
# Wozu: Der SDK-Manager von CodeForgeMobile (codeforge-env) las bisher die Release-Liste über die GitHub-API –
# mehrere Seiten à 100 Releases, mehrere MB JSON, Rate-Limit 60/Stunde ohne Token. Beim ersten Start dauerte das
# lange. catalog.json enthält nur, was codeforge-env braucht, und kommt über raw.githubusercontent.com (CDN, kein
# API-Limit). Dasselbe Prinzip wie store.json im Plugin-Store.
#
# Format: Array wie die Releases-API, nur mit den genutzten Feldern:
#   [{"tag_name","name","prerelease","published_at",
#     "assets":[{"name","size","digest","browser_download_url"}]}]
#
# Aufruf: GH_TOKEN=… TARGET_REPO=owner/repo bash scripts/build-catalog.sh [--commit]
#   --commit  catalog.json committen und pushen, wenn sich der Inhalt geändert hat
# =============================================================================
set -euo pipefail
: "${GH_TOKEN:?GH_TOKEN fehlt}"
: "${TARGET_REPO:?TARGET_REPO fehlt (owner/repo)}"
[[ "$TARGET_REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { echo "::error::Ungültiges TARGET_REPO" >&2; exit 1; }
OUT="${CATALOG_FILE:-catalog.json}"
commit=false
[[ "${1:-}" == "--commit" ]] && commit=true

tmp=$(mktemp)
gh api --paginate "repos/$TARGET_REPO/releases?per_page=100" | jq -s '
  add // []
  | map(select(.draft | not))
  | map({ tag_name, name: (.name // ""), prerelease, published_at,
          assets: [ .assets[] | { name, size, digest: (.digest // ""), browser_download_url } ] })
  | sort_by(.published_at) | reverse' > "$tmp"
n=$(jq length "$tmp")
(( n > 0 )) || { echo "::error::Keine Releases gefunden – catalog.json bleibt unverändert" >&2; rm -f "$tmp"; exit 1; }
# Stabiler Inhalt: ohne Zeitstempel, damit unveränderte Releases keinen Commit auslösen
jq -c '.' "$tmp" > "$OUT"; rm -f "$tmp"
echo "catalog.json: $n Releases, $(jq '[.[].assets[]] | length' "$OUT") Assets, $(( $(stat -c %s "$OUT") / 1024 )) KB"

if [[ "$commit" == true ]]; then
  if git diff --quiet -- "$OUT" 2>/dev/null && git ls-files --error-unmatch "$OUT" >/dev/null 2>&1; then
    echo "catalog.json unverändert"; exit 0
  fi
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git add "$OUT"
  git commit -q -m "catalog.json aktualisieren ($n Releases)"
  for i in 1 2 3; do
    git pull -q --rebase origin "$(git rev-parse --abbrev-ref HEAD)" && git push -q && exit 0
    sleep $((i * 5))
  done
  echo "::error::catalog.json konnte nicht gepusht werden" >&2; exit 1
fi
