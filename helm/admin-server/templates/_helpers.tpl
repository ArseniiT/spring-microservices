{{/*
Nom court du chart (ex. admin-server)
*/}}
{{- define "admin-server.name" -}}
{{ .Chart.Name }}
{{- end }}

{{/*
Nom complet avec nom de la release (ex. prod-admin-server)
*/}}
{{- define "admin-server.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
