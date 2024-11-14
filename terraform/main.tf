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

resource "vault_mount" "pki" {
  path        = "pki"
  type        = "pki"
  description = "PKI secrets engine"
  max_lease_ttl_seconds = 87600 * 3600
}

resource "vault_pki_secret_backend_config_urls" "pki_urls" {
  backend = vault_mount.pki.path

  issuing_certificates    = ["${var.vault_address}/v1/pki/ca"]
  crl_distribution_points = ["${var.vault_address}/v1/pki/crl"]
}

resource "vault_pki_secret_backend_root_cert" "root_cert" {
  backend = vault_mount.pki.path
  type = "internal"
  common_name = "dahlke"
  organization = "dahlke"
  key_type = "rsa"
  key_bits = 4096
  exclude_cn_from_sans = true
}

resource "vault_pki_secret_backend_role" "temporal_infra_worker" {
  backend = vault_mount.pki.path

  name = "temporal-infra-worker"
  allowed_domains = ["dahlke.io"]
  allow_subdomains = true
  max_ttl = "720h"
  key_type = "rsa"
  key_bits = 2048
  allow_any_name = true
  key_usage = ["DigitalSignature"]
  ext_key_usage = ["ClientAuth"]
  require_cn = false
}

resource "vault_pki_secret_backend_cert" "temporal_infra_worker_cert" {
  backend = vault_mount.pki.path
  name    = "temporal-infra-worker"
  common_name = "worker.dahlke.io"
  ttl = "720h"
  private_key_format = "pkcs8"

  depends_on = [vault_pki_secret_backend_role.temporal_infra_worker]
}

resource "vault_mount" "kvv1" {
  path        = "kvv1"
  type        = "kv"
  options     = { version = "1" }
  description = "KV Version 1 secret engine mount"
}

resource "vault_kv_secret" "secret" {
  path = "${vault_mount.kvv1.path}/secret"
  data_json = jsonencode(
  {
    username = "db-readonly-username"
    password = "db-secret-password"
  }
  )
}

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  depends_on = [vault_auth_backend.kubernetes]

  backend = vault_auth_backend.kubernetes.path

  kubernetes_host = "https://${var.kubernetes_host}:443"
}

resource "vault_policy" "temporal_infra_worker" {
  name = "temporal-infra-worker"

  policy = <<EOF
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
}

resource "vault_kubernetes_auth_backend_role" "temporal_infra_worker" {
  depends_on = [vault_auth_backend.kubernetes, vault_policy.temporal_infra_worker]

  role_name = "temporal-infra-worker"
  backend = vault_auth_backend.kubernetes.path
  bound_service_account_names = ["temporal-infra-worker"]
  bound_service_account_namespaces = ["default", "vault"]
  token_policies = [vault_policy.temporal_infra_worker.name]
  token_ttl = 24 * 60 * 60
}


resource "random_id" "random_suffix" {
  byte_length = 4
}

resource "temporalcloud_namespace" "terraform_test" {
  name               = "${var.prefix}-terraform-demo-${random_id.random_suffix.hex}"
  regions            = [var.region]
  accepted_client_ca = base64encode(vault_pki_secret_backend_cert.temporal_infra_worker_cert.issuing_ca)
  retention_days     = 7
}
