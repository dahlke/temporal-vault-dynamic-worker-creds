output "terraform_test_namespace_grpc_endpoint" {
  value = temporalcloud_namespace.terraform_test.endpoints.grpc_address
}

output "terraform_test_namespace_id" {
  value = temporalcloud_namespace.terraform_test.id
}
