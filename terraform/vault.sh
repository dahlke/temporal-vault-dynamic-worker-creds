#!/bin/bash


rm *.pem *.key

vault secrets disable pki
vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki

vault kv put internal/database/config username="db-readonly-username" password="db-secret-password"

vault write pki/config/urls \
     issuing_certificates="$VAULT_ADDR/v1/pki/ca" \
     crl_distribution_points="$VAULT_ADDR/v1/pki/crl"

vault write pki/root/generate/internal \
    common_name="dahlke" \
    organization="dahlke" \
    key_type="rsa" \
    key_bits=4096 \
    exclude_cn_from_sans=true

vault write pki/roles/temporal-infra-worker \
    allowed_domains="dahlke.io" \
    allow_subdomains=true \ max_ttl="720h" \
    key_type="rsa" \
    key_bits=2048 \
    allow_any_name=true \
    key_usage="DigitalSignature" \
    ext_key_usage="ClientAuth" \
    require_cn=false

vault write -format=json pki/issue/temporal-infra-worker \
    organization="dahlke" \
    ttl="720h" \
    private_key_format="pkcs8" \
    > cert_output.json

cat cert_output.json | jq -r '.data.certificate' > client.pem
cat cert_output.json | jq -r '.data.private_key' > client.key
cat cert_output.json | jq -r '.data.ca_chain[]' > ca_chain.pem

tcld namespace accepted-client-ca add --namespace $TEMPORAL_NAMESPACE --ca-certificate $(cat ca_chain.pem | base64)
tcld namespace accepted-client-ca remove --namespace $TEMPORAL_NAMESPACE --fp $(tcld namespace accepted-client-ca list --namespace $TEMPORAL_NAMESPACE | jq '.[0].fingerprint')

# kubectl exec -n vault -it vault-0 -- /bin/sh

vault auth enable kubernetes

vault write auth/kubernetes/config \
      kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"

vault policy write temporal-infra-worker - <<EOF
path "internal/data/database/config" {
   capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/temporal-infra-worker \
      bound_service_account_names=temporal-infra-worker \
      bound_service_account_namespaces=default \
      policies=temporal-infra-worker \
      ttl=24h
exit

vault policy write temporal-infra-worker - <<EOF
# Allow issuing certificates
path "pki/issue/temporal-infra-worker" {
   capabilities = ["create", "read", "update"]
}

# Allow reading certificate configuration
path "pki/config/*" {
   capabilities = ["read"]
}

# Allow reading role configuration
path "pki/roles/temporal-infra-worker" {
   capabilities = ["read"]
}
EOF
