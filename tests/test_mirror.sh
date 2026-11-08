test_chart_name_matches_ocirepository() {
  url=$(yq .spec.url "$ROOT/base/ocirepository.yaml")
  case $url in oci://ghcr.io/twallac10/charts/*) ;; *) fail "OCIRepository outside our GHCR prefix: $url";; esac
  name=$(yq .name "$ROOT/chart/Chart.yaml")
  [ "$name" = "$(yq .wrapper.name "$ROOT/mirror/chart.yaml")" ] || fail "Chart.yaml name $name != mirror wrapper.name"
  [ "$name" = "${url##*/}" ] || fail "helm push publishes $name but clusters pull ${url##*/}"
}

test_mirror_caller_pinned() {
  uses=$(yq '.jobs[].uses' "$ROOT/.github/workflows/mirror.yaml")
  echo "$uses" | grep -Eq '^twallac10/promo-workflows/\.github/workflows/mirror\.yaml@v[0-9]+\.[0-9]+\.[0-9]+$' || fail "mirror caller not pinned to a tag: $uses"
}
