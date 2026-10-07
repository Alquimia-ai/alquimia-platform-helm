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

{{- define "alquimia.isOpenShift" -}}
{{- if .Capabilities.APIVersions.Has "config.openshift.io/v1" -}}true{{- end -}}
{{- end }}

{{- define "alquimia.appsDomain" -}}
{{- if .Values.appsDomain -}}
{{- .Values.appsDomain -}}
{{- else if .Capabilities.APIVersions.Has "config.openshift.io/v1" -}}
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

{{- define "alquimia.zeroTrust" -}}
{{- if and .Values.runtime.enabled .Values.runtime.zeroTrust.enabled }}true{{- end }}
{{- end }}

{{- define "alquimia.spire.namespace" -}}
{{- .Values.spire.namespace | default "spire" -}}
{{- end }}

{{- define "alquimia.spire.trustDomain" -}}
{{- if .Values.spire.trustDomain -}}
{{- .Values.spire.trustDomain -}}
{{- else -}}
{{- .Values.runtime.zeroTrust.trustDomain | default "acme.example" -}}
{{- end -}}
{{- end }}

{{- define "alquimia.spire.socketPath" -}}
/run/spire/sockets/agent.sock
{{- end }}

{{- define "alquimia.spire.kubeletCABundle" -}}
{{- if .Values.spire.kubeletCA.bundle -}}
{{- .Values.spire.kubeletCA.bundle -}}
{{- else -}}
{{- $cm := lookup "v1" "ConfigMap" "openshift-config-managed" "kubelet-serving-ca" -}}
{{- if and $cm $cm.data -}}
{{- index $cm.data "ca-bundle.crt" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "alquimia.spire.useKubeletCA" -}}
{{- $p := .Values.spire.platform | default "auto" -}}
{{- if or (eq $p "openshift") (and (eq $p "auto") (include "alquimia.spire.kubeletCABundle" .)) -}}
true
{{- end -}}
{{- end }}

{{- define "alquimia.registryMode" -}}
{{- $mode := .Values.registry.mode | default "local" -}}
{{- if not (or (eq $mode "local") (eq $mode "remote")) -}}
{{- fail "registry.mode tiene que ser local o remote" -}}
{{- end -}}
{{- $mode -}}
{{- end }}

{{- define "alquimia.registryHost" -}}
{{- if eq (include "alquimia.registryMode" .) "remote" -}}
{{- $host := .Values.registry.host | default "" | trim -}}
{{- if not $host -}}
{{- fail "registry.mode remote requiere registry.host (por ejemplo registry.acme.example)" -}}
{{- end -}}
{{- $host -}}
{{- else -}}
{{- printf "oras-registry.%s.svc.cluster.local:5000" (include "alquimia.namespace" .) -}}
{{- end -}}
{{- end }}

{{- define "alquimia.registryTLS" -}}
{{- if and (eq (include "alquimia.registryMode" .) "local") .Values.registry.tls }}true{{- end -}}
{{- end }}

{{- define "alquimia.registryPlainHttp" -}}
{{- if eq (include "alquimia.registryTLS" .) "true" -}}
false
{{- else if eq (include "alquimia.registryMode" .) "remote" -}}
{{- if .Values.registry.plainHttp }}true{{- else }}false{{- end -}}
{{- else if .Values.runtime.zeroTrust.enabled -}}
{{- .Values.runtime.zeroTrust.orasPlainHttp | toString -}}
{{- else -}}
{{- .Values.runtime.config.ORAS_PLAIN_HTTP | toString -}}
{{- end -}}
{{- end }}

{{- define "alquimia.registryInsecure" -}}
{{- if eq (include "alquimia.registryTLS" .) "true" -}}
false
{{- else if eq (include "alquimia.registryMode" .) "remote" -}}
{{- if .Values.registry.insecure }}true{{- else }}false{{- end -}}
{{- else if .Values.runtime.zeroTrust.enabled -}}
{{- .Values.runtime.zeroTrust.orasInsecure | toString -}}
{{- else -}}
{{- .Values.runtime.config.ORAS_INSECURE | toString -}}
{{- end -}}
{{- end }}

{{- define "alquimia.agentspaceNamespace" -}}
{{- if .Values.spire.enabled -}}
{{- include "alquimia.spire.namespace" . -}}
{{- else -}}
{{- .Values.runtime.zeroTrust.provisioningNamespace | default "spire" -}}
{{- end -}}
{{- end }}

{{- define "alquimia.runtimeKeycloak" -}}
{{- if or (eq (include "alquimia.zeroTrust" .) "true") .Values.keycloak.runtimeAuth.enabled }}true{{- end }}
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
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi
{{- end }}

{{- define "alquimia.helperResources" -}}
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 256Mi
{{- end }}

{{- define "alquimia.runtimeContainerSecurity" -}}
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault
{{- end }}

{{- define "alquimia.registryTrustInit" -}}
{{- if eq (include "alquimia.registryTLS" .) "true" }}
- name: trust-registry-ca
  image: {{ .Values.images.runtime | quote }}
  imagePullPolicy: IfNotPresent
  command:
    - /bin/sh
    - -c
    - cat /etc/ssl/cert.pem /etc/alquimia/registry-ca/ca.crt > /trust/ca-bundle.crt
  volumeMounts:
    - name: registry-ca
      mountPath: /etc/alquimia/registry-ca
      readOnly: true
    - name: trust-bundle
      mountPath: /trust
  securityContext:
    runAsNonRoot: true
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
  {{- include "alquimia.helperResources" . | nindent 2 }}
{{- end }}
{{- end }}

{{- define "alquimia.registryTrustEnv" -}}
{{- if eq (include "alquimia.registryTLS" .) "true" }}
- name: SSL_CERT_FILE
  value: /trust/ca-bundle.crt
- name: REQUESTS_CA_BUNDLE
  value: /trust/ca-bundle.crt
- name: CURL_CA_BUNDLE
  value: /trust/ca-bundle.crt
{{- end }}
{{- end }}

{{- define "alquimia.registryTrustMount" -}}
{{- if eq (include "alquimia.registryTLS" .) "true" }}
- name: trust-bundle
  mountPath: /trust
  readOnly: true
{{- end }}
{{- end }}

{{- define "alquimia.registryTrustVolumes" -}}
{{- if eq (include "alquimia.registryTLS" .) "true" }}
- name: registry-ca
  secret:
    secretName: oras-registry-tls
    items:
      - key: ca.crt
        path: ca.crt
- name: trust-bundle
  emptyDir: {}
{{- end }}
{{- end }}
