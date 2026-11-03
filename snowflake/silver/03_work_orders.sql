-- =============================================================================
-- Silver: Dynamics AX WORK ORDERS (operational fulfilment; expected billing).
-- =============================================================================
USE WAREHOUSE RECON_TRANSFORM_WH;

CREATE OR REPLACE TABLE silver.work_orders AS
SELECT
    'DYNAMICS_AX'               AS source_system,
    work_order_id,
    customer_id                 AS source_customer_id,
    item_id,
    TRIM(description)            AS description,
    TRY_TO_NUMBER(quantity)     AS quantity,
    TRY_TO_NUMBER(amount)       AS amount,
    UPPER(TRIM(status))         AS status,
    TRY_TO_TIMESTAMP_NTZ(created_date)   AS created_date,
    TRY_TO_TIMESTAMP_NTZ(completed_date) AS completed_date,
    _loaded_at                  AS etl_loaded_at
FROM bronze.ax_work_orders
QUALIFY ROW_NUMBER() OVER (PARTITION BY work_order_id ORDER BY _loaded_at DESC) = 1;
