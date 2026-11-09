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

test_mirror_caller_passes_app_secrets() {
  [ "$(yq '.jobs.mirror.secrets' "$ROOT/.github/workflows/mirror.yaml")" = inherit ] || fail "mirror caller must use secrets: inherit (promo App token)"
}

test_promote_caller() {
  f="$ROOT/.github/workflows/promote.yaml"
  [ -f "$f" ] || fail "no promote caller"
  [ "$(yq '.on.repository_dispatch.types | join(",")' "$f")" = "HelmRelease/$APP.$APP" ] || fail "dispatch types must be HelmRelease/$APP.$APP"
  promote=$(yq '.jobs.promote.uses' "$f"); mirror=$(yq '.jobs.mirror.uses' "$ROOT/.github/workflows/mirror.yaml")
  echo "$promote" | grep -Eq '^twallac10/promo-workflows/\.github/workflows/promote\.yaml@v[0-9]+\.[0-9]+\.[0-9]+$' || fail "promote caller not pinned to a tag: $promote"
  [ "${promote##*@}" = "${mirror##*@}" ] || fail "promote (${promote##*@}) and mirror (${mirror##*@}) pin different promo-workflows tags"
  [ "$(yq '.jobs.promote.secrets' "$f")" = inherit ] || fail "promote caller must use secrets: inherit (promo App token)"
}
