{{- define "platform-gateway.labels" -}}
app.kubernetes.io/name: {{ .Values.gatewayName }}
app.kubernetes.io/managed-by: helm
app.kubernetes.io/component: gateway-api-platform
{{- range $k, $v := .Values.labels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end -}}
