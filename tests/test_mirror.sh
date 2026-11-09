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

# Callers pass only the promo App credentials, never every repo secret (no `secrets: inherit`).
app_secrets_only() {
  [ "$(yq -o json -I0 ".jobs.$2.secrets" "$1")" = '{"PROMO_APP_ID":"${{ secrets.PROMO_APP_ID }}","PROMO_APP_PRIVATE_KEY":"${{ secrets.PROMO_APP_PRIVATE_KEY }}"}' ] \
    || fail "$1: pass exactly PROMO_APP_ID and PROMO_APP_PRIVATE_KEY"
}

test_mirror_caller_passes_app_secrets() {
  app_secrets_only "$ROOT/.github/workflows/mirror.yaml" mirror
}

test_promote_caller() {
  f="$ROOT/.github/workflows/promote.yaml"
  [ -f "$f" ] || fail "no promote caller"
  [ "$(yq '.on.repository_dispatch.types | join(",")' "$f")" = "HelmRelease/$APP.$APP" ] || fail "dispatch types must be HelmRelease/$APP.$APP"
  promote=$(yq '.jobs.promote.uses' "$f"); mirror=$(yq '.jobs.mirror.uses' "$ROOT/.github/workflows/mirror.yaml")
  echo "$promote" | grep -Eq '^twallac10/promo-workflows/\.github/workflows/promote\.yaml@v[0-9]+\.[0-9]+\.[0-9]+$' || fail "promote caller not pinned to a tag: $promote"
  [ "${promote##*@}" = "${mirror##*@}" ] || fail "promote (${promote##*@}) and mirror (${mirror##*@}) pin different promo-workflows tags"
  app_secrets_only "$f" promote
}
