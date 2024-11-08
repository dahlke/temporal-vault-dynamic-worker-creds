# Rotating Temporal Workers Certificates in Kubernetes with Vault

## Requirements
- `minikube`
- `vault`
- `kubectl`

## TODO
- https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-sidecar
- https://keithtenzer.com/temporal/Deploying_Temporal_Worker_on_Kubernetes/
- Terraform
- Vault
- Kubernetes
- Run Vault and the Operator in their own namespace
- Update all of the namespace stuff

## Vault and Minikube Startup

Start up a Minikube cluster with 4 CPUs and 8GB of memory.

```bash
minikube start --driver=docker --cpus=4 --memory=8192
```

### Run Vault in dev mode in Kubernetes

Add the HashiCorp Helm repository, create a namespace for Vault, and install Vault in Minikube.

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

kubectl create namespace vault

helm install vault hashicorp/vault --set "server.dev.enabled=true"
helm install vault-secrets-operator hashicorp/vault-secrets-operator

EOF
```

Port forward locally to Vault installed in Kubernetes.

```bash
# kubectl port-forward -n vault svc/vault 8200:8200
kubectl port-forward svc/vault 8200:8200
```

The Vault UI is now available at [`http://127.0.0.1:8200`](http://127.0.0.1:8200).

## Configure Vault

In a new terminal, set up Vault env variables.

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'
```

### Enable and configure the Kubernetes auth method.

```bash
kubectl exec -it vault-0 -- /bin/sh

vault secrets enable -path=internal kv-v2
vault kv put internal/database/config username="db-readonly-username" password="db-secret-password"

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
```

### Enable and Configure the PKI Secrets Engine

```bash
vault secrets disable pki
vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki

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
```

### Deploy Temporal Worker

#### With Vault Agent Injector

Deploy the Temporal worker.

```bash
kubectl apply -f deployment-temporal-infra-worker.yaml
```

#### With Vault Secrets Operator

```bash
helm install vault-secrets-operator hashicorp/vault-secrets-operator
```

```bash
TODO
```
