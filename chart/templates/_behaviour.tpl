{{- /*
Template-owned (promo-app-template, synced by promo-fleet's task repos:sync).

Behaviour tests run by Testkube: the promotion evidence. An app's
templates/behaviour.yaml calls:
  {{ include "promo.behaviour" (dict "ctx" . "checks" (list (dict "name" "<check>" "script" "<sh>") ...)) }}
and adds any extra RBAC its checks need for ServiceAccount promo-behaviour-<release> (namespace testkube).

Renders: the test ServiceAccount, get on its own HelmRelease only (for the
report), the TestWorkflow (each check writes /data/junit/<check>.xml and runs
even if another failed; the last step is promo-fleet's promo-report template),
and a post-install/post-upgrade TestWorkflowExecution so every Helm revision is
tested once. Values: behaviour.tier (tier.yaml), promoTest.image.
*/}}
{{- define "promo.behaviour" -}}
{{- $ctx := .ctx -}}
{{- $app := $ctx.Release.Name -}}
{{- $tier := required "behaviour.tier must be set in tiers/<tier>/tier.yaml" $ctx.Values.behaviour.tier -}}
{{- $names := list -}}
{{- range .checks }}{{ $names = append $names .name }}{{ end -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: promo-behaviour-{{ $app }}
  namespace: testkube
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: promo-behaviour-{{ $app }}
  namespace: {{ $ctx.Release.Namespace }}
rules:
  - apiGroups: [helm.toolkit.fluxcd.io]
    resources: [helmreleases]
    resourceNames: [{{ $app }}]
    verbs: [get]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: promo-behaviour-{{ $app }}
  namespace: {{ $ctx.Release.Namespace }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: promo-behaviour-{{ $app }}
subjects:
  - kind: ServiceAccount
    name: promo-behaviour-{{ $app }}
    namespace: testkube
---
apiVersion: testworkflows.testkube.io/v1
kind: TestWorkflow
metadata:
  name: {{ $app }}-behaviour
  namespace: testkube
spec:
  pod:
    serviceAccountName: promo-behaviour-{{ $app }}
  container:
    image: {{ $ctx.Values.promoTest.image }}
  steps:
    {{- range .checks }}
    - name: {{ .name }}
      condition: always
      shell: |
        mkdir -p /data/junit; start=$(date +%s); log=/tmp/{{ .name }}.log
        if ( set -e
        {{- .script | nindent 8 }}
        ) > "$log" 2>&1; then r=0; else r=$?; fi
        cat "$log"; t=$(( $(date +%s) - start ))
        if [ $r = 0 ]; then
          printf '<testcase name="%s" classname="%s" time="%s"/>\n' {{ .name }} {{ $app }} "$t" > /data/junit/{{ .name }}.xml
        else
          msg=$(tail -c 2000 "$log" | sed 's/]]>/]] >/g')
          printf '<testcase name="%s" classname="%s" time="%s"><failure message="check failed (exit %s)"><![CDATA[%s]]></failure></testcase>\n' \
            {{ .name }} {{ $app }} "$t" "$r" "$msg" > /data/junit/{{ .name }}.xml
        fi
        exit $r
    {{- end }}
    - template:
        name: promo-report
        config:
          app: {{ $app }}
          tier: {{ $tier }}
          expected: {{ join " " $names | quote }}
---
# Each Helm revision (install or upgrade) runs the behaviour tests once.
apiVersion: testworkflows.testkube.io/v1
kind: TestWorkflowExecution
metadata:
  name: {{ $app }}-behaviour-r{{ $ctx.Release.Revision }}
  namespace: testkube
  annotations:
    helm.sh/hook: post-install,post-upgrade
    helm.sh/hook-delete-policy: before-hook-creation
spec:
  testWorkflow:
    name: {{ $app }}-behaviour
{{- end -}}
