{{/*
Nom court du chart (ex. config-server)
*/}}
{{- define "config-server.name" -}}
{{ .Chart.Name }}
{{- end }}

{{/*
Nom complet avec nom de la release (ex. prod-config-server)
*/}}
{{- define "config-server.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
