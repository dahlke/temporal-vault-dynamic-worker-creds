# Dynamic Temporal Worker Credentials from Vault (Certs & API Keys)

⚠️ Not for Production Use ⚠️

## Requirements

- `minikube`
- `terraform`
- `vault`
- `kubectl`

This is a sample project to rotate the certificates or API keys and inject them into a Temporal
worker running in Kubernetes, using Vault's PKI secrets engine or Vault's KV secret engine and the
[Vault Secrets Operator](https://github.com/hashicorp/vault-secrets-operator).

## Vault and Minikube Startup

Start up a Minikube cluster with 2 CPUs and 4GB of memory.

```bash
minikube start --driver=docker --cpus=2 --memory=4096
```

### Run Vault in dev mode in Kubernetes

Add the HashiCorp Helm repository, create a namespace for Vault, and install Vault in Minikube in
Dev mode. We'll also install the Vault Secrets Operator at this stage.

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

There are two Terraform configurations, one for setting up Vault and Temporal Cloud for mTLS
authentication, and another with API key authentication. Choose which option you want by `cd`ing
int the appropriate `./terraform` directory.

```bash
terraform apply -auto-approve -var "kubernetes_host=$KUBERNETES_PORT_443_TCP_ADDR"
```

Whenever you need to destroy the Terraform configuration, you can do so with the following command.

```bash
terraform destroy -auto-approve -var "kubernetes_host=$KUBERNETES_PORT_443_TCP_ADDR"
```

If you are using the mTLS approach, once the Terraform configuration is applied, you can extract
the certs to files if you'd like to inspect them or use them directly.

```bash
rm *.pem *.key
terraform output -raw intermediate_client_pem > client.pem
terraform output -raw intermediate_client_key > client.key
terraform output -raw intermediate_ca_chain_pem > ca_chain.pem
terraform output -raw full_ca_chain > full_ca_chain.pem

export TEMPORAL_NAMESPACE=$(terraform output -raw terraform_test_namespace_id)
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

In the `kubernetes` directory, there are two different ways to deploy the Temporal worker allowing
consumption of dynamic credentials from Vault with the [Vault Secrets Operator](https://github.com/hashicorp/vault-secrets-operator)

You'll need to update the `ConfigMap` named `temporal-infra-worker-config` with the correct values
for `TEMPORAL_ADDRESS`, `TEMPORAL_NAMESPACE`, `TEMPORAL_TASK_QUEUE`, and `TF_VAR_prefix` in
whichever Kubernetes manifest file you choose from the `./kubernetes` directory.

```bash
apiVersion: v1
kind: ConfigMap
metadata:
  name: temporal-infra-worker-config
data:
  TEMPORAL_ADDRESS: "<your-temporal-host-url>"
  TEMPORAL_NAMESPACE: "<your-temporal-namespace>"
  TEMPORAL_TASK_QUEUE: "<your-temporal-task-queue>"
  TF_VAR_prefix: "<your-terraform-prefix>"
  ENCRYPT_PAYLOADS: "true"
```

### With Vault Agent Injector

Deploy the Temporal worker.

kubectl apply -f kubernetes/certs/vault-agent-sidecar/deployment-temporal-infra-worker-agent.yaml

```

Then, to watch the secret be rotated, you can run the following commands.

```bash
POD_NAME=$(kubectl get pods -n default -l app=temporal-infra-worker -o jsonpath='{.items[0].metadata.name}')

watch -n 1 kubectl exec -n default $POD_NAME -- cat /vault/secrets/tls-cert.pem
watch -n 1 kubectl exec -n default $POD_NAME -- cat /vault/secrets/tls-key.pem
```

### With Vault Secrets Operator

#### Certificates

```bash
kubectl apply -f kubernetes/certs/vault-secrets-operator/deployment-temporal-infra-worker-vso.yaml
```

Then, to watch the secret be rotated, you can run the following commands.

```bash
kubectl get secret temporal-tls-certs -o yaml
kubectl get secret temporal-tls-certs -o jsonpath='{.data.ca_chain}' | base64 -d
kubectl get secret temporal-tls-certs -o jsonpath='{.data.certificate}' | base64 -d

watch -n 1 "kubectl get secret temporal-tls-certs -o jsonpath='{.data.ca_chain}' | base64 -d"
watch -n 1 "kubectl get secret temporal-tls-certs -o jsonpath='{.data.certificate}' | base64 --decode"
```

To tear down the deployment.

```bash
kubectl delete -f kubernetes/certs/deployment-temporal-infra-worker-vso.yaml
```

#### API Keys

Place the API key into Vault.

```bash
vault kv put secret/temporal-cloud TEMPORAL_API_KEY=$TEMPORAL_API_KEY
```

```bash
kubectl apply -f kubernetes/api_keys/deployment-temporal-infra-worker-vso.yaml
```

To tear down the deployment.

```bash
kubectl delete -f kubernetes/api_keys/deployment-temporal-infra-worker-vso.yaml
```

### Cleaning up

```bash
terraform destroy -auto-approve -var "kubernetes_host=$KUBERNETES_PORT_443_TCP_ADDR"
```

# TODO

- don't use the default namespace
- clean up this README, clearer instructions, record a video.
- does the static need a refresh?
- change the roles / policies to be specific to the way they are doing auth.