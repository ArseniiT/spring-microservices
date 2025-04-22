{{/*
Nom court du chart (ex. customers-service)
*/}}
{{- define "customers-service.name" -}}
{{ .Chart.Name }}
{{- end }}

{{/*
Nom complet avec nom de la release (ex. prod-customers-service)
*/}}
{{- define "customers-service.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
