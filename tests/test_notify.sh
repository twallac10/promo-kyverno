test_notify_shape() {
  for t in $TIERS; do
    out=$(build_tier "$t")
    p=$(echo "$out" | yq -o json -I0 'select(.kind=="Provider")')
    [ "$(echo "$p" | grep -c .)" = 1 ] || fail "$t: want exactly one Provider"
    echo "$p" | jq -e --arg app "$APP" '.metadata.name == "promo-dispatch" and .metadata.namespace == $app
      and .spec.type == "githubdispatch" and .spec.address == "https://github.com/twallac10/promo-" + $app
      and .spec.secretRef.name == "promo-dispatch"' >/dev/null || fail "$t: Provider: $p"
    [ "$(echo "$out" | yq 'select(.kind=="Alert") | .metadata.name' | grep -v -- '---' | sort | tr '\n' ' ')" = "promote-failure " ] \
      || fail "$t: want only Alert promote-failure (promotion follows the signed Testkube report)"
    for a in promote-failure; do
      echo "$out" | yq -o json -I0 "select(.kind==\"Alert\" and .metadata.name==\"$a\")" | jq -e --arg app "$APP" --arg t "$t" '
        .metadata.namespace == $app and .spec.providerRef.name == "promo-dispatch"
        and .spec.eventSources == [{"kind": "HelmRelease", "name": $app}]
        and .spec.eventMetadata == {"tier": $t, "app": $app}' >/dev/null || fail "$t: $a sources or metadata"
    done
    f=$(echo "$out" | yq -o json -I0 'select(.kind=="Alert" and .metadata.name=="promote-failure") | .spec')
    echo "$f" | jq -e '.eventSeverity == "error" and .inclusionList == ["^Helm (install|upgrade|test) failed"]' >/dev/null || fail "$t: failure filter: $f"
  done
}

test_notify_not_promotable() {
  for t in $TIERS; do
    [ -z "$(yq 'select(.kind=="Provider" or .kind=="Alert") | .kind' "$ROOT/tiers/$t/release.yaml" | grep -v -- '---')" ] \
      || fail "$t: notifications in release.yaml would be promoted"
  done
}
