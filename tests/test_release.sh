release_id_ann() { yq 'select(.kind=="HelmRelease") | .metadata.annotations."event.toolkit.fluxcd.io/release-id"' "$1"; }

test_release_id_current() {
  for t in $TIERS; do
    f="$ROOT/tiers/$t/release.yaml"
    want=$("$ROOT/scripts/release-id.sh" "$f")
    echo "$want" | grep -Eq '^sha256:[0-9a-f]{64}$' || fail "$t: bad id: $want"
    [ "$(release_id_ann "$f")" = "$want" ] || fail "$t: release-id annotation stale: run scripts/release-id.sh --write $f"
  done
}

test_release_id_ignores_own_annotation() {
  f=$(mktemp); cp "$ROOT/tiers/dev/release.yaml" "$f"
  id=$("$ROOT/scripts/release-id.sh" "$f")
  yq -i '(select(.kind=="HelmRelease") | .metadata.annotations."event.toolkit.fluxcd.io/release-id") = "x"' "$f"
  [ "$("$ROOT/scripts/release-id.sh" "$f")" = "$id" ] || fail "id depends on its own annotation"
  yq -i 'del(select(.kind=="HelmRelease") | .metadata.annotations)' "$f"
  [ "$("$ROOT/scripts/release-id.sh" "$f")" = "$id" ] || fail "id differs once the annotation is removed (empty annotations map)"
  yq -i '(select(.kind=="HelmRelease") | .spec.values.probe) = "changed"' "$f"
  [ "$("$ROOT/scripts/release-id.sh" "$f")" != "$id" ] || fail "id ignores a shared value change"
  cp "$ROOT/tiers/dev/release.yaml" "$f"
  yq -i '(select(.kind=="OCIRepository") | .spec.ref.digest) = "sha256:1111111111111111111111111111111111111111111111111111111111111111"' "$f"
  [ "$("$ROOT/scripts/release-id.sh" "$f")" != "$id" ] || fail "id ignores a digest change"
}

test_release_id_tier_independent() {
  tmp=$(mktemp -d); cp -R "$ROOT/tiers" "$tmp/"
  cp "$tmp/tiers/dev/release.yaml" "$tmp/tiers/stg/release.yaml"
  [ "$("$ROOT/scripts/release-id.sh" "$tmp/tiers/stg/release.yaml")" = "$(release_id_ann "$tmp/tiers/stg/release.yaml")" ] \
    || fail "a promoted (copied) release.yaml must keep a current id"
}

test_release_id_write() {
  f=$(mktemp); cp "$ROOT/tiers/dev/release.yaml" "$f"
  yq -i '(select(.kind=="HelmRelease") | .spec.values.probe) = "changed"' "$f"
  "$ROOT/scripts/release-id.sh" --write "$f"
  [ "$(release_id_ann "$f")" = "$("$ROOT/scripts/release-id.sh" "$f")" ] || fail "--write did not set the current id"
}
