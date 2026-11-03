-- =============================================================================
-- 05_file_formats_stages.sql
-- Shared CSV file format + internal named stage that holds generated source CSVs.
-- run_pipeline.py PUTs data_output/<source>/<table>.csv into @recon_csv_stage.
-- =============================================================================

USE DATABASE RECON_PLATFORM;
USE SCHEMA BRONZE;

-- Shared CSV format for all three source systems -----------------------------
CREATE OR REPLACE FILE FORMAT ff_recon_csv
  TYPE                          = CSV
  FIELD_DELIMITER               = ','
  SKIP_HEADER                   = 1
  FIELD_OPTIONALLY_ENCLOSED_BY  = '"'
  NULL_IF                       = ('', 'NULL')
  TRIM_SPACE                    = TRUE
  EMPTY_FIELD_AS_NULL           = TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
  ENCODING                      = 'UTF8'
  COMMENT                       = 'CSV format for Salesforce/Dynamics AX/PowerBill loads.';

-- Internal named stage (schema-level object) --------------------------------
CREATE OR REPLACE STAGE recon_csv_stage
  FILE_FORMAT = ff_recon_csv
  COMMENT     = 'Landing area for synthetic source CSVs (PUT from run_pipeline.py).';
