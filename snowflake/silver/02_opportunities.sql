-- =============================================================================
-- Silver: Salesforce OPPORTUNITIES (the sales pipeline; source of "won" revenue).
-- =============================================================================
USE WAREHOUSE RECON_TRANSFORM_WH;

CREATE OR REPLACE TABLE silver.opportunities AS
SELECT
    'SALESFORCE'              AS source_system,
    opportunity_id,
    account_id                AS source_account_id,
    TRIM(opportunity_name)    AS opportunity_name,
    UPPER(TRIM(stage))        AS stage,
    TRY_TO_NUMBER(amount)     AS amount,
    TRY_TO_DATE(close_date)    AS close_date,
    TRY_TO_TIMESTAMP_NTZ(created_date) AS created_date,
    _loaded_at                 AS etl_loaded_at
FROM bronze.sf_opportunities
QUALIFY ROW_NUMBER() OVER (PARTITION BY opportunity_id ORDER BY _loaded_at DESC) = 1;
