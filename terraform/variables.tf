# =============================================================================
# Variables for the Snowflake reconciliation platform IaC.
# Provide non-secret values in terraform.tfvars (gitignored) and secrets via
# environment variables (TF_VAR_snowflake_password / key pair).
# =============================================================================

variable "snowflake_account" {
  description = "Snowflake account identifier, e.g. xy12345.eu-central-1.aws"
  type        = string
}

variable "snowflake_user" {
  description = "Snowflake user used by Terraform (ACCOUNTADMIN for provisioning)."
  type        = string
}

variable "snowflake_role" {
  description = "Role to use when provisioning."
  type        = string
  default     = "ACCOUNTADMIN"
}

variable "snowflake_password" {
  description = "Password for the Terraform user. Prefer key-pair auth in prod."
  type        = string
  sensitive   = true
}

variable "database_name" {
  description = "Name of the reconciliation database."
  type        = string
  default     = "RECON_PLATFORM"
}

variable "warehouse_size" {
  description = "Size of the transform warehouse."
  type        = string
  default     = "SMALL"
}

variable "credit_quota_load" {
  description = "Monthly credit quota for the load warehouse monitor."
  type        = number
  default     = 25
}

variable "credit_quota_transform" {
  description = "Monthly credit quota for the transform warehouse monitor."
  type        = number
  default     = 40
}

variable "credit_quota_reporting" {
  description = "Monthly credit quota for the reporting warehouse monitor."
  type        = number
  default     = 15
}
