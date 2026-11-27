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
{{- if .Values.openshift }}true{{- end -}}
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
{{- fail "registry.mode must be local or remote" -}}
{{- end -}}
{{- $mode -}}
{{- end }}

{{- define "alquimia.zotConfig" -}}
{
  "storage": {
    "rootDirectory": "/var/lib/registry"
  },
  "http": {
    "address": "0.0.0.0",
    "port": "5000",
    "realm": "zot",
    "compat": ["docker2s2"]{{- if eq (include "alquimia.registryTLS" .) "true" }},
    "tls": {
      "cert": "/certs/tls.crt",
      "key": "/certs/tls.key"
    }{{- end }},
    "auth": {
      "htpasswd": {
        "path": "/auth/auth.htpasswd"
      }
    }
  },
  "log": {
    "level": "info"
  }
}
{{- end }}

{{- define "alquimia.registryHost" -}}
{{- if eq (include "alquimia.registryMode" .) "remote" -}}
{{- $host := .Values.registry.host | default "" | trim -}}
{{- if not $host -}}
{{- fail "registry.mode remote requires registry.host (for example registry.acme.example)" -}}
{{- end -}}
{{- $host -}}
{{- else -}}
{{- printf "oras-registry.%s.svc.cluster.local:5000" (include "alquimia.namespace" .) -}}
{{- end -}}
{{- end }}

{{- define "alquimia.registryTLS" -}}
{{- if and (eq (include "alquimia.registryMode" .) "local") .Values.registry.tls }}true{{- end -}}
{{- end }}

{{- define "alquimia.registryCaBundle" -}}
{{- $ca := .Values.registry.ca | default dict -}}
{{- $ca.bundle | default "" | trim -}}
{{- end }}

{{- define "alquimia.registryCaExistingSecret" -}}
{{- $ca := .Values.registry.ca | default dict -}}
{{- $ca.existingSecret | default "" | trim -}}
{{- end }}

{{- define "alquimia.registryCaSecretKey" -}}
{{- $ca := .Values.registry.ca | default dict -}}
{{- $key := $ca.existingSecretKey | default "" | trim -}}
{{- if $key }}{{ $key }}{{ else }}ca.crt{{ end -}}
{{- end }}

{{- define "alquimia.registryCaValidate" -}}
{{- $bundle := include "alquimia.registryCaBundle" . -}}
{{- $secret := include "alquimia.registryCaExistingSecret" . -}}
{{- if and $bundle $secret -}}
{{- fail "registry.ca.bundle and registry.ca.existingSecret cannot both be set" -}}
{{- end -}}
{{- if and (or $bundle $secret) (ne (include "alquimia.registryMode" .) "remote") -}}
{{- fail "registry.ca requires registry.mode remote" -}}
{{- end -}}
{{- if and (or $bundle $secret) (or .Values.registry.plainHttp .Values.registry.insecure) -}}
{{- fail "registry.ca requires registry.plainHttp=false and registry.insecure=false" -}}
{{- end -}}
{{- end }}

{{- define "alquimia.registryRemoteCa" -}}
{{- if and (eq (include "alquimia.registryMode" .) "remote") (or (include "alquimia.registryCaBundle" .) (include "alquimia.registryCaExistingSecret" .)) -}}
true
{{- end -}}
{{- end }}

{{- define "alquimia.registryTrust" -}}
{{- if or (eq (include "alquimia.registryTLS" .) "true") (eq (include "alquimia.registryRemoteCa" .) "true") -}}
true
{{- end -}}
{{- end }}

{{- define "alquimia.minioEndpoint" -}}
{{- .Values.minio.endpoint | default "" | trim | trimSuffix "/" -}}
{{- end }}

{{- define "alquimia.minioCaBundle" -}}
{{- $ca := .Values.minio.ca | default dict -}}
{{- $ca.bundle | default "" | trim -}}
{{- end }}

{{- define "alquimia.minioCaExistingSecret" -}}
{{- $ca := .Values.minio.ca | default dict -}}
{{- $ca.existingSecret | default "" | trim -}}
{{- end }}

{{- define "alquimia.minioCaSecretKey" -}}
{{- $ca := .Values.minio.ca | default dict -}}
{{- $key := $ca.existingSecretKey | default "" | trim -}}
{{- if $key }}{{ $key }}{{ else }}ca.crt{{ end -}}
{{- end }}

{{- define "alquimia.minioCa" -}}
{{- if or (include "alquimia.minioCaBundle" .) (include "alquimia.minioCaExistingSecret" .) -}}
true
{{- end -}}
{{- end }}

