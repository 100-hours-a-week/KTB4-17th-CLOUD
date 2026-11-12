{{/* Resource name
 * nameOverride 또는 릴리스 이름을 리소스 이름과 선택 라벨의 공통 기준으로 사용한다.
 */}}
{{- define "star23.name" -}}
{{- default .Release.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Common labels
 * 이름·릴리스 라벨로 Service와 Pod를 연결하고, 나머지 라벨로 소속과 환경을 표시한다.
 */}}
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
