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

variable "vault_address" {
  type = string
  default = "http://127.0.0.1:8200"
}

variable "vault_token" {
  type = string
  default = "root"
}

variable "kubernetes_host" {
  type = string
}

variable "prefix" {
  type = string
}
