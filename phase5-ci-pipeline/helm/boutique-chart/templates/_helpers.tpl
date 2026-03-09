{{/*
서비스 이름 생성
*/}}
{{- define "boutique.fullname" -}}
{{- .Release.Name }}-{{ .Chart.Name }}
{{- end }}

{{/*
공통 레이블
*/}}
{{- define "boutique.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
이미지 주소 결정
- useGlobalRegistry: false 이면 공식 이미지 (redis 등)
- 기본은 global.registry/name:tag
*/}}
{{- define "boutique.image" -}}
{{- $svc := .svc -}}
{{- $global := .global -}}
{{- if and (hasKey $svc.image "useGlobalRegistry") (not $svc.image.useGlobalRegistry) -}}
{{ $svc.image.repository }}:{{ $svc.image.tag }}
{{- else -}}
{{ $global.registry }}/{{ $svc.image.name }}:{{ $svc.image.tag }}
{{- end -}}
{{- end }}

{{/*
공통 securityContext (컨테이너)
*/}}
{{- define "boutique.containerSecurityContext" -}}
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  privileged: false
  readOnlyRootFilesystem: true
{{- end }}

{{/*
공통 securityContext (파드)
*/}}
{{- define "boutique.podSecurityContext" -}}
securityContext:
  fsGroup: 1000
  runAsGroup: 1000
  runAsNonRoot: true
  runAsUser: 1000
{{- end }}

{{/*
TopologySpreadConstraints
*/}}
{{- define "boutique.topologySpreadConstraints" -}}
{{- $tsc := .Values.topologySpreadConstraints -}}
{{- if $tsc.enabled }}
topologySpreadConstraints:
  - maxSkew: {{ $tsc.maxSkew }}
    topologyKey: {{ $tsc.topologyKey }}
    whenUnsatisfiable: {{ $tsc.whenUnsatisfiable }}
    labelSelector:
      matchLabels:
        app: {{ .svcName }}
{{- end }}
{{- end }}

{{/*
Probe 렌더링 (grpc / http / tcp)
*/}}
{{- define "boutique.probe" -}}
{{- $probe := .probe -}}
{{- if eq $probe.type "grpc" }}
grpc:
  port: {{ $probe.port }}
{{- else if eq $probe.type "http" }}
httpGet:
  path: {{ $probe.path }}
  port: {{ $probe.port }}
  {{- if $probe.httpHeaders }}
  httpHeaders:
  {{- range $probe.httpHeaders }}
  - name: {{ .name }}
    value: {{ .value | quote }}
  {{- end }}
  {{- end }}
{{- else if eq $probe.type "tcp" }}
tcpSocket:
  port: {{ $probe.port }}
{{- end }}
{{- end }}
