{{/*
Nom court du chart (ex. discovery-server)
*/}}
{{- define "discovery-server.name" -}}
{{ .Chart.Name }}
{{- end }}

{{/*
Nom complet avec nom de la release (ex. prod-discovery-server)
*/}}
{{- define "discovery-server.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
