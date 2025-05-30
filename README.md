# Dynamic Temporal Worker Credentials from Vault

⚠️ **Not for Production Use** ⚠️

This project demonstrates two approaches for securely managing Temporal Cloud authentication credentials in Kubernetes using [HashiCorp Vault](https://developer.hashicorp.com/vault) and the [Vault Secrets Operator](https://github.com/hashicorp/vault-secrets-operator).

## Prerequisites

- `minikube`
- `terraform`
- `vault`
- `kubectl`

## Authentication Methods

### mTLS Certificate Authentication (Recommended)

- **Automatic Rotation**: Uses Vault's PKI secrets engine to generate and automatically rotate client certificates
- **Zero Maintenance**: Certificates are automatically renewed before expiration
- **Highest Security**: Provides the strongest authentication method with no manual intervention required
- **Location**: `terraform/certs/` and `kubernetes/certs/`

### API Key Authentication

- **Manual Management**: Uses Vault's KV secrets engine to store static API keys
- **Operational Overhead**: Requires manual updates when API keys need to be rotated
- **Simpler Setup**: Easier initial configuration but requires ongoing maintenance
- **Location**: `terraform/api_keys/` and `kubernetes/api_keys/`

## Environment Setup

### Step 1: Start Minikube

```bash
minikube start --driver=docker --cpus=2 --memory=4096
```

### Step 2: Install Vault and Vault Secrets Operator

Add the HashiCorp Helm repository and install Vault in dev mode along with the Vault Secrets Operator:

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

kubectl create namespace vault

helm install -n vault vault hashicorp/vault --set "server.dev.enabled=true"
helm install -n vault vault-secrets-operator hashicorp/vault-secrets-operator
```

### Step 3: Port Forward to Vault

```bash
kubectl port-forward -n vault svc/vault 8200:8200
```

The Vault UI is now available at [`http://127.0.0.1:8200`](http://127.0.0.1:8200).

### Step 4: Configure Environment Variables

```bash
export KUBERNETES_PORT_443_TCP_ADDR=$(kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}')
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'
```

## Configuration

Choose your authentication method and navigate to the appropriate directory:

### For mTLS Certificate Authentication

```bash
cd terraform/certs/
terraform init
terraform apply -auto-approve -var "kubernetes_host=$KUBERNETES_PORT_443_TCP_ADDR"
```

#### Extract Certificates (Optional)

If you want to inspect the generated certificates:

```bash
rm *.pem *.key
terraform output -raw intermediate_client_pem > client.pem
terraform output -raw intermediate_client_key > client.key
terraform output -raw intermediate_ca_chain_pem > ca_chain.pem
terraform output -raw full_ca_chain > full_ca_chain.pem

export TEMPORAL_NAMESPACE=$(terraform output -raw terraform_test_namespace_id)
```

### For API Key Authentication

```bash
cd terraform/api_keys/
terraform init
terraform apply -auto-approve -var "kubernetes_host=$KUBERNETES_PORT_443_TCP_ADDR"
```

#### Store API Key in Vault

**Important**: Store your Temporal Cloud API key manually in Vault (do not put secrets in Terraform state):

```bash
vault kv put secret/temporal-cloud TEMPORAL_API_KEY="your-actual-api-key-here"
```

## Deployment

### Update Configuration

Before deploying, update the `ConfigMap` values in your chosen Kubernetes manifest file:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: temporal-infra-worker-config
  namespace: default
data:
  TEMPORAL_ADDRESS: "<your-temporal-host-url>"
  TEMPORAL_NAMESPACE: "<your-temporal-namespace>"
  TEMPORAL_TASK_QUEUE: "<your-temporal-task-queue>"
  TF_VAR_prefix: "<your-terraform-prefix>"
  ENCRYPT_PAYLOADS: "true"
```

### Deploy mTLS Certificate Worker

```bash
kubectl apply -f kubernetes/certs/deployment-temporal-infra-worker-vso.yaml
```

### Deploy API Key Worker

```bash
kubectl apply -f kubernetes/api_keys/deployment-temporal-infra-worker-vso.yaml
```

## Monitoring Secret Rotation

### mTLS Certificate Monitoring

Monitor certificate rotation and view certificate details:

```bash
# View the secret details
kubectl get secret temporal-tls-certs -o yaml

# Check certificate content
kubectl get secret temporal-tls-certs -o jsonpath='{.data.certificate}' | base64 -d

# Check CA chain
kubectl get secret temporal-tls-certs -o jsonpath='{.data.ca_chain}' | base64 -d

# Watch certificate rotation in real-time
watch -n 5 "kubectl get secret temporal-tls-certs -o jsonpath='{.data.certificate}' | base64 -d | openssl x509 -noout -dates"

# Monitor certificate subject and expiration
watch -n 5 "kubectl get secret temporal-tls-certs -o jsonpath='{.data.certificate}' | base64 -d | openssl x509 -noout -subject -dates"
```

### API Key Monitoring

Monitor API key synchronization:

```bash
# Check if the secret exists and has data
kubectl get secret temporal-api-key -o yaml

# Verify the API key is present (without revealing the actual key)
kubectl get secret temporal-api-key -o jsonpath='{.data.TEMPORAL_API_KEY}' | base64 -d | wc -c

# Check VaultStaticSecret status for sync issues
kubectl describe vaultstaticsecret temporal-api-key

# Monitor secret updates
kubectl get events --field-selector involvedObject.name=temporal-api-key --watch
```

### General Vault Secrets Operator Monitoring

Check VSO logs for any issues:

```bash
# Check VSO controller logs
kubectl logs -n vault-secrets-operator-system -l app.kubernetes.io/name=vault-secrets-operator

# Watch VSO logs in real-time
kubectl logs -n vault-secrets-operator-system -l app.kubernetes.io/name=vault-secrets-operator -f
```

## Key Rotation

### mTLS Certificate Rotation

Certificates rotate automatically based on the TTL configured in the Vault PKI engine. No manual intervention required.

### API Key Rotation

When your API key needs to be rotated:

1. Update the key in Vault:
   ```bash
   vault kv put secret/temporal-cloud TEMPORAL_API_KEY="your-new-api-key"
   ```

2. The Vault Secrets Operator will automatically sync the new key to Kubernetes within 30 seconds (based on the `refreshAfter` setting).

3. The worker pod will automatically restart to pick up the new credentials (due to the `rolloutRestartTargets` configuration).

## Cleanup

### Remove Kubernetes Resources

```bash
# For mTLS deployment
kubectl delete -f kubernetes/certs/deployment-temporal-infra-worker-vso.yaml

# For API key deployment  
kubectl delete -f kubernetes/api_keys/deployment-temporal-infra-worker-vso.yaml
```

### Destroy Terraform Infrastructure

```bash
# From the terraform directory you used (certs/ or api_keys/)
terraform destroy -auto-approve -var "kubernetes_host=$KUBERNETES_PORT_443_TCP_ADDR"
```

### Stop Minikube

```bash
minikube stop
minikube delete
```