test_each_tier_builds() {
  for t in $TIERS; do
    build_tier "$t" | kconform || fail "tier $t does not build or validate"
  done
}

test_release_only_promotable_fields() {
  for t in $TIERS; do
    bad=$(yq ea -o json -I0 '[.] ' "$ROOT/tiers/$t/release.yaml" | jq -r '
      .[] as $d | $d | paths(scalars) | map(tostring) | join(".") as $p
      | select(
          ($p | test("^(apiVersion|kind|metadata\\.name|metadata\\.namespace)$")) or
          ($d.kind == "OCIRepository" and ($p == "spec.ref.digest" or $p == "metadata.annotations.promo.twallac10.dev/chart-version")) or
          ($d.kind == "HelmRelease" and (($p | startswith("spec.values.")) or $p == "metadata.annotations.event.toolkit.fluxcd.io/release-id"))
          | not)
      | "\($d.kind):\($p)"')
    [ -z "$bad" ] || fail "tier $t release.yaml sets non-promotable fields: $bad"
  done
}

test_tier_edit_is_isolated() {
  tmp=$(mktemp -d); cp -R "$ROOT/base" "$ROOT/tiers" "$tmp/"
  for t in stg prd; do kubectl kustomize "$tmp/tiers/$t" > "$tmp/$t.before"; done
  yq -i '(select(.kind=="HelmRelease") | .spec.values.isolationProbe) = "changed"' "$tmp/tiers/dev/tier.yaml"
  kubectl kustomize "$tmp/tiers/dev" | grep -q isolationProbe || fail "dev edit not applied"
  for t in stg prd; do
    kubectl kustomize "$tmp/tiers/$t" | diff -q - "$tmp/$t.before" >/dev/null || fail "dev edit changed $t"
  done
}

test_helmrelease_tests_enabled() {
  for t in $TIERS; do
    hr=$(build_tier "$t" | yq -o json 'select(.kind=="HelmRelease")')
    [ "$(echo "$hr" | jq -r .spec.test.enable)" = true ] || fail "$t: test.enable"
    [ "$(echo "$hr" | jq -r .spec.test.ignoreFailures)" = false ] || fail "$t: test.ignoreFailures"
    [ "$(echo "$hr" | jq -r .spec.chartRef.kind)" = OCIRepository ] || fail "$t: chartRef.kind"
  done
}

test_remediation_matches_onfailure() {
  # dev = hold (no remediation), stg/prd = rollback with no retries.
  for t in $TIERS; do
    r=$(build_tier "$t" | yq -o json 'select(.kind=="HelmRelease") | .spec.upgrade.remediation // {}')
    case $t in
      dev) [ "$(echo "$r" | jq -r '.remediateLastFailure // false')" = false ] || fail "dev must hold";;
      *) [ "$(echo "$r" | jq -c '{strategy, retries, remediateLastFailure}')" = '{"strategy":"rollback","retries":0,"remediateLastFailure":true}' ] || fail "$t must roll back: $r";;
    esac
  done
}
