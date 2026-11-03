-- =============================================================================
-- Silver: Dynamics AX CONTRACTS (recurring/committed revenue; expected billing).
-- =============================================================================
USE WAREHOUSE RECON_TRANSFORM_WH;

CREATE OR REPLACE TABLE silver.contracts AS
SELECT
    'DYNAMICS_AX'             AS source_system,
    contract_id,
    customer_id               AS source_customer_id,
    TRIM(contract_name)       AS contract_name,
    TRY_TO_DATE(start_date)   AS start_date,
    TRY_TO_DATE(end_date)     AS end_date,
    TRY_TO_NUMBER(annual_value) AS annual_value,
    UPPER(TRIM(status))       AS status,
    _loaded_at                AS etl_loaded_at
FROM bronze.ax_contracts
QUALIFY ROW_NUMBER() OVER (PARTITION BY contract_id ORDER BY _loaded_at DESC) = 1;
