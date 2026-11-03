-- =============================================================================
-- Silver: Dynamics AX ITEMS (assets/catalogue) - the product master.
-- =============================================================================
USE WAREHOUSE RECON_TRANSFORM_WH;

CREATE OR REPLACE TABLE silver.assets AS
SELECT
    item_id,
    TRIM(item_name)           AS item_name,
    TRIM(category)            AS category,
    TRY_TO_NUMBER(unit_price) AS unit_price,
    _loaded_at                AS etl_loaded_at
FROM bronze.ax_items
QUALIFY ROW_NUMBER() OVER (PARTITION BY item_id ORDER BY _loaded_at DESC) = 1;
