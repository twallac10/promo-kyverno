# Shared helpers for tests/test_*.sh. bash 3.2 compatible.
TIERS="dev stg prd"

fail() { echo "$*" >&2; exit 1; }

# Kubernetes JSON schemas for Flux CRDs, generated from the installed flux CLI
# and cached under .cache/ keyed by its version.
flux_schemas() {
  local v dir
  v=$(flux version --client -o json 2>/dev/null | jq -r .flux)
  dir="$ROOT/.cache/schemas-$v"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir.tmp"
    flux install --export | yq -o json -I0 'select(.kind=="CustomResourceDefinition")' |
      jq -c '.spec as $s | $s.versions[] | {g: $s.group, k: ($s.names.kind|ascii_downcase), v: .name, schema: .schema.openAPIV3Schema}' |
      while read -r line; do
        g=$(echo "$line" | jq -r .g); k=$(echo "$line" | jq -r .k); ver=$(echo "$line" | jq -r .v)
        mkdir -p "$dir.tmp/$g"
        echo "$line" | jq '.schema | walk(if type=="object" and has("properties") and (has("additionalProperties")|not) and ((."x-kubernetes-preserve-unknown-fields")|not) then .additionalProperties=false else . end)' > "$dir.tmp/$g/${k}_${ver}.json"
      done
    mv "$dir.tmp" "$dir"
  fi
  echo "$dir"
}

# kubeconform -strict with Flux schemas; reads manifests on stdin.
kconform() {
  local s
  s=$(flux_schemas)
  kubeconform -strict -summary -schema-location default \
    -schema-location "$s/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" -
}

build_tier() { kubectl kustomize "$ROOT/tiers/$1"; }

APP=$(yq .metadata.name "$ROOT/base/helmrelease.yaml")
is_template() { [ "$APP" = example ]; }

chart_deps() {
  ls "$ROOT"/chart/charts/*.tgz >/dev/null 2>&1 || helm dependency build "$ROOT/chart" >&2
}

# Render the wrapper chart the way Flux installs it for a tier: chart version
# with a +build suffix (OCI digest) and the tier's merged HelmRelease values.
render() {
  local t=${1:-dev} tmp
  chart_deps
  tmp=$(mktemp -d)
  cp -R "$ROOT/chart" "$tmp/chart"
  yq -i '.version = .version + "+abc123def"' "$tmp/chart/Chart.yaml"
  build_tier "$t" | yq 'select(.kind=="HelmRelease") | .spec.values // {}' > "$tmp/values.yaml"
  helm template "$APP" "$tmp/chart" -n "$APP" -f "$tmp/values.yaml"
}

# Test hook resources in a rendered manifest stream on stdin.
test_hooks() { yq 'select(.metadata.annotations."helm.sh/hook" == "test")'; }
