{{/*
Nom court du chart (ex. api-gateway)
*/}}
{{- define "api-gateway.name" -}}
{{ .Chart.Name }}
{{- end }}

{{/*
Nom complet avec nom de la release (ex. prod-api-gateway)
*/}}
{{- define "api-gateway.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