{{- define "alquimia.minioValidate" -}}
{{- $ep := include "alquimia.minioEndpoint" . -}}
{{- $bundle := include "alquimia.minioCaBundle" . -}}
{{- $secret := include "alquimia.minioCaExistingSecret" . -}}
{{- if and $bundle $secret -}}
{{- fail "minio.ca.bundle and minio.ca.existingSecret cannot both be set" -}}
{{- end -}}
{{- if and $ep .Values.minio.enabled -}}
{{- fail "minio.endpoint requires minio.enabled false" -}}
{{- end -}}
{{- if and $ep (not (or (hasPrefix "https://" $ep) (hasPrefix "http://" $ep))) -}}
{{- fail "minio.endpoint must start with https:// or http://" -}}
{{- end -}}
{{- if and (or $bundle $secret) .Values.minio.enabled -}}
{{- fail "minio.ca requires minio.enabled false" -}}
{{- end -}}
{{- if and (or $bundle $secret) (hasPrefix "http://" $ep) -}}
{{- fail "minio.ca requires an https:// endpoint" -}}
{{- end -}}
{{- if and (not .Values.minio.enabled) (not $ep) (eq (include "alquimia.helmSecrets" .) "true") -}}
{{- fail "minio.enabled false requires minio.endpoint when secrets.backend is helm" -}}
{{- end -}}
{{- end }}

{{- define "alquimia.s3Endpoint" -}}
{{- $ep := include "alquimia.minioEndpoint" . -}}
{{- if $ep -}}
{{- $ep -}}
{{- else -}}
{{- printf "http://minio-service.%s.svc.cluster.local:9000" (include "alquimia.namespace" .) -}}
{{- end -}}
{{- end }}

{{- define "alquimia.s3Secure" -}}
{{- $ep := include "alquimia.minioEndpoint" . -}}
{{- if hasPrefix "https://" $ep -}}
true
{{- else if hasPrefix "http://" $ep -}}
false
{{- else -}}
{{- .Values.runtime.secrets.s3.secure | toString -}}
{{- end -}}
{{- end }}

{{- define "alquimia.s3RemoteEnv" -}}
{{- if include "alquimia.minioEndpoint" . }}
- name: BLOB_S3_ENDPOINT_URL
  value: {{ include "alquimia.minioEndpoint" . | quote }}
- name: BLOB_S3_SECURE
  value: {{ include "alquimia.s3Secure" . | quote }}
{{- end }}
{{- end }}

{{- define "alquimia.rcloneS3EndpointEnv" -}}
- name: RCLONE_S3_ENDPOINT
  {{- if include "alquimia.minioEndpoint" . }}
  value: {{ include "alquimia.minioEndpoint" . | quote }}
  {{- else }}
  valueFrom:
    secretKeyRef:
      name: alquimia-s3
      key: BLOB_S3_ENDPOINT_URL
  {{- end }}
{{- if eq (include "alquimia.minioCa" .) "true" }}
- name: RCLONE_CA_CERT
  value: /trust/ca-bundle.crt
{{- end }}
{{- end }}

{{- define "alquimia.minioCaRcloneMount" -}}
{{- if eq (include "alquimia.minioCa" .) "true" }}
- name: trust-bundle
  mountPath: /trust
  readOnly: true
{{- end }}
{{- end }}

{{- define "alquimia.keycloakCaBundle" -}}
{{- $ca := .Values.keycloak.ca | default dict -}}
{{- $ca.bundle | default "" | trim -}}
{{- end }}

{{- define "alquimia.keycloakCaExistingSecret" -}}
{{- $ca := .Values.keycloak.ca | default dict -}}
{{- $ca.existingSecret | default "" | trim -}}
{{- end }}

{{- define "alquimia.keycloakCaSecretKey" -}}
{{- $ca := .Values.keycloak.ca | default dict -}}
{{- $key := $ca.existingSecretKey | default "" | trim -}}
{{- if $key }}{{ $key }}{{ else }}ca.crt{{ end -}}
{{- end }}

{{- define "alquimia.keycloakCa" -}}
{{- if or (include "alquimia.keycloakCaBundle" .) (include "alquimia.keycloakCaExistingSecret" .) -}}
true
{{- end -}}
{{- end }}

