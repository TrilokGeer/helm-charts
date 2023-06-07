{{/*
Expand the name of the chart.
*/}}
{{- define "spire-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "spire-server.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Allow the release namespace to be overridden for multi-namespace deployments in combined charts
*/}}
{{- define "spire-server.namespace" -}}
  {{- if .Values.namespaceOverride -}}
    {{- .Values.namespaceOverride -}}
  {{- else -}}
    {{- .Release.Namespace -}}
  {{- end -}}
{{- end -}}

{{- define "spire-server.podMonitor.namespace" -}}
  {{- if ne (len .Values.telemetry.prometheus.podMonitor.namespace) 0 }}
    {{- .Values.telemetry.prometheus.podMonitor.namespace }}
  {{- else if ne (len (dig "telemetry" "prometheus" "podMonitor" "namespace" "" .Values.global)) 0 }}
    {{- .Values.global.telemetry.prometheus.podMonitor.namespace }}
  {{- else }}
    {{- include "spire-server.namespace" . }}
  {{- end }}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "spire-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "spire-server.labels" -}}
helm.sh/chart: {{ include "spire-server.chart" . }}
{{ include "spire-server.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "spire-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spire-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "spire-server.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "spire-server.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "spire-server.upstream-ca-secret" -}}
{{- $root := . }}
{{- with .Values.upstreamAuthority.disk -}}
{{- if eq (.secret.create | toString) "true" -}}
{{ include "spire-server.fullname" $root }}-upstream-ca
{{- else -}}
{{ default (include "spire-server.fullname" $root) .secret.name }}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "spire-controller-manager.fullname" -}}
{{ include "spire-server.fullname" . | trimSuffix "-server" }}-controller-manager
{{- end }}

{{- define "spire-server.serviceAccountAllowedList" }}
{{- if ne (len .Values.nodeAttestor.k8s_psat.serviceAccountAllowList) 0 }}
{{- .Values.nodeAttestor.k8s_psat.serviceAccountAllowList | toJson }}
{{- else }}
[{{ printf "%s:%s-agent" .Release.Namespace .Release.Name | quote }}]
{{- end }}
{{- end }}

{{/*
Take a copy of a plugin values, and output mergable config
*/}}
{{- define "spire-server.config_mergeable" }}
{{- $config := . }}
{{- $newConfig := dict }}
{{- range (list "plugin_cmd" "plugin_checksum" "plugin_data") }}
{{- if hasKey $config . }}
{{- $_ := set $newConfig . (index $config .) }}
{{- end }}
{{- end }}
{{- toYaml $newConfig }}
{{- end }}

{{/*
Take a copy of the config and merge in plugins passed through as root.
*/}}
{{- define "spire-server.config_merge" }}
{{- $newConfig := .config | fromYaml }}
{{- $root := .root }}
{{- $sections := list (list "nodeAttestor" "NodeAttestor") (list "notifier" "Notifier") (list "keyManager" "KeyManager") (list "upstreamAuthority" "UpstreamAuthority") }}
{{- range $section := $sections }}
{{- $vsection := index $section 0 }}
{{- $csection := index $section 1 }}
{{- if not (hasKey $newConfig.plugins $csection) }}
{{- $_ := set $newConfig.plugins $csection (dict) }}
{{- end }}
{{- $cdict := index $newConfig.plugins $csection }}
{{- $vdict := index $root.Values $vsection }}
{{- range $name, $v := $vdict }}
{{- $oldV := index $cdict $name | default (dict) }}
{{- $newV := $oldV | mustMerge (include "spire-server.config_mergeable" $v | fromYaml) }}
{{- if or (not (hasKey $v "enabled")) (eq ($v.enabled | toString) "true") }}
{{- $_ := set $cdict $name $newV }}
{{- end }}
{{- end }}
{{- if eq (len $cdict) 0 }}
{{- $_ := unset $newConfig.plugins $csection }}
{{- end }}
{{- end }}
{{- $newConfig | toYaml }}
{{- end }}

