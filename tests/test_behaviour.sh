# Behaviour tests (Testkube): the signed promotion evidence. Rendered by the
# template-owned chart/templates/_behaviour.tpl from each app's chart/templates/behaviour.yaml.

test_behaviour_workflow() {
  is_template && { echo skip; return 0; }
  for t in $TIERS; do
    wf=$(behaviour "$t" | yq -o json -I0 'select(.kind=="TestWorkflow")')
    echo "$wf" | jq -e --arg app "$APP" '.metadata.name == ($app + "-behaviour") and .metadata.namespace == "testkube"
      and .spec.pod.serviceAccountName == ("promo-behaviour-" + $app)' >/dev/null || fail "$t: workflow: $wf"
    n=$(check_names "$t" | grep -c .); [ "$n" -ge 1 ] || fail "$t: no checks"
    echo "$wf" | jq -e '[.spec.steps[] | select(has("shell")) | .condition] | all(. == "always")' >/dev/null || fail "$t: every check must run even if another failed"
    last=$(echo "$wf" | jq -c '.spec.steps[-1].template')
    echo "$last" | jq -e --arg app "$APP" --arg t "$t" --arg exp "$(check_names "$t" | tr '\n' ' ' | sed 's/ $//')" \
      '.name == "promo-report" and .config == {app: $app, tier: $t, expected: $exp}' >/dev/null || fail "$t: report step: $last"
    for c in $(check_names "$t"); do
      echo "$wf" | jq -r --arg c "$c" '.spec.steps[] | select(.name == $c) | .shell' | grep -q "/data/junit/$c.xml" || fail "$t: $c must write /data/junit/$c.xml"
    done
  done
}

test_behaviour_execution_hook() {
  is_template && { echo skip; return 0; }
  ex=$(behaviour | yq -o json -I0 'select(.kind=="TestWorkflowExecution")')
  echo "$ex" | jq -e --arg app "$APP" '.metadata.name == ($app + "-behaviour-r1") and .metadata.namespace == "testkube"
    and .metadata.annotations["helm.sh/hook"] == "post-install,post-upgrade"
    and .spec.testWorkflow.name == ($app + "-behaviour")' >/dev/null || fail "execution hook: $ex"
}

test_behaviour_rbac_scoped() {
  is_template && { echo skip; return 0; }
  role=$(behaviour | yq -o json -I0 "select(.kind==\"Role\" and .metadata.name==\"promo-behaviour-$APP\")")
  echo "$role" | jq -e --arg app "$APP" '.metadata.namespace == $app and .rules == [{"apiGroups": ["helm.toolkit.fluxcd.io"],
    "resources": ["helmreleases"], "resourceNames": [$app], "verbs": ["get"]}]' >/dev/null || fail "report RBAC must be get on its own HelmRelease only: $role"
  [ "$(behaviour | yq 'select(.kind=="ServiceAccount") | .metadata.name + "/" + .metadata.namespace')" = "promo-behaviour-$APP/testkube" ] || fail "service account"
}