{{- define "alquimia.keycloakCaValidate" -}}
{{- $bundle := include "alquimia.keycloakCaBundle" . -}}
{{- $secret := include "alquimia.keycloakCaExistingSecret" . -}}
{{- $url := "" -}}
{{- if not .Values.keycloak.enabled -}}
{{- $ex := .Values.keycloak.existing | default dict -}}
{{- $url = $ex.url | default "" | trim -}}
{{- end -}}
{{- if and $bundle $secret -}}
{{- fail "keycloak.ca.bundle and keycloak.ca.existingSecret cannot both be set" -}}
{{- end -}}
{{- if and (or $bundle $secret) .Values.keycloak.enabled -}}
{{- fail "keycloak.ca requires keycloak.enabled false" -}}
{{- end -}}
{{- if and (or $bundle $secret) (not (hasPrefix "https://" $url)) -}}
{{- fail "keycloak.ca requires keycloak.existing.url starting with https://" -}}
{{- end -}}
{{- end }}

{{- define "alquimia.extraTrust" -}}
{{- if or (eq (include "alquimia.registryTrust" .) "true") (eq (include "alquimia.minioCa" .) "true") (eq (include "alquimia.keycloakCa" .) "true") -}}
true
{{- end -}}
{{- end }}

{{- define "alquimia.keycloakCaVolume" -}}
{{- if eq (include "alquimia.keycloakCa" .) "true" }}
- name: keycloak-ca
  {{- if include "alquimia.keycloakCaExistingSecret" . }}
  secret:
    secretName: {{ include "alquimia.keycloakCaExistingSecret" . | quote }}
    items:
      - key: {{ include "alquimia.keycloakCaSecretKey" . | quote }}
        path: ca.crt
  {{- else }}
  configMap:
    name: alquimia-keycloak-ca
    items:
      - key: ca.crt
        path: ca.crt
  {{- end }}
{{- end }}
{{- end }}

{{- define "alquimia.keycloakCaMount" -}}
{{- if eq (include "alquimia.keycloakCa" .) "true" }}
- name: keycloak-ca
  mountPath: /etc/alquimia/keycloak-ca
  readOnly: true
{{- end }}
{{- end }}

{{- define "alquimia.keycloakCaEnv" -}}
{{- if eq (include "alquimia.keycloakCa" .) "true" }}
- name: NODE_EXTRA_CA_CERTS
  value: /etc/alquimia/keycloak-ca/ca.crt
{{- end }}
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

{{- define "alquimia.otelServiceName" -}}
{{- printf "%s%s" (.prefix | default "") (.name | default "") -}}
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
{{- if eq (include "alquimia.extraTrust" .) "true" }}
- name: trust-ca
  image: {{ .Values.images.runtime | quote }}
  imagePullPolicy: IfNotPresent
  command:
    - /bin/sh
    - -c
    - |
      set -e
      cat /etc/ssl/cert.pem > /trust/ca-bundle.crt
      if [ -f /etc/alquimia/registry-ca/ca.crt ]; then
        cat /etc/alquimia/registry-ca/ca.crt >> /trust/ca-bundle.crt
      fi
      if [ -f /etc/alquimia/minio-ca/ca.crt ]; then
        cat /etc/alquimia/minio-ca/ca.crt >> /trust/ca-bundle.crt
      fi
      if [ -f /etc/alquimia/keycloak-ca/ca.crt ]; then
        cat /etc/alquimia/keycloak-ca/ca.crt >> /trust/ca-bundle.crt
      fi
  volumeMounts:
    {{- if eq (include "alquimia.registryTrust" .) "true" }}
    - name: registry-ca
      mountPath: /etc/alquimia/registry-ca
      readOnly: true
    {{- end }}
    {{- if eq (include "alquimia.minioCa" .) "true" }}
    - name: minio-ca
      mountPath: /etc/alquimia/minio-ca
      readOnly: true
    {{- end }}
    {{- if eq (include "alquimia.keycloakCa" .) "true" }}
    - name: keycloak-ca
      mountPath: /etc/alquimia/keycloak-ca
      readOnly: true
    {{- end }}
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
{{- if eq (include "alquimia.extraTrust" .) "true" }}
- name: SSL_CERT_FILE
  value: /trust/ca-bundle.crt
- name: REQUESTS_CA_BUNDLE
  value: /trust/ca-bundle.crt
- name: CURL_CA_BUNDLE
  value: /trust/ca-bundle.crt
{{- if eq (include "alquimia.minioCa" .) "true" }}
- name: AWS_CA_BUNDLE
  value: /trust/ca-bundle.crt
{{- end }}
{{- end }}
{{- end }}

