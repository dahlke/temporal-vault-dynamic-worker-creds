terraform {
  required_providers {
    temporalcloud = {
      source = "temporalio/temporalcloud"
    }
    vault = {
      source = "hashicorp/vault"
    }
  }
}

provider "temporalcloud" {
  endpoint       = var.endpoint       # or env var `TEMPORAL_CLOUD_ENDPOINT`
  allow_insecure = var.allow_insecure # or env var `TEMPORAL_CLOUD_ALLOW_INSECURE`
}

provider "vault" {
  address = var.vault_address # or env var `VAULT_ADDR`
  token = var.vault_token # or env var `VAULT_TOKEN`
}

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  depends_on = [vault_auth_backend.kubernetes]

  backend = vault_auth_backend.kubernetes.path

  kubernetes_host = "https://${var.kubernetes_host}:443"
}

resource "vault_kubernetes_auth_backend_role" "temporal_infra_worker" {
  depends_on = [vault_auth_backend.kubernetes, vault_policy.temporal_infra_worker]

  role_name = "temporal-infra-worker"
  backend = vault_auth_backend.kubernetes.path
  bound_service_account_names = ["temporal-infra-worker"]
  bound_service_account_namespaces = ["temporal-workers", "vault"]
  token_policies = [vault_policy.temporal_infra_worker.name]
  token_ttl = 24 * 60 * 60
}

resource "vault_policy" "temporal_infra_worker" {
  name = "temporal-infra-worker"

  policy = <<EOF
# Allow reading from the default KV store
path "secret/*" {
   capabilities = ["read"]
}
EOF
}

resource "random_id" "random_suffix" {
  byte_length = 4
}

resource "temporalcloud_namespace" "terraform_test" {
  name               = "${var.prefix}-vault-api-keys-${random_id.random_suffix.hex}"
  regions            = [var.region]
  api_key_auth       = true
  retention_days     = 1
}
