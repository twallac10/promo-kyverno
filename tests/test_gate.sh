G=$ROOT/.github/workflows/gate.yaml

test_gate_jobs() {
  [ -f "$G" ] || fail "no gate.yaml"
  [ "$(yq '.jobs | keys | join(",")' "$G")" = "guardrails,promotion-gate" ] || fail "jobs must be exactly guardrails, promotion-gate"
  [ "$(yq '.jobs["promotion-gate"].needs' "$G")" = guardrails ] || fail "promotion-gate needs guardrails"
  [ "$(yq '.jobs["promotion-gate"].environment' "$G")" = '${{ needs.guardrails.outputs.environment }}' ] || fail "environment must come from guardrails"
  uses=$(yq '.jobs.guardrails.steps[] | select(.uses | test("actions/guardrails")) | .uses' "$G")
  promote=$(yq '.jobs.promote.uses' "$ROOT/.github/workflows/promote.yaml")
  [ "${uses##*@}" = "${promote##*@}" ] || fail "guardrails (${uses##*@}) and promote (${promote##*@}) pin different tags"
  [ "$(yq '.on.pull_request.branches | join(",")' "$G")" = main ] || fail "gate runs on PRs to main"
}

test_gate_fails_closed() {
  # A skipped required check counts as passed, and a job whose needs failed is skipped.
  [ "$(yq '.jobs["promotion-gate"].if' "$G")" = 'always()' ] || fail "promotion-gate must run even when guardrails fails"
  [ "$(yq '.jobs["promotion-gate"].steps[0].env.GUARDRAILS' "$G")" = '${{ needs.guardrails.result }}' ] || fail "gate step must read the guardrails result"
  yq '.jobs["promotion-gate"].steps[0].run' "$G" | grep -q '"$GUARDRAILS" = success' || fail "gate step must fail unless guardrails succeeded"
}

test_gate_never_runs_pr_code() {
  [ "$(yq '.jobs.guardrails.steps[] | select(.uses | test("actions/checkout")) | .with.ref' "$G")" = main ] || fail "guardrails must check out main, not the PR"
  bad=$(yq '.. | select(has("run")) | .run' "$G" | grep -n '\${{' || true)
  [ -z "$bad" ] || fail "run block interpolates an expression: $bad"
}
