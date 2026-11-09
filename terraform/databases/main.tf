# Database schemas. Runs before the apps, so a new app version finds its schema.
# Values come from the db_*_schema lines of versions.tfvars.

terraform {
  required_version = ">= 1.5"
  backend "local" {}
}

variable "environment" {
  type = string
}

variable "schemas" {
  type        = map(string)
  description = "Schema version per database, for example { core = \"1.0.0\" }"
}

resource "terraform_data" "schema" {
  for_each = var.schemas
  input = {
    environment = var.environment
    database    = each.key
    version     = each.value
  }
}
