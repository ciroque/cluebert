{{/*
Expand the name of the chart.
*/}}
{{- define "cluebert.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
A default fully qualified app name, truncated at 63 characters for DNS.
If the release name contains the chart name, it is used as the full name.
*/}}
{{- define "cluebert.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "cluebert.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "cluebert.labels" -}}
helm.sh/chart: {{ include "cluebert.chart" . }}
{{ include "cluebert.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "cluebert.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cluebert.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
The image, pinned by digest.
*/}}
{{- define "cluebert.image" -}}
{{- $digest := required "image.digest is required (sha256:...)" .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository $digest -}}
{{- end }}

{{- define "cluebert.host" -}}
{{- required "host is required, e.g. --set host=cluebert.example.com" .Values.host -}}
{{- end }}

{{- define "cluebert.migrateSecretName" -}}
{{- printf "%s-migrate" (include "cluebert.fullname" .) -}}
{{- end }}

{{/*
The Secret's data, shared by the release Secret and the migrate hook's.
*/}}
{{- define "cluebert.secretData" -}}
secret-key-base: {{ required "app.secretKeyBase is required (mix phx.gen.secret)" .Values.app.secretKeyBase | b64enc | quote }}
database-username: {{ required "app.database.username is required" .Values.app.database.username | b64enc | quote }}
database-password: {{ required "app.database.password is required" .Values.app.database.password | b64enc | quote }}
{{- end }}

{{/*
Runtime env for the release (see config/runtime.exs). Pass secretName to
read a different Secret.
*/}}
{{- define "cluebert.env" -}}
{{- $secretName := .secretName | default (include "cluebert.fullname" .) -}}
- name: SECRET_KEY_BASE
  valueFrom:
    secretKeyRef:
      name: {{ $secretName }}
      key: secret-key-base
- name: DATABASE_HOST
  value: {{ required "app.database.hostname is required" .Values.app.database.hostname | quote }}
- name: DATABASE_PORT
  value: {{ .Values.app.database.port | quote }}
- name: DATABASE_NAME
  value: {{ required "app.database.name is required" .Values.app.database.name | quote }}
- name: DATABASE_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ $secretName }}
      key: database-username
- name: DATABASE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ $secretName }}
      key: database-password
- name: POOL_SIZE
  value: {{ .Values.app.poolSize | quote }}
- name: PHX_HOST
  value: {{ include "cluebert.host" . | quote }}
- name: PORT
  value: {{ .Values.service.targetPort | quote }}
{{- end }}
