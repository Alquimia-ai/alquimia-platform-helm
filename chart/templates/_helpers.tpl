{{- define "alquimia.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "alquimia.namespace" -}}
{{- .Values.namespace | default .Release.Namespace -}}
{{- end }}

{{- define "alquimia.helmSecrets" -}}
{{- if eq (.Values.secrets.backend | default "sealed") "helm" }}true{{- else }}false{{- end }}
{{- end }}

{{- define "alquimia.nodeAffinity" -}}
{{- $na := .local | default dict -}}
{{- if empty $na }}
{{- $na = .Values.nodeAffinity | default dict -}}
{{- end }}
{{- if not (empty $na) }}
affinity:
  nodeAffinity:
    {{- toYaml $na | nindent 4 }}
{{- end }}
{{- end }}

{{- define "alquimia.appsDomain" -}}
{{- if .Values.appsDomain -}}
{{- .Values.appsDomain -}}
{{- else -}}
{{- $ing := lookup "config.openshift.io/v1" "Ingress" "" "cluster" -}}
{{- if and $ing $ing.spec $ing.spec.domain -}}
{{- $ing.spec.domain -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "alquimia.studioHost" -}}
{{- if .Values.studio.host -}}
{{- .Values.studio.host -}}
{{- else if (include "alquimia.appsDomain" .) -}}
{{- printf "alquimia-studio.%s" (include "alquimia.appsDomain" .) -}}
{{- end -}}
{{- end }}

{{- define "alquimia.hasNodeAffinity" -}}
{{- $na := .local | default dict -}}
{{- if empty $na }}
{{- $na = .Values.nodeAffinity | default dict -}}
{{- end }}
{{- if not (empty $na) }}true{{- end }}
{{- end }}

{{- define "alquimia.waitVaultInit" -}}
- name: wait-vault
  image: {{ .Values.images.curl | quote }}
  imagePullPolicy: IfNotPresent
  command:
    - /bin/sh
    - -c
    - |
      echo "Waiting for Vault to be unsealed..."
      until curl -sf "$VAULT_ADDR/v1/sys/health"; do
        sleep 5
      done
      echo "Vault is ready."
  env:
    - name: VAULT_ADDR
      value: {{ printf "http://vault.%s.svc.cluster.local:8200" (include "alquimia.namespace" .) | quote }}
{{- end }}
