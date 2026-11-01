#!/usr/bin/env bash
# Spiegelt Release-Assets aus nullij/sclrepo 1:1 in dieses Repo (gleicher Tag) und legt je Datei <name>.sha256 an.
# Idempotent: vorhandene Assets werden übersprungen (FORCE=true lädt neu hoch). Jede Datei einzeln, danach gelöscht (Platz).
set -euo pipefail
SRC_REPO="${SRC_REPO:-nullij/sclrepo}"
TARGET_REPO="${TARGET_REPO:?}"
TAGS="${TAGS:-android-sdk-37.0.0,flutter-sdk,kotlinlsp,v36.1.0}"
DRY_RUN="${DRY_RUN:-true}"
FORCE="${FORCE:-false}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

IFS=',' read -ra tag_list <<<"$TAGS"
for tag in "${tag_list[@]}"; do
  tag="$(echo "$tag" | xargs)"; [ -n "$tag" ] || continue
  echo "::group::$tag"
  src_json="$(gh api "repos/$SRC_REPO/releases/tags/$tag")"
  mapfile -t names < <(jq -r '.assets[].name' <<<"$src_json")
  echo "Quelle: ${#names[@]} Assets: ${names[*]}"
  if ! gh api "repos/$TARGET_REPO/releases/tags/$tag" >/dev/null 2>&1; then
    echo "Release $tag fehlt im Ziel."
    if [ "$DRY_RUN" != "true" ]; then
      gh release create "$tag" -R "$TARGET_REPO" --title "$tag" \
        --notes "Spiegel von https://github.com/$SRC_REPO/releases/tag/$tag"$'\n'"Assets unverändert, SHA-256 in den .sha256-Dateien. Herkunft und Lizenz siehe Upstream-Repo https://github.com/$SRC_REPO."
    fi
  fi
  have="$(gh api "repos/$TARGET_REPO/releases/tags/$tag" --jq '.assets[].name' 2>/dev/null || true)"
  for name in "${names[@]}"; do
    case "$name" in *.sha256) continue ;; esac
    if grep -qxF "$name" <<<"$have" && grep -qxF "$name.sha256" <<<"$have" && [ "$FORCE" != "true" ]; then
      echo "überspringe $name (vorhanden)"; continue
    fi
    if [ "$DRY_RUN" = "true" ]; then echo "[dry-run] würde $name spiegeln"; continue; fi
    dir="$WORK/$tag"; mkdir -p "$dir"
    echo "lade $name …"
    gh release download "$tag" -R "$SRC_REPO" -p "$name" -D "$dir" --clobber
    ( cd "$dir" && sha256sum "$name" > "$name.sha256" && cat "$name.sha256" )
    up=("$dir/$name" "$dir/$name.sha256")
    gh release upload "$tag" "${up[@]}" -R "$TARGET_REPO" --clobber
    rm -rf "$dir"
  done
  echo "::endgroup::"
done
