G=$ROOT/.github/workflows/gate.yaml

test_gate_jobs() {
  [ -f "$G" ] || fail "no gate.yaml"
  [ "$(yq '.jobs | keys | join(",")' "$G")" = "guardrails,promotion-gate" ] || fail "jobs must be exactly guardrails, promotion-gate"
  [ "$(yq '.jobs["promotion-gate"].needs' "$G")" = guardrails ] || fail "promotion-gate needs guardrails"
  [ "$(yq '.jobs["promotion-gate"].environment' "$G")" = "\${{ needs.guardrails.result == 'success' && needs.guardrails.outputs.environment || '' }}" ] || fail "environment must come from guardrails, and only when they passed (no approval request for a PR that already failed)"
  uses=$(yq '.jobs.guardrails.steps[] | select(.uses | test("actions/guardrails")) | .uses' "$G")
  promote=$(yq '.jobs.promote.uses' "$ROOT/.github/workflows/promote.yaml")
  [ "${uses##*@}" = "${promote##*@}" ] || fail "guardrails (${uses##*@}) and promote (${promote##*@}) pin different tags"
  [ "$(yq '.on.pull_request_target.branches | join(",")' "$G")" = main ] || fail "gate runs on PRs to main"
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

test_gate_uses_mains_definition() {
  # On pull_request GitHub runs the PR's own gate.yaml, which a PR could rewrite to pass.
  # pull_request_target runs main's; safe here because the gate runs no PR code.
  [ "$(yq '.on | keys | join(",")' "$G")" = pull_request_target ] || fail "gate must trigger on pull_request_target only"
  perms=$(yq -o json -I0 '.permissions' "$G")
  [ "$perms" = '{"contents":"read","deployments":"read","pull-requests":"read","attestations":"read"}' ] || fail "gate permissions must be read-only: $perms"
}
