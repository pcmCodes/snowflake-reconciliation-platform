-- =============================================================================
-- 02_databases_schemas.sql
-- Medallion database + schema scaffolding.
-- =============================================================================

CREATE OR REPLACE DATABASE RECON_PLATFORM
  COMMENT = 'Reconciliation platform - BrightFibre (Salesforce + Dynamics AX + PowerBill).';

USE DATABASE RECON_PLATFORM;

CREATE OR REPLACE SCHEMA BRONZE   COMMENT = 'Raw landed source data with lineage metadata.';
CREATE OR REPLACE SCHEMA SILVER  COMMENT = 'Cleaned, conformed entities (one row per source entity).';
CREATE OR REPLACE SCHEMA GOLD    COMMENT = 'Dimensional model (SCD2) + revenue-leakage exceptions.';
CREATE OR REPLACE SCHEMA SEMANTIC COMMENT = 'Revenue Assurance dashboard views.';
