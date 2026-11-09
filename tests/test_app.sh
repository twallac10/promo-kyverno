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
  # Helm can't map Kyverno kinds on first install (its CRDs are templates in this
  # release), so no Kyverno object may be a hook: the test pod creates the policy.
  kinds=$(echo "$hooks" | yq '.kind' | grep -v -- '---' | sort -u | tr '\n' ' ')
  [ "$kinds" = "Pod " ] || fail "test hooks must be Pods only, got: $kinds"
  pod=$(echo "$hooks" | yq 'select(.kind=="Pod" and .metadata.name=="kyverno-test-deny") | .spec.containers[0].args[0]')
  [ -n "$pod" ] || fail "no kyverno-test-deny pod"
  echo "$pod" | grep -q 'kind: ValidatingPolicy' || fail "test pod must create its own ValidatingPolicy"
  echo "$pod" | grep -q 'validationActions: \[Deny\]' || fail "test policy must Deny"
  echo "$pod" | grep -q 'trap .*kubectl delete validatingpolicy' || fail "test pod must delete its policy on exit"
  rules=$(render dev | yq -o json -I0 'select(.kind=="ClusterRole" and .metadata.name=="kyverno-test") | .rules')
  for v in create delete get; do
    echo "$rules" | jq -e --arg v "$v" '.[] | select(.apiGroups==["policies.kyverno.io"] and (.resources|index("validatingpolicies")) and (.verbs|index($v)))' >/dev/null \
      || fail "test ClusterRole lacks $v on validatingpolicies: $rules"
  done
  # Only its own policy: an unscoped delete could remove any policy, including the
  # guardrail (oci-only-charts) that Kyverno turns into the API server's VAP.
  echo "$rules" | jq -e '[.[] | select(.apiGroups==["policies.kyverno.io"]) | select((.verbs - ["create"]) != [] and .resourceNames != ["kyverno-test-deny"])] == []' >/dev/null \
    || fail "get/patch/delete on validatingpolicies must be limited to resourceNames [kyverno-test-deny]: $rules"
}
