test_labels_with_build_suffix() {
  is_template && { echo skip; return 0; }
  for t in $TIERS; do
    bad=$(render "$t" | yq -o json -I0 '.metadata.labels // {} | to_entries[] | .value' | tr -d '"' |
      grep -Ev '^(([A-Za-z0-9][-A-Za-z0-9_.]*)?[A-Za-z0-9])?$' || true)
    [ -z "$bad" ] || fail "$t: invalid label values: $bad"
    long=$(render "$t" | yq -o json -I0 '.metadata.labels // {} | to_entries[] | .value' | tr -d '"' | awk 'length > 63')
    [ -z "$long" ] || fail "$t: label values over 63 chars: $long"
  done
}

test_has_tests() {
  is_template && { echo skip; return 0; }
  n=$(render dev | test_hooks | yq 'select(.kind=="Pod") | .metadata.name' | grep -vc -- '---' || true)
  [ "$n" -ge 1 ] || fail "no helm test pods"
}

test_chart_pins_match_mirror() {
  is_template && { echo skip; return 0; }
  m="$ROOT/mirror/chart.yaml" c="$ROOT/chart/Chart.yaml"
  [ "$(yq '.dependencies | length' "$c")" = 1 ] || fail "wrapper must have exactly one dependency"
  [ "$(yq '.dependencies[0].name' "$c")" = "$(yq .upstream.chart "$m")" ] || fail "dependency name != mirror upstream.chart"
  [ "$(yq '.dependencies[0].version' "$c")" = "$(yq .upstream.version "$m")" ] || fail "dependency version != mirror upstream.version"
  [ "$(yq '.dependencies[0].repository' "$c")" = "$(yq .upstream.repo "$m")" ] || fail "dependency repo != mirror upstream.repo"
}

test_images_pinned() {
  is_template && { echo skip; return 0; }
  for t in $TIERS; do
    bad=$(render "$t" | yq '.. | select(has("image") and (.image | type) == "!!str") | .image' | grep -v -- '---' |
      grep -Ev '(@sha256:[0-9a-f]{64}|:v?[0-9]+\.[0-9]+[0-9A-Za-z.+-]*)$' || true)
    [ -z "$bad" ] || fail "$t: unpinned images: $bad"
  done
}
