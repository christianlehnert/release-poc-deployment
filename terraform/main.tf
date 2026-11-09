# Simulated infrastructure: two "container apps" whose image comes from versions.tfvars.
# terraform_data stands in for a real resource, so plan and apply behave like the real thing
# ("update in-place" when a version changes) without any cloud account.

terraform {
  required_version = ">= 1.5"
  backend "local" {}
}

variable "environment" {
  type = string
}

variable "app_tag" {
  type        = string
  description = "Version of the app, for example release/1.0.1"
  validation {
    condition     = startswith(var.app_tag, "release/")
    error_message = "Only release/* versions are allowed."
  }
}

variable "ui_tag" {
  type        = string
  description = "Version of the UI, for example release/2.0.0"
  validation {
    condition     = startswith(var.ui_tag, "release/")
    error_message = "Only release/* versions are allowed."
  }
}

resource "terraform_data" "app" {
  input = {
    environment = var.environment
    image       = "registry.example/app:${replace(var.app_tag, "/", "-")}"
  }
}

resource "terraform_data" "ui" {
  input = {
    environment = var.environment
    image       = "registry.example/ui:${replace(var.ui_tag, "/", "-")}"
  }
}

output "images" {
  value = {
    app = terraform_data.app.output.image
    ui  = terraform_data.ui.output.image
  }
}
