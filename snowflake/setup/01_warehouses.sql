-- =============================================================================
-- 01_warehouses.sql
-- Virtual-warehouse sizing strategy for the reconciliation platform.
-- Each warehouse is purpose-built; auto-suspend keeps cost down between runs.
-- Requires ACCOUNTADMIN (or a role granted CREATE WAREHOUSE on the account).
-- =============================================================================

-- Lightweight, spiky ingestion: tiny, fast suspend.
CREATE OR REPLACE WAREHOUSE RECON_LOAD_WH
  WAREHOUSE_SIZE       = 'X-SMALL'
  AUTO_SUSPEND         = 60          -- seconds idle before auto-suspend
  AUTO_RESUME          = TRUE
  INITIALLY_SUSPENDED  = TRUE
  SCALING_POLICY       = 'STANDARD'
  COMMENT              = 'Bronze ingestion: COPY/PUT loads (low concurrency, spiky).';

-- Heavier transforms, SCD2 MERGEs, entity resolution: bigger.
CREATE OR REPLACE WAREHOUSE RECON_TRANSFORM_WH
  WAREHOUSE_SIZE       = 'SMALL'
  AUTO_SUSPEND         = 60
  AUTO_RESUME          = TRUE
  INITIALLY_SUSPENDED  = TRUE
  SCALING_POLICY       = 'ECONOMY'   -- favour reusing already-started clusters
  COMMENT              = 'Silver + Gold transforms (joins, SCD2, fuzzy matching).';

-- Dashboard/reporting: tiny, quick suspend.
CREATE OR REPLACE WAREHOUSE RECON_REPORTING_WH
  WAREHOUSE_SIZE       = 'X-SMALL'
  AUTO_SUSPEND         = 30
  AUTO_RESUME          = TRUE
  INITIALLY_SUSPENDED  = TRUE
  COMMENT              = 'Semantic-layer queries and dashboard refresh.';
