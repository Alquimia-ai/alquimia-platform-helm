{{- define "alquimia.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "alquimia.namespace" -}}
{{- .Values.namespace | default .Release.Namespace -}}
{{- end }}

{{- define "alquimia.vaultUnsealer.serviceAccountName" -}}
{{- $sa := .Values.vault.serviceAccount | default dict -}}
{{- $sa.name | default "vault-unsealer" -}}
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

{{- define "alquimia.keycloakHost" -}}
{{- if .Values.keycloak.host -}}
{{- .Values.keycloak.host -}}
{{- else if (include "alquimia.appsDomain" .) -}}
{{- printf "keycloak.%s" (include "alquimia.appsDomain" .) -}}
{{- end -}}
{{- end }}

{{- define "alquimia.keycloakUrl" -}}
{{- if not .Values.keycloak.enabled -}}
{{- $ex := .Values.keycloak.existing | default dict -}}
{{- if $ex.url -}}
{{- $ex.url -}}
{{- else if and $ex.service $ex.namespace -}}
{{- printf "http://%s.%s.svc.cluster.local:%v" $ex.service $ex.namespace ($ex.port | default 8080) -}}
{{- end -}}
{{- else -}}
{{- $host := include "alquimia.keycloakHost" . | trim -}}
{{- if $host -}}
{{- printf "https://%s" $host -}}
{{- else -}}
{{- printf "http://keycloak.%s.svc.cluster.local:8080" (include "alquimia.namespace" .) -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "alquimia.keycloakIssuer" -}}
{{- $url := include "alquimia.keycloakUrl" . | trim -}}
{{- if $url -}}
{{- printf "%s/realms/%s" (trimSuffix "/" $url) (.Values.keycloak.realm | default "alquimia") -}}
{{- end -}}
{{- end }}

{{- define "alquimia.otelUrl" -}}
{{- $base := trimSuffix "/" .endpoint -}}
{{- $path := .path | default "" -}}
{{- if and $path (not (hasPrefix "/" $path)) -}}
{{- $path = printf "/%s" $path -}}
{{- end -}}
{{- printf "%s%s" $base $path -}}
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
