{{/*
=============================================================================
Template helpers. These are Go-template functions reused across the chart.

Defined with `{{- define "name" -}}` and called with `{{- include "name" . -}}`.

Why a separate file: avoids copy-pasting the same label set into every YAML,
and makes labels/names consistent across Deployment, Service, ConfigMap, etc.

`{{/* ... */}}` is a HELM comment (stripped before rendering). `# ...` is a
YAML comment (appears in the rendered output). We use {{/* */}} for design
notes and # for runtime documentation.
=============================================================================
*/}}


{{/*
fullname: the canonical name for every object this chart creates. We use
Argo CD's release name directly (one release per tenant -> unique names).
Kubernetes object names max out at 63 chars (DNS-1123 label).
*/}}
{{- define "agent-integration.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}


{{/*
name: the chart's logical app name. Used in app.kubernetes.io/name label
(which is different from the release name).
*/}}
{{- define "agent-integration.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}


{{/*
Standard label set applied to EVERY object.

The `app.kubernetes.io/*` labels are a Kubernetes CONVENTION documented at
https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/.
Tools like Lens, Argo CD, and kubectl recognize them.

The `devops.platform/*` labels are ours, used by Grafana dashboards and
Prometheus alerts to group metrics per tenant.

IMPORTANT: Selector labels (next helper) must be a SUBSET of these, and must
NEVER change after first apply, because Deployment selectors are immutable.
*/}}
{{- define "agent-integration.labels" -}}
app.kubernetes.io/name: {{ include "agent-integration.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: devops-platform
devops.platform/tenant: {{ .Values.tenant | quote }}
devops.platform/environment: {{ .Values.environment | quote }}
{{- end -}}


{{/*
Selector labels: used by Deployment.spec.selector.matchLabels and by
Service.spec.selector to pick pods. MUST stay stable across releases or the
Deployment will refuse to upgrade.

We deliberately keep this set SMALL (just name + instance). Version label
changes on every release; including it in the selector would break upgrades.
*/}}
{{- define "agent-integration.selectorLabels" -}}
app.kubernetes.io/name: {{ include "agent-integration.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}


{{/*
Resolve the ingress host. Explicit `.Values.ingress.host` wins; otherwise we
template `<tenant>.<domain>` so onboarding is just "set a tenant slug."
*/}}
{{- define "agent-integration.ingressHost" -}}
{{- if .Values.ingress.host -}}
{{ .Values.ingress.host }}
{{- else -}}
{{ printf "%s.%s" .Values.tenant .Values.ingress.domain }}
{{- end -}}
{{- end -}}


{{/*
Which Secret name to reference from env. If the tenant supplied
existingSecret (the prod path), use that. Otherwise we create a chart-owned
Secret using the fullname (local-dev path).
*/}}
{{- define "agent-integration.secretName" -}}
{{- if .Values.secret.existingSecret -}}
{{ .Values.secret.existingSecret }}
{{- else -}}
{{ include "agent-integration.fullname" . }}
{{- end -}}
{{- end -}}
