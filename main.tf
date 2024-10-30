terraform {
  required_providers {
    temporalcloud = {
      source = "temporalio/temporalcloud"
    }
  }
}

variable "endpoint" {
  type    = string
  default = "saas-api.tmprl.cloud:443"
}

variable "region" {
  type    = string
  default = "aws-us-west-2"
}

variable "allow_insecure" {
  type    = bool
  default = false
}


variable "prefix" {
  type = string
}

provider "temporalcloud" {
  endpoint       = var.endpoint       # or env var `TEMPORAL_CLOUD_ENDPOINT`
  allow_insecure = var.allow_insecure # or env var `TEMPORAL_CLOUD_ALLOW_INSECURE`
}

resource "random_id" "random_suffix" {
  byte_length = 4
}

# Create the Temporal Cloud namespace with mTLS configuration
resource "temporalcloud_namespace" "terraform_test" {
  name               = "${var.prefix}-terraform-demo-${random_id.random_suffix.hex}"
  regions            = [var.region]
  accepted_client_ca = base64encode(file("${path.module}/ca_chain.pem"))
  retention_days     = 7
  /*
  lifecycle {
    ignore_changes = [
      accepted_client_ca,
    ]
  }
  */
}

output "terraform_test_namespace_endpoints" {
  value = temporalcloud_namespace.terraform_test.endpoints
}

output "terraform_test_namespace_id" {
  value = temporalcloud_namespace.terraform_test.id
}
