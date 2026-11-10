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

test_kyverno_smoke_and_behaviour() {
  # Smoke (Helm): the upstream readiness checks. Behaviour (Testkube): the admission path end to end.
  hooks=$(render dev | test_hooks | yq '.kind + "/" + .metadata.name' | grep -v -- '---' | sort | tr '\n' ' ')
  [ "$hooks" = "Pod/kyverno-admission-controller-metrics Pod/kyverno-reports-controller-metrics " ] || fail "smoke hooks: $hooks"
  [ "$(check_names | tr '\n' ' ')" = "deny-dry-run " ] || fail "behaviour checks: $(check_names)"
  s=$(behaviour | yq 'select(.kind=="TestWorkflow") | .spec.steps[] | select(.name == "deny-dry-run") | .shell')
  echo "$s" | grep -q 'kind: ValidatingPolicy' || fail "check must create its own test policy"
  echo "$s" | grep -q 'trap .*kubectl delete validatingpolicy' || fail "check must delete its policy on exit"
  echo "$s" | grep -q 'promo kyverno test denial' || fail "check must expect the test denial"
}

test_kyverno_behaviour_rbac() {
  rules=$(render dev | yq -o json -I0 'select(.kind=="ClusterRole" and .metadata.name=="kyverno-behaviour") | .rules')
  echo "$rules" | jq -e '[.[] | select(.apiGroups==["policies.kyverno.io"]) | select((.verbs - ["create"]) != [] and .resourceNames != ["kyverno-test-deny"])] == []' >/dev/null \
    || fail "get/patch/delete on validatingpolicies only for kyverno-test-deny: $rules"
  [ "$(render dev | yq 'select(.kind=="ClusterRoleBinding" and .metadata.name=="kyverno-behaviour") | .subjects[0].name + "/" + .subjects[0].namespace')" = promo-behaviour-kyverno/testkube ] || fail "binding subject"
  [ "$(render dev | yq 'select(.kind=="Role" and .metadata.name=="kyverno-behaviour") | .metadata.namespace + ":" + (.rules[0].verbs | join(","))')" = "default:create" ] || fail "dry-run pods in default"
  [ -z "$(render dev | yq 'select(.metadata.name=="kyverno-test") | .kind' | grep -v -- '---')" ] || fail "old Helm-test RBAC must be gone"
}
