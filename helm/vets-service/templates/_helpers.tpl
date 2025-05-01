{{/*
Nom court du chart (ex. vets-service)
*/}}
{{- define "vets-service.name" -}}
{{ .Chart.Name }}
{{- end }}

{{/*
Nom complet avec nom de la release (ex. prod-vets-service)
*/}}
{{- define "vets-service.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
