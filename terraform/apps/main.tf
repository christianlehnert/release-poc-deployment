# The applications. One container app per line <name>_tag in versions.tfvars.
# A new application only needs a new line in versions.tfvars, no code change here.
# Feature flags come from features.tfvars of the environment (not promoted from TEST).

terraform {
  required_version = ">= 1.5"
  backend "local" {}
}

variable "environment" {
  type = string
}

variable "versions" {
  type        = map(string)
  description = "Version per application, for example { app = \"release/1.0.2\" }"
  validation {
    condition     = alltrue([for v in values(var.versions) : startswith(v, "release/") || (var.environment == "dev" && (startswith(v, "main/") || startswith(v, "preview/")))])
    error_message = "Only release/* versions are allowed (main/* and preview/* only on dev)."
  }
}

variable "digests" {
  type        = map(string)
  default     = {}
  description = "Image digest per application (sha256:...). The same digest runs in every stage."
}

variable "features" {
  type        = map(bool)
  default     = {}
  description = "Feature flags of this environment"
}

resource "terraform_data" "app" {
  for_each = var.versions
  input = {
    environment = var.environment
    image       = contains(keys(var.digests), each.key) ? "ghcr.io/christianlehnert/release-poc-${each.key}:${replace(each.value, "/", "-")}" : "registry.example/${each.key}:${replace(each.value, "/", "-")}"
    digest      = lookup(var.digests, each.key, "")
    features    = var.features
  }
}

output "images" {
  value = { for k, r in terraform_data.app : k => r.output.image }
}
