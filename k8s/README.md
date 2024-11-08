# Rotating Temporal Workers Certificates in Kubernetes with Vault

## Requirements
- `minikube`
- `vault`
- `kubectl`

## TODO
- https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-sidecar

## Vault and Minikube Startup

Start up a Minikube cluster with 4 CPUs and 8GB of memory.

```bash
minikube start --driver=docker --cpus=4 --memory=8192
```

### Option 1: Vault in dev mode from CLI

Start Vault in dev mode with a root token of `root`.

```bash
vault server -dev -dev-root-token-id="root"
```

### Option 2: Vault in dev mode in Kubernetes

Add the HashiCorp Helm repository, create a namespace for Vault, and install Vault in Minikube.

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

kubectl create namespace vault

# TODO: -n vault
helm install vault hashicorp/vault --set "server.dev.enabled=true"

EOF
```

Port forward to Vault.

```bash
# kubectl port-forward -n vault svc/vault 8200:8200
kubectl port-forward svc/vault 8200:8200
```

Open the Vault UI in your browser.

```bash
open http://127.0.0.1:8200
```

## Configure Vault

In a new terminal, set up Vault env variables.

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'
```

Enable and configure the Kubernetes auth method.

```bash
kubectl exec -it vault-0 -- /bin/sh

vault secrets enable -path=internal kv-v2
vault kv put internal/database/config username="db-readonly-username" password="db-secret-password"

vault auth enable kubernetes

vault write auth/kubernetes/config \
      kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"

# vault policy write internal-app - <<EOF
# path "internal/data/database/config" {
   # capabilities = ["read"]
# }
# EOF

vault policy write temporal-worker - <<EOF
path "internal/data/database/config" {
   capabilities = ["read"]
}
EOF

# vault write auth/kubernetes/role/internal-app \
      # bound_service_account_names=internal-app \
      # bound_service_account_namespaces=default \
      # policies=internal-app \
      # ttl=24h

vault write auth/kubernetes/role/temporal-worker \
      bound_service_account_names=temporal-worker \
      bound_service_account_namespaces=default \
      policies=temporal-worker \
      ttl=24h
exit
```

```bash
kubectl get serviceaccounts
# kubectl create sa internal-app
kubectl create sa temporal-worker
kubectl get serviceaccounts

# kubectl apply -f deployment-orgchart.yaml
kubectl apply -f deployment-temporal-worker.yaml

# kubectl exec \
      # $(kubectl get pod -l app=orgchart -o jsonpath="{.items[0].metadata.name}") \
      # -c orgchart -- cat /vault/secrets/database-config.txt

kubectl exec \
      $(kubectl get pod -l app=temporal-worker -o jsonpath="{.items[0].metadata.name}") \
      -c orgchart -- cat /vault/secrets/database-config.txt
```

Enable and configure the PKI secrets engine.

```bash
# Enable PKI secrets engine
vault secrets enable pki

# Tune the PKI secrets engine
vault secrets tune -max-lease-ttl=8760h pki

# Create the root CA
vault write pki/root/generate/internal \
    common_name="Temporal Worker CA" \
    ttl=8760h

# Configure the PKI role
vault write pki/roles/temporal-worker \
    allowed_domains="temporal-worker.local" \
    allow_subdomains=true \
    max_ttl="720h" \
    key_usage="DigitalSignature,KeyEncipherment" \
    ext_key_usage="ServerAuth,ClientAuth"

# Create Vault policy for workers
vault policy write temporal-worker-cert - <<EOF
path "pki/issue/temporal-worker" {
  capabilities = ["create", "update"]
}
EOF

# Create Kubernetes auth role
vault write auth/kubernetes/role/temporal-worker \
    bound_service_account_names=temporal-worker \
    bound_service_account_namespaces=default \
    policies=temporal-worker-cert \
    ttl=1h
```
