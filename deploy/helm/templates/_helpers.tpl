{{/*
Expand the name of the chart.
*/}}
{{- define "monitor.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "monitor.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "monitor.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "monitor.labels" -}}
helm.sh/chart: {{ include "monitor.chart" . }}
{{ include "monitor.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "monitor.selectorLabels" -}}
app.kubernetes.io/name: {{ include "monitor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
App labels
*/}}
{{- define "monitor.app.labels" -}}
{{ include "monitor.labels" . }}
app.kubernetes.io/component: app
{{- end }}

{{/*
App selector labels
*/}}
{{- define "monitor.app.selectorLabels" -}}
{{ include "monitor.selectorLabels" . }}
app.kubernetes.io/component: app
{{- end }}

{{/*
PostgreSQL labels
*/}}
{{- define "monitor.postgres.labels" -}}
{{ include "monitor.labels" . }}
app.kubernetes.io/component: postgres
{{- end }}

{{/*
PostgreSQL selector labels
*/}}
{{- define "monitor.postgres.selectorLabels" -}}
{{ include "monitor.selectorLabels" . }}
app.kubernetes.io/component: postgres
{{- end }}

{{/*
Prometheus labels
*/}}
{{- define "monitor.prometheus.labels" -}}
{{ include "monitor.labels" . }}
app.kubernetes.io/component: prometheus
{{- end }}

{{/*
Prometheus selector labels
*/}}
{{- define "monitor.prometheus.selectorLabels" -}}
{{ include "monitor.selectorLabels" . }}
app.kubernetes.io/component: prometheus
{{- end }}

{{/*
Grafana labels
*/}}
{{- define "monitor.grafana.labels" -}}
{{ include "monitor.labels" . }}
app.kubernetes.io/component: grafana
{{- end }}

{{/*
Grafana selector labels
*/}}
{{- define "monitor.grafana.selectorLabels" -}}
{{ include "monitor.selectorLabels" . }}
app.kubernetes.io/component: grafana
{{- end }}

{{/*
PostgreSQL service name
*/}}
{{- define "monitor.postgres.serviceName" -}}
{{- printf "%s-postgres" (include "monitor.fullname" .) }}
{{- end }}

{{/*
Prometheus service name
*/}}
{{- define "monitor.prometheus.serviceName" -}}
{{- printf "%s-prometheus" (include "monitor.fullname" .) }}
{{- end }}

{{/*
App service name
*/}}
{{- define "monitor.app.serviceName" -}}
{{- printf "%s-app" (include "monitor.fullname" .) }}
{{- end }}

{{/*
PostgreSQL secret name
*/}}
{{- define "monitor.postgres.secretName" -}}
{{- if .Values.postgres.existingSecret }}
{{- .Values.postgres.existingSecret }}
{{- else }}
{{- printf "%s-postgres" (include "monitor.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Grafana secret name
*/}}
{{- define "monitor.grafana.secretName" -}}
{{- if .Values.grafana.existingSecret }}
{{- .Values.grafana.existingSecret }}
{{- else }}
{{- printf "%s-grafana" (include "monitor.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Auth secret name
*/}}
{{- define "monitor.auth.secretName" -}}
{{- if .Values.auth.existingSecret }}
{{- .Values.auth.existingSecret }}
{{- else }}
{{- printf "%s-auth" (include "monitor.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Mail secret name
*/}}
{{- define "monitor.mail.secretName" -}}
{{- if .Values.mail.existingSecret }}
{{- .Values.mail.existingSecret }}
{{- else }}
{{- printf "%s-mail" (include "monitor.fullname" .) }}
{{- end }}
{{- end }}

{{/*
AI secret name
*/}}
{{- define "monitor.ai.secretName" -}}
{{- if .Values.ai.existingSecret }}
{{- .Values.ai.existingSecret }}
{{- else }}
{{- printf "%s-ai" (include "monitor.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Webhook secret name
*/}}
{{- define "monitor.webhook.secretName" -}}
{{- if .Values.webhook.existingSecret }}
{{- .Values.webhook.existingSecret }}
{{- else }}
{{- printf "%s-webhook" (include "monitor.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Redis secret name
*/}}
{{- define "monitor.redis.secretName" -}}
{{- if .Values.redis.existingSecret }}
{{- .Values.redis.existingSecret }}
{{- else }}
{{- printf "%s-redis" (include "monitor.fullname" .) }}
{{- end }}
{{- end }}

{{/*
MinIO secret name
*/}}
{{- define "monitor.minio.secretName" -}}
{{- if .Values.minio.existingSecret }}
{{- .Values.minio.existingSecret }}
{{- else }}
{{- printf "%s-minio" (include "monitor.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Redis labels
*/}}
{{- define "monitor.redis.labels" -}}
{{ include "monitor.labels" . }}
app.kubernetes.io/component: redis
{{- end }}

{{/*
Redis selector labels
*/}}
{{- define "monitor.redis.selectorLabels" -}}
{{ include "monitor.selectorLabels" . }}
app.kubernetes.io/component: redis
{{- end }}

{{/*
Redis service name
*/}}
{{- define "monitor.redis.serviceName" -}}
{{- printf "%s-redis" (include "monitor.fullname" .) }}
{{- end }}

{{/*
Frontend labels
*/}}
{{- define "monitor.frontend.labels" -}}
{{ include "monitor.labels" . }}
app.kubernetes.io/component: frontend
{{- end }}

{{/*
Frontend selector labels
*/}}
{{- define "monitor.frontend.selectorLabels" -}}
{{ include "monitor.selectorLabels" . }}
app.kubernetes.io/component: frontend
{{- end }}

{{/*
Frontend service name
*/}}
{{- define "monitor.frontend.serviceName" -}}
{{- printf "%s-frontend" (include "monitor.fullname" .) }}
{{- end }}

{{/*
MinIO labels
*/}}
{{- define "monitor.minio.labels" -}}
{{ include "monitor.labels" . }}
app.kubernetes.io/component: minio
{{- end }}

{{/*
MinIO selector labels
*/}}
{{- define "monitor.minio.selectorLabels" -}}
{{ include "monitor.selectorLabels" . }}
app.kubernetes.io/component: minio
{{- end }}

{{/*
MinIO service name
*/}}
{{- define "monitor.minio.serviceName" -}}
{{- printf "%s-minio" (include "monitor.fullname" .) }}
{{- end }}

{{/*
Elasticsearch labels
*/}}
{{- define "monitor.elasticsearch.labels" -}}
{{ include "monitor.labels" . }}
app.kubernetes.io/component: elasticsearch
{{- end }}

{{/*
Elasticsearch selector labels
*/}}
{{- define "monitor.elasticsearch.selectorLabels" -}}
{{ include "monitor.selectorLabels" . }}
app.kubernetes.io/component: elasticsearch
{{- end }}

{{/*
Elasticsearch service name
*/}}
{{- define "monitor.elasticsearch.serviceName" -}}
{{- printf "%s-elasticsearch" (include "monitor.fullname" .) }}
{{- end }}

{{/*
Elasticsearch secret name
*/}}
{{- define "monitor.elasticsearch.secretName" -}}
{{- if .Values.elk.elasticsearch.existingSecret }}
{{- .Values.elk.elasticsearch.existingSecret }}
{{- else }}
{{- printf "%s-elasticsearch" (include "monitor.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Kibana labels
*/}}
{{- define "monitor.kibana.labels" -}}
{{ include "monitor.labels" . }}
app.kubernetes.io/component: kibana
{{- end }}

{{/*
Kibana selector labels
*/}}
{{- define "monitor.kibana.selectorLabels" -}}
{{ include "monitor.selectorLabels" . }}
app.kubernetes.io/component: kibana
{{- end }}

{{/*
Kibana service name
*/}}
{{- define "monitor.kibana.serviceName" -}}
{{- printf "%s-kibana" (include "monitor.fullname" .) }}
{{- end }}

{{/*
Kafka labels
*/}}
{{- define "monitor.kafka.labels" -}}
{{ include "monitor.labels" . }}
app.kubernetes.io/component: kafka
{{- end }}

{{/*
Kafka selector labels
*/}}
{{- define "monitor.kafka.selectorLabels" -}}
{{ include "monitor.selectorLabels" . }}
app.kubernetes.io/component: kafka
{{- end }}

{{/*
Kafka service name
*/}}
{{- define "monitor.kafka.serviceName" -}}
{{- printf "%s-kafka" (include "monitor.fullname" .) }}
{{- end }}

{{/*
Kafka secret name
*/}}
{{- define "monitor.kafka.secretName" -}}
{{- if .Values.kafka.existingSecret }}
{{- .Values.kafka.existingSecret }}
{{- else }}
{{- printf "%s-kafka" (include "monitor.fullname" .) }}
{{- end }}
{{- end }}

{{/*
ScyllaDB labels
*/}}
{{- define "monitor.scylla.labels" -}}
{{ include "monitor.labels" . }}
app.kubernetes.io/component: scylla
{{- end }}

{{/*
ScyllaDB selector labels
*/}}
{{- define "monitor.scylla.selectorLabels" -}}
{{ include "monitor.selectorLabels" . }}
app.kubernetes.io/component: scylla
{{- end }}

{{/*
ScyllaDB service name
*/}}
{{- define "monitor.scylla.serviceName" -}}
{{- printf "%s-scylla" (include "monitor.fullname" .) }}
{{- end }}

{{/*
SonarQube labels
*/}}
{{- define "monitor.sonarqube.labels" -}}
{{ include "monitor.labels" . }}
app.kubernetes.io/component: sonarqube
{{- end }}

{{/*
SonarQube selector labels
*/}}
{{- define "monitor.sonarqube.selectorLabels" -}}
{{ include "monitor.selectorLabels" . }}
app.kubernetes.io/component: sonarqube
{{- end }}

{{/*
SonarQube service name
*/}}
{{- define "monitor.sonarqube.serviceName" -}}
{{- printf "%s-sonarqube" (include "monitor.fullname" .) }}
{{- end }}

{{/*
SonarQube secret name
*/}}
{{- define "monitor.sonarqube.secretName" -}}
{{- if .Values.sonarqube.existingSecret }}
{{- .Values.sonarqube.existingSecret }}
{{- else }}
{{- printf "%s-sonarqube" (include "monitor.fullname" .) }}
{{- end }}
{{- end }}

{{/*
SonarQube PostgreSQL labels
*/}}
{{- define "monitor.sonarqube.postgres.labels" -}}
{{ include "monitor.labels" . }}
app.kubernetes.io/component: sonarqube-postgres
{{- end }}

{{/*
SonarQube PostgreSQL selector labels
*/}}
{{- define "monitor.sonarqube.postgres.selectorLabels" -}}
{{ include "monitor.selectorLabels" . }}
app.kubernetes.io/component: sonarqube-postgres
{{- end }}

{{/*
SonarQube PostgreSQL service name
*/}}
{{- define "monitor.sonarqube.postgres.serviceName" -}}
{{- printf "%s-sonarqube-postgres" (include "monitor.fullname" .) }}
{{- end }}

{{/*
Filebeat labels
*/}}
{{- define "monitor.filebeat.labels" -}}
{{ include "monitor.labels" . }}
app.kubernetes.io/component: filebeat
{{- end }}

{{/*
Filebeat selector labels
*/}}
{{- define "monitor.filebeat.selectorLabels" -}}
{{ include "monitor.selectorLabels" . }}
app.kubernetes.io/component: filebeat
{{- end }}
