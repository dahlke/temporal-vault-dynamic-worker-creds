output "client_pem" {
  value = vault_pki_secret_backend_cert.temporal_infra_worker_cert.certificate
}

output "client_key" {
  value = vault_pki_secret_backend_cert.temporal_infra_worker_cert.private_key
  sensitive = true
}

output "ca_chain_pem" {
  value = vault_pki_secret_backend_cert.temporal_infra_worker_cert.issuing_ca
}

output "terraform_test_namespace_endpoints" {
  value = temporalcloud_namespace.terraform_test.endpoints
}

output "terraform_test_namespace_id" {
  value = temporalcloud_namespace.terraform_test.id
}