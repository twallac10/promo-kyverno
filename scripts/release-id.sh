#!/usr/bin/env bash
# Release id of a tier's release.yaml: sha256 of its content without the id
# annotation itself. Identical release.yaml files have identical ids in every
# tier. The HelmRelease carries it as event.toolkit.fluxcd.io/release-id, so
# Flux events say exactly which release was tested.
# Usage: release-id.sh <release.yaml>          print the id
#        release-id.sh --write <release.yaml>  set the annotation in place
set -euo pipefail
key=event.toolkit.fluxcd.io/release-id
write=0
[ "${1:-}" = --write ] && { write=1; shift; }
f=$1
id=sha256:$(KEY=$key yq -o json -I0 '
  del(.metadata.annotations[strenv(KEY)]) |
  with(select((.metadata.annotations | length) == 0); del(.metadata.annotations))' "$f" | shasum -a 256 | cut -d' ' -f1)
if [ $write = 1 ]; then
  KEY=$key ID=$id yq -i '(select(.kind=="HelmRelease") | .metadata.annotations[strenv(KEY)]) = strenv(ID)' "$f"
else
  echo "$id"
fi
