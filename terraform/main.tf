# =============================================================================
# Infrastructure-as-code for the Snowflake Reconciliation Platform.
# This is the Terraform equivalent of snowflake/setup/*.sql: it provisions the
# warehouses, database, schemas, roles/grants and resource monitors, so the
# platform's governance objects are version-controlled and reviewable.
#
# Provider: Snowflake-Labs/snowflake  (https://registry.terraform.io/providers/Snowflake-Labs/snowflake)
# Usage:
#   cp terraform.tfvars.example terraform.tfvars   # fill in account/user
#   export TF_VAR_snowflake_password='...'         # or use a key pair
#   terraform init && terraform plan && terraform apply
# =============================================================================
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.90"
    }
  }
}

provider "snowflake" {
  account  = var.snowflake_account
  user     = var.snowflake_user
  password = var.snowflake_password
  role     = var.snowflake_role
}

# ---------------------------------------------------------------------------
# Warehouses (auto-suspend keeps cost down between runs)
# ---------------------------------------------------------------------------
resource "snowflake_warehouse" "load" {
  name           = "RECON_LOAD_WH"
  warehouse_size = "XSMALL"
  auto_suspend   = 60
  auto_resume    = "true"
  initially_suspended = "true"
}

resource "snowflake_warehouse" "transform" {
  name           = "RECON_TRANSFORM_WH"
  warehouse_size = var.warehouse_size
  auto_suspend   = 60
  auto_resume    = "true"
  initially_suspended = "true"
  scaling_policy = "ECONOMY"
}

resource "snowflake_warehouse" "reporting" {
  name           = "RECON_REPORTING_WH"
  warehouse_size = "XSMALL"
  auto_suspend   = 30
  auto_resume    = "true"
  initially_suspended = "true"
}

# ---------------------------------------------------------------------------
# Database + medallion schemas
# ---------------------------------------------------------------------------
resource "snowflake_database" "platform" {
  name    = var.database_name
  comment = "Reconciliation platform - BrightFibre (Salesforce + Dynamics AX + PowerBill)."
}

resource "snowflake_schema" "bronze" {
  database = snowflake_database.platform.name
  name     = "BRONZE"
  comment  = "Raw landed source data with lineage metadata."
}

resource "snowflake_schema" "silver" {
  database = snowflake_database.platform.name
  name     = "SILVER"
  comment  = "Cleaned, conformed entities."
}

resource "snowflake_schema" "gold" {
  database = snowflake_database.platform.name
  name     = "GOLD"
  comment  = "Dimensional model (SCD2) + revenue-leakage exceptions."
}

resource "snowflake_schema" "semantic" {
  database = snowflake_database.platform.name
  name     = "SEMANTIC"
  comment  = "Revenue Assurance dashboard views."
}

# ---------------------------------------------------------------------------
# RBAC: least-privilege functional roles + hierarchy + warehouse usage
# ---------------------------------------------------------------------------
resource "snowflake_role" "engineer" { name = "RECON_ENGINEER" }
resource "snowflake_role" "analyst"  { name = "RECON_ANALYST" }
resource "snowflake_role" "reader"   { name = "RECON_READER" }

resource "snowflake_grant_privileges_to_role" "engineer_schemas" {
  role  = snowflake_role.engineer.name
  privileges = ["USAGE", "CREATE TABLE", "CREATE VIEW", "CREATE STAGE", "CREATE FILE FORMAT"]
  on_schema {
    schema = snowflake_schema.bronze.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_role" "engineer_wh_load" {
  role = snowflake_role.engineer.name
  privileges = ["USAGE"]
  on_account_object { warehouse = snowflake_warehouse.load.name }
}

resource "snowflake_grant_privileges_to_role" "analyst_wh" {
  role = snowflake_role.analyst.name
  privileges = ["USAGE"]
  on_account_object { warehouse = snowflake_warehouse.reporting.name }
}

# ---------------------------------------------------------------------------
# Resource monitors (monthly credit caps, notify -> suspend)
# ---------------------------------------------------------------------------
resource "snowflake_resource_monitor" "load" {
  name          = "rm_recon_load"
  credit_quota  = var.credit_quota_load
  frequency     = "MONTHLY"
  start_timestamp = "IMMEDIATELY"
  notify_triggers {
    threshold    = 80
    action       = "NOTIFY"
  }
  suspend_triggers {
    threshold = 100
  }
}

resource "snowflake_resource_monitor" "transform" {
  name          = "rm_recon_transform"
  credit_quota  = var.credit_quota_transform
  frequency     = "MONTHLY"
  start_timestamp = "IMMEDIATELY"
  suspend_triggers {
    threshold = 100
  }
}

resource "snowflake_resource_monitor" "reporting" {
  name          = "rm_recon_reporting"
  credit_quota  = var.credit_quota_reporting
  frequency     = "MONTHLY"
  start_timestamp = "IMMEDIATELY"
  notify_triggers {
    threshold = 80
    action    = "NOTIFY"
  }
}

# Attach monitors to warehouses
resource "snowflake_warehouse_resource_monitor" "load" {
  warehouse        = snowflake_warehouse.load.name
  resource_monitor = snowflake_resource_monitor.load.name
}