{{- define "alquimia.registryTrustMount" -}}
{{- if eq (include "alquimia.extraTrust" .) "true" }}
- name: trust-bundle
  mountPath: /trust
  readOnly: true
{{- end }}
{{- end }}

{{- define "alquimia.registryTrustVolumes" -}}
{{- if eq (include "alquimia.extraTrust" .) "true" }}
{{- if eq (include "alquimia.registryTrust" .) "true" }}
- name: registry-ca
  {{- if eq (include "alquimia.registryTLS" .) "true" }}
  secret:
    secretName: oras-registry-tls
    items:
      - key: ca.crt
        path: ca.crt
  {{- else if include "alquimia.registryCaExistingSecret" . }}
  secret:
    secretName: {{ include "alquimia.registryCaExistingSecret" . | quote }}
    items:
      - key: {{ include "alquimia.registryCaSecretKey" . | quote }}
        path: ca.crt
  {{- else }}
  configMap:
    name: alquimia-registry-ca
    items:
      - key: ca.crt
        path: ca.crt
  {{- end }}
{{- end }}
{{- if eq (include "alquimia.minioCa" .) "true" }}
- name: minio-ca
  {{- if include "alquimia.minioCaExistingSecret" . }}
  secret:
    secretName: {{ include "alquimia.minioCaExistingSecret" . | quote }}
    items:
      - key: {{ include "alquimia.minioCaSecretKey" . | quote }}
        path: ca.crt
  {{- else }}
  configMap:
    name: alquimia-minio-ca
    items:
      - key: ca.crt
        path: ca.crt
  {{- end }}
{{- end }}
{{- if eq (include "alquimia.keycloakCa" .) "true" }}
{{- include "alquimia.keycloakCaVolume" . }}
{{- end }}
- name: trust-bundle
  emptyDir: {}
{{- end }}
{{- end }}

{{- define "alquimia.embeddingsConfig" -}}
{{- $cfg := dict -}}
{{- if .Values.runtime.embeddings -}}
{{- $cfg = .Values.runtime.embeddings.config | default dict -}}
{{- end -}}
{{- if $cfg -}}
{{- if kindIs "string" $cfg -}}
{{ $cfg }}
{{- else -}}
{{ $cfg | toYaml }}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "alquimia.hasEmbeddings" -}}
{{- if include "alquimia.embeddingsConfig" . | trim }}true{{- end -}}
{{- end }}

{{- define "alquimia.embeddingsMount" -}}
{{- if eq (include "alquimia.hasEmbeddings" .) "true" }}
- name: embeddings-config
  mountPath: /var/lib/alquimia/embeddings.yaml
  subPath: embeddings.yaml
  readOnly: true
{{- end }}
{{- end }}

{{- define "alquimia.embeddingsVolume" -}}
{{- if eq (include "alquimia.hasEmbeddings" .) "true" }}
- name: embeddings-config
  configMap:
    name: alquimia-embeddings
    defaultMode: 0444
{{- end }}
{{- end }}

{{- define "alquimia.cosignEnabled" -}}
{{- if or .Values.runtime.cosign.publicKey .Values.runtime.cosign.privateKey }}true{{- end -}}
{{- end }}

{{- define "alquimia.cosignMount" -}}
{{- if eq (include "alquimia.cosignEnabled" .) "true" }}
- name: cosign-key
  mountPath: /etc/alquimia/cosign
  readOnly: true
{{- end }}
{{- end }}

{{- define "alquimia.cosignVolume" -}}
{{- $pub := .Values.runtime.cosign.publicKey -}}
{{- $priv := .Values.runtime.cosign.privateKey -}}
{{- if or $pub $priv }}
- name: cosign-key
  {{- if and $pub $priv }}
  projected:
    defaultMode: 0444
    sources:
      - configMap:
          name: alquimia-cosign
          items:
            - key: cosign.pub
              path: cosign.pub
      - secret:
          name: alquimia-cosign-key
          items:
            - key: cosign.key
              path: cosign.key
              mode: 0440
  {{- else if $pub }}
  configMap:
    name: alquimia-cosign
    defaultMode: 0444
  {{- else }}
  secret:
    secretName: alquimia-cosign-key
    defaultMode: 0440
    items:
      - key: cosign.key
        path: cosign.key
  {{- end }}
{{- end }}
{{- end }}

{{- define "alquimia.cosignPasswordEnv" -}}
{{- if .Values.runtime.cosign.privateKey }}
- name: COSIGN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: alquimia-cosign-key
      key: COSIGN_PASSWORD
{{- end }}
{{- end }}
