output "intermediate_ca_issuing_certificates" {
  value = vault_pki_secret_backend_config_urls.pki_int_urls.issuing_certificates
}

output "intermediate_ca_crl_distribution_points" {
  value = vault_pki_secret_backend_config_urls.pki_int_urls.crl_distribution_points
}

output "intermediate_ca_role_name" {
  value = vault_pki_secret_backend_role.temporal_infra_worker_intermediate.name
}

output "intermediate_ca_cert_common_name" {
  value = vault_pki_secret_backend_cert.temporal_infra_worker_cert_intermediate.common_name
}

output "intermediate_client_pem" {
  value = vault_pki_secret_backend_cert.temporal_infra_worker_cert_intermediate.certificate
}

output "intermediate_client_key" {
  value     = vault_pki_secret_backend_cert.temporal_infra_worker_cert_intermediate.private_key
  sensitive = true
}

output "intermediate_ca_chain_pem" {
  value = vault_pki_secret_backend_cert.temporal_infra_worker_cert_intermediate.ca_chain
}

output "terraform_test_namespace_endpoints" {
  value = temporalcloud_namespace.terraform_test.endpoints
}

output "terraform_test_namespace_id" {
  value = temporalcloud_namespace.terraform_test.id
}

output "full_ca_chain" {
  value = <<EOT
${vault_pki_secret_backend_intermediate_set_signed.set_signed_intermediate.certificate}
${vault_pki_secret_backend_root_cert.root_cert.certificate}
EOT
  sensitive = true
}
