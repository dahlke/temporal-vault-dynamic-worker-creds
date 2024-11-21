# Rotating Temporal Workers Certificates in Kubernetes with Vault

## Requirements

- `minikube`
- `terraform`
- `vault`
- `kubectl`

This is a sample project to rotate the certificates for a Temporal worker running in Kubernetes,
using Vault's PKI Secrets Engine to generate certs and deliver them to the worker pods with either
the Vault Agent Injector or the Vault Secrets Operator.

## Vault and Minikube Startup

Start up a Minikube cluster with 2 CPUs and 4GB of memory.

```bash
minikube start --driver=docker --cpus=2 --memory=4096
```

### Run Vault in dev mode in Kubernetes

Add the HashiCorp Helm repository, create a namespace for Vault, and install Vault in Minikube in
Dev mode. We'll also install the [Vault Secrets Operator](https://github.com/hashicorp/vault-secrets-operator)
at this stage.

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

kubectl create namespace vault

helm install -n vault vault hashicorp/vault --set "server.dev.enabled=true"
helm install -n vault vault-secrets-operator hashicorp/vault-secrets-operator
```

For ease of use while developing, port forward locally to Vault installed in Kubernetes.

```bash
kubectl port-forward -n vault svc/vault 8200:8200
```

The Vault UI is now available at [`http://127.0.0.1:8200`](http://127.0.0.1:8200).

### Configure Vault and Create Temporal Namespace w/ Terraform

Now that Vault is running, initialize Terraform.

```bash
terraform init
```

Get the Kubernetes cluster IP address and set the Vault address and token. Since we're running Vault
in dev mode and port forwarding locally, we can use the root token and localhost for the Vault address.

```bash
export KUBERNETES_PORT_443_TCP_ADDR=$(kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}')
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'
```

Then apply the Terraform configuration. The Terraform configuration will mount the PKI engine in Vault,
create a root CA, and create a role and certificate for the Temporal worker. It will use the issuing
CA to create a new namespace in Temporal Cloud.

```bash
terraform apply -auto-approve -var "kubernetes_host=$KUBERNETES_PORT_443_TCP_ADDR"
```

Whenever you need to destroy the Terraform configuration, you can do so with the following command.

```bash
terraform destroy -auto-approve -var "kubernetes_host=$KUBERNETES_PORT_443_TCP_ADDR"
```

Once the Terraform configuration is applied, you can extract the certs to files if you'd like to
inspect them or use them directly.

```bash
terraform output -raw client_pem > client.pem
terraform output -raw client_key > client.key
terraform output -raw ca_chain_pem > ca_chain.pem
```

You can also use `tcld` to easily add and remove the CA cert from the Temporal namespace.

```bash
tcld namespace accepted-client-ca add \
  --namespace $TEMPORAL_NAMESPACE \
  --ca-certificate $(cat ca_chain.pem | base64)

tcld namespace accepted-client-ca remove \
  --namespace $TEMPORAL_NAMESPACE \
  --fp $(tcld namespace accepted-client-ca list \
  --namespace $TEMPORAL_NAMESPACE | jq '.[0].fingerprint')
```

To see all of your outputs, including the name of the new Temporal namespace, run the following command.

```bash
terraform output
```

## Deploy Temporal Worker

In the `kubernetes` directory, there are two different ways to deploy the Temporal worker: with the
Vault Agent Injector or with the Vault Secrets Operator. You'll need to make some modifications to
a few files before we can deploy the worker.

In both `kubernetes/vault-secrets-operator/deployment-temporal-infra-worker-vso.yaml` and
`kubernetes/vault-agent-sidecar/deployment-temporal-infra-worker-agent.yaml`, you'll need to update
the `ConfigMap` named `temporal-infra-worker-config` with the correct values for `TEMPORAL_HOST_URL`,
`TEMPORAL_NAMESPACE`, `TEMPORAL_TASK_QUEUE`, and `TF_VAR_prefix`.

```bash
apiVersion: v1
kind: ConfigMap
metadata:
  name: temporal-infra-worker-config
data:
  TEMPORAL_HOST_URL: "<your-temporal-host-url>"
  TEMPORAL_NAMESPACE: "<your-temporal-namespace>"
  TEMPORAL_TASK_QUEUE: "<your-temporal-task-queue>"
  TF_VAR_prefix: "<your-terraform-prefix>"
  ENCRYPT_PAYLOADS: "true"
```

You'll also need to update the `Secret` named `temporal-secrets` with the correct values for
`cloud-api-key`.

```bash
apiVersion: v1
kind: Secret
metadata:
  name: temporal-secrets
type: Opaque
data:
  cloud-api-key: "<your-cloud-api-key>"
```

### With Vault Agent Injector

Deploy the Temporal worker.

```bash
kubectl apply -f kubernetes/vault-agent-sidecar/deployment-temporal-infra-worker-agent.yaml
```

### With Vault Secrets Operator

```bash
kubectl apply -f kubernetes/vault-secrets-operator/deployment-temporal-infra-worker-vso.yaml
```

## [IN DEVELOPMENT] Rotate the Root CA

Now say you want to rotate the root CA, you can do so with the following command.

```bash
vault write pki/root/rotate/internal \
    common_name="dahlke" \
    organization="dahlke" \
    key_type="rsa" \
    key_bits=4096 \
    exclude_cn_from_sans=true

vault read -field=certificate pki/cert/ca > new_ca.pem

# Generate a new intermediate CA
vault write -format=json pki_int/intermediate/generate/internal \
    common_name="New Intermediate CA" ttl="8760h" > pki_intermediate.json

# Extract the CSR from the generated intermediate CA
csr=$(jq -r '.data.csr' pki_intermediate.json)

# Sign the intermediate CA with the root CA
vault write -format=json pki/root/sign-intermediate \
    csr="$csr" \
    format="pem_bundle" \
    ttl="8760h" > intermediate.cert.json

cat intermediate.cert.json | jq -r '.data.certificate' > intermediate.cert.pem
cat intermediate.cert.json | jq -r '.data.ca_chain[]' > new_ca_chain.pem

# Set the signed certificate for the intermediate CA
vault write pki_int/intermediate/set-signed \
    certificate=@intermediate.cert.pem

# issuing_ca=$(vault read -field=certificate pki_int/cert/ca)
# root_cert=$(vault read -field=certificate pki/cert/ca)
# echo -e "${issuing_ca}\n${root_cert}" > new_ca_chain.pem

```

Add the new CA cert to the Temporal namespace.

```bash
export TEMPORAL_NAMESPACE="neil-terraform-demo-de39616c.sdvdw"

tcld namespace accepted-client-ca add \
  --namespace $TEMPORAL_NAMESPACE \
  --ca-certificate $(cat new_ca_chain.pem | base64)
```
