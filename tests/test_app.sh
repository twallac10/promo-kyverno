test_kyverno_controllers() {
  deps=$(render dev | yq 'select(.kind=="Deployment") | .metadata.name' | grep -v -- '---' | sort | tr '\n' ' ')
  [ "$deps" = "kyverno-admission-controller kyverno-reports-controller " ] || fail "deployments: $deps"
}

test_kyverno_excludes_system_namespaces() {
  w=$(render dev | yq 'select(.kind=="ConfigMap" and .metadata.name=="kyverno") | .data.webhooks')
  for ns in kube-system flux-system; do
    echo "$w" | jq -e --arg ns "$ns" '[.namespaceSelector.matchExpressions[] | select(.key=="kubernetes.io/metadata.name" and .operator=="NotIn") | .values[]] | index($ns) != null' >/dev/null \
      || fail "webhooks do not exclude $ns: $w"
  done
}

test_kyverno_deny_test() {
  hooks=$(render dev | test_hooks)
  echo "$hooks" | yq -e 'select(.kind=="ValidatingPolicy") | .spec.validationActions[] | select(. == "Deny")' >/dev/null || fail "no Deny test policy"
  echo "$hooks" | yq -e 'select(.kind=="Pod" and .metadata.name=="kyverno-test-deny")' >/dev/null || fail "no kyverno-test-deny pod"
  [ "$(echo "$hooks" | yq 'select(.kind=="ValidatingPolicy") | .metadata.annotations."helm.sh/hook-weight"')" -lt \
    "$(echo "$hooks" | yq 'select(.kind=="Pod" and .metadata.name=="kyverno-test-deny") | .metadata.annotations."helm.sh/hook-weight" // "0"')" ] \
    || fail "policy must be created before the pod"
}