{{/*
Take a copy of the plugin section and return a yaml string based version
reformatted from a dict of dicts to a dict of lists of dicts
*/}}
{{- define "spire-server.plugins_reformat" }}
{{- range $type, $v := . }}
{{ $type }}:
  {{- $names := sortAlpha (keys $v) }}
  {{- range $name := $names }}
    {{- $v2 := index $v $name }}
    - {{ $name }}: {{ $v2 | toYaml | nindent 8 }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Take a copy of the config as a yaml config and root var.
Merge in .root.Values.plugin into config,
Reformat the plugin section from a dict of dicts to a dict of lists of dicts,
and export it back as as json string.
This makes it much easier for users to merge in plugin configs, as dicts are easier
to merge in values, but spire needs arrays.
*/}}
{{- define "spire-server.reformat-and-yaml2json" -}}
{{- $config := include "spire-server.config_merge" . | fromYaml }}
{{- $plugins := include "spire-server.plugins_reformat" $config.plugins | fromYaml }}
{{- $_ := set $config "plugins" $plugins }}
{{- $config | toPrettyJson }}

{{- define "spire-server.kubectl-image" }}
{{- $root := deepCopy . }}
{{- $tag := (default $root.image.tag $root.image.version) | toString }}
{{- if eq (len $tag) 0 }}
{{- $_ := set $root.image "tag" (regexReplaceAll "^(v?\\d+\\.\\d+\\.\\d+).*" $root.KubeVersion "${1}") }}
{{- end }}
{{- include "spire-lib.image" $root }}
{{- end }}

{{- define "spire-server.config-mysql-query" }}
{{- $lst := list }}
{{- range . }}
{{- range $key, $value := . }}
{{- $eValue := toString $value }}
{{- $entry := printf "%s=%s" (urlquery $key) (urlquery $eValue) }}
{{- $lst = append $lst $entry }}
{{- end }}
{{- end }}
{{- if gt (len $lst) 0 }}
{{- printf "?%s" (join "&" $lst) }}
{{- end }}
{{- end }}

{{- define "spire-server.config-postgresql-options" }}
{{- $lst := list }}
{{- range . }}
{{- range $key, $value := . }}
{{- $eValue := toString $value }}
{{- $entry := printf "%s=%s" $key $eValue }}
{{- $lst = append $lst $entry }}
{{- end }}
{{- end }}
{{- if gt (len $lst) 0 }}
{{- printf " %s" (join " " $lst) }}
{{- end }}
{{- end }}

{{- define "spire-server.datastore-config" }}
{{- $config := deepCopy .Values.dataStore.sql.plugin_data }}
{{- if eq .Values.dataStore.sql.databaseType "sqlite3" }}
  {{- $_ := set $config "database_type" "sqlite3" }}
  {{- $_ := set $config "connection_string" "/run/spire/data/datastore.sqlite3" }}
{{- else if eq .Values.dataStore.sql.databaseType "mysql" }}
  {{- $_ := set $config "database_type" "mysql" }}
  {{- $port := int .Values.dataStore.sql.port | default 3306 }}
  {{- $query := include "spire-server.config-mysql-query" .Values.dataStore.sql.options }}
  {{- $_ := set $config "connection_string" (printf "%s:${DBPW}@tcp(%s:%d)/%s%s" .Values.dataStore.sql.username .Values.dataStore.sql.host $port .Values.dataStore.sql.databaseName $query) }}
{{- else if eq .Values.dataStore.sql.databaseType "postgres" }}
  {{- $_ := set $config "database_type" "postgres" }}
  {{- $port := int .Values.dataStore.sql.port | default 5432 }}
  {{- $options:= include "spire-server.config-postgresql-options" .Values.dataStore.sql.options }}
  {{- $_ := set $config "connection_string" (printf "dbname=%s user=%s password=${DBPW} host=%s port=%d%s" .Values.dataStore.sql.databaseName .Values.dataStore.sql.username .Values.dataStore.sql.host $port $options) }}
{{- else }}
  {{- fail "Unsupported database type" }}
{{- end }}
{{- $config | toYaml }}
{{- end }}

{{/*
Tornjak specific section
*/}}

{{- define "spire-tornjak.fullname" -}}
{{ include "spire-server.fullname" . | trimSuffix "-server" }}-tornjak
{{- end }}

{{- define "spire-tornjak.config" -}}
{{ include "spire-tornjak.fullname" . }}-config
{{- end }}

{{- define "spire-tornjak.backend" -}}
{{ include "spire-tornjak.fullname" . }}-backend
{{- end }}
