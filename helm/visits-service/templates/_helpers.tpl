{{/*
Nom court du chart (ex. visits-service)
*/}}
{{- define "visits-service.name" -}}
{{ .Chart.Name }}
{{- end }}

{{/*
Nom complet avec nom de la release (ex. prod-visits-service)
*/}}
{{- define "visits-service.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
