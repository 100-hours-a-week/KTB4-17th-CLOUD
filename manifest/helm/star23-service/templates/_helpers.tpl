{{- define "star23.name" -}}
{{- default .Release.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "star23.labels" -}}
app.kubernetes.io/name: {{ include "star23.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: {{ .Values.labels.partOf | quote }}
app.kubernetes.io/component: {{ .Values.labels.component | quote }}
team: {{ .Values.labels.team | quote }}
env: {{ .Values.labels.environment | quote }}
{{- if .Values.labels.framework }}
framework: {{ .Values.labels.framework | quote }}
{{- end }}
{{- end -}}
