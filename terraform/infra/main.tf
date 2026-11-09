# Shared infrastructure of an environment (queues, identities, permissions).
# Changes only when this pipeline code changes, not with an app release.

terraform {
  required_version = ">= 1.5"
  backend "local" {}
}

variable "environment" {
  type = string
}

resource "terraform_data" "queues" {
  input = {
    environment = var.environment
    queues      = ["inbound", "outbound", "alerts"]
  }
}

resource "terraform_data" "identities" {
  input = {
    environment = var.environment
    identities  = ["app", "worker", "gateway"]
  }
}
