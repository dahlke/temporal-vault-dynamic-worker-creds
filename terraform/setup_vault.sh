#!/bin/bash

rm *.pem *.key

# kubectl exec -n vault -it vault-0 -- /bin/sh

vault secrets disable pki
vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki
vault auth disable kubernetes
vault auth enable kubernetes

vault write auth/kubernetes/config \
      kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"

vault write auth/kubernetes/role/temporal-infra-worker \
      bound_service_account_names=temporal-infra-worker \
      bound_service_account_namespaces=default \
      policies=temporal-infra-worker \
      ttl=24h
exit

vault policy write temporal-infra-worker - <<EOF
# Allow issuing certificates
path "pki_int/issue/temporal-infra-worker" {
   capabilities = ["create", "read", "update"]
}

# Allow reading certificate configuration
path "pki_int/config/*" {
   capabilities = ["read"]
}

# Allow reading role configuration
path "pki_int/roles/temporal-infra-worker" {
   capabilities = ["read"]
}
EOF

# Generate the root CA
vault write pki/root/generate/internal \
    common_name="dahlke" \
    organization="dahlke" \
    key_type="rsa" \
    key_bits=4096 \
    exclude_cn_from_sans=true

# Enable a new path for the intermediate CA
vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=43800h pki_int

# Generate the intermediate CA CSR
vault write -format=json pki_int/intermediate/generate/internal \
    common_name="dahlke Intermediate Authority" \
    organization="dahlke" \
    key_type="rsa" \
    key_bits=4096 \
    exclude_cn_from_sans=true \
    | jq -r '.data.csr' > pki_intermediate.csr

# Sign the intermediate CA with the root CA
vault write -format=json pki/root/sign-intermediate csr=@pki_intermediate.csr \
    format=pem_bundle ttl="43800h" \
    | jq -r '.data.certificate' > intermediate.cert.pem

# Import the signed intermediate certificate back into Vault
vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem

# Configure the URLs for the intermediate CA
vault write pki_int/config/urls \
    issuing_certificates="$VAULT_ADDR/v1/pki_int/ca" \
    crl_distribution_points="$VAULT_ADDR/v1/pki_int/crl"

# Configure the role to use the intermediate CA
vault write pki_int/roles/temporal-infra-worker \
    allowed_domains="dahlke.io" \
    allow_subdomains=true \
    max_ttl="720h" \
    key_type="rsa" \
    key_bits=2048 \
    allow_any_name=true \
    key_usage="DigitalSignature" \
    ext_key_usage="ClientAuth" \
    require_cn=false

# Issue a certificate using the intermediate CA
vault write -format=json pki_int/issue/temporal-infra-worker \
    organization="dahlke" \
    ttl="720h" \
    private_key_format="pkcs8" \
    > cert_output.json

cat cert_output.json | jq -r '.data.certificate' > client.pem
cat cert_output.json | jq -r '.data.private_key' > client.key
cat cert_output.json | jq -r '.data.ca_chain[]' > ca_chain.pem

tcld namespace accepted-client-ca add --namespace $TEMPORAL_NAMESPACE --ca-certificate $(cat ca_chain.pem | base64)
tcld namespace accepted-client-ca remove --namespace $TEMPORAL_NAMESPACE --fp $(tcld namespace accepted-client-ca list --namespace $TEMPORAL_NAMESPACE | jq '.[0].fingerprint')
