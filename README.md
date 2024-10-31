# temporal-vault-certs

## Requirements
- `jq`
- `vault`
- `terraform`
- `temporal`

## Walkthrough

Start a dev server.

```bash
vault server -dev -dev-root-token-id="root"
```

Set your env vars.

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'
export TEMPORAL_ADDRESS="<your-namespace>.tmprl.cloud:7233"
export TEMPORAL_NAMESPACE="<your-namespace>"
export TEMPORAL_TLS_CERT="$(pwd)/client.pem"
export TEMPORAL_TLS_KEY="$(pwd)/client.key"
```

Confirm Vault is up and running

```bash
vault status
```

Run the Vault script. This will mount the PKI secrets engine and create a CA,
then create a role and issue a cert for the Temporal service. Lastly, the
cert is uploaded to the namespace.

```bash
./vault.sh
```# temporal-vault-certs
