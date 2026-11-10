{{- define "star23.name" -}}{{/* 리소스 이름을 만드는 공통 템플릿을 정의합니다. 양쪽의 -는 인접한 공백과 줄바꿈을 제거합니다. */ -}}
{{- default .Release.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}{{/* nameOverride가 비어 있으면 릴리스 이름을 사용하고, 최대 63자로 자른 뒤 끝의 하이픈을 제거합니다. */ -}}
{{- end -}}{{/* star23.name 템플릿 정의를 끝냅니다. */ -}}

{{- define "star23.labels" -}}{{/* 여러 리소스에서 재사용할 공통 라벨 템플릿을 정의합니다. */ -}}
app.kubernetes.io/name: {{ include "star23.name" . }}{{/* 현재 컨텍스트(.)로 이름 템플릿을 실행하여 애플리케이션 이름을 넣습니다. */}}
app.kubernetes.io/instance: {{ .Release.Name }}{{/* Helm 릴리스 이름으로 배포 인스턴스를 구분합니다. */}}
app.kubernetes.io/part-of: {{ .Values.labels.partOf | quote }}{{/* 소속 애플리케이션 값을 넣습니다. quote는 값을 큰따옴표로 감싸 YAML 문자열로 표현합니다. */}}
app.kubernetes.io/component: {{ .Values.labels.component | quote }}{{/* api-server, ai-server 등 구성요소의 역할을 문자열로 넣습니다. */}}
team: {{ .Values.labels.team | quote }}{{/* 리소스를 담당하는 팀 값을 문자열로 넣습니다. */}}
env: {{ .Values.labels.environment | quote }}{{/* prod 등 배포 환경 값을 문자열로 넣습니다. */}}
{{- if .Values.labels.framework }}{{/* framework 값이 있을 때만 아래 프레임워크 라벨을 생성합니다. */}}
framework: {{ .Values.labels.framework | quote }}{{/* spring, fastapi 등 사용하는 프레임워크 값을 문자열로 넣습니다. */}}
{{- end }}{{/* framework 라벨의 조건문을 끝냅니다. */}}
{{- end -}}{{/* star23.labels 템플릿 정의를 끝냅니다. */ -}}
