-- =============================================================================
-- Silver: PowerBill INVOICES + INVOICE_LINES (actual billing - the truth set for
-- reconciliation). Both kept here; Gold consumes them.
-- =============================================================================
USE WAREHOUSE RECON_TRANSFORM_WH;

CREATE OR REPLACE TABLE silver.invoices AS
SELECT
    'POWERBILL'              AS source_system,
    invoice_id,
    customer_code            AS source_customer_id,
    TRY_TO_DATE(invoice_date) AS invoice_date,
    TRY_TO_DATE(due_date)    AS due_date,
    TRY_TO_NUMBER(total_amount) AS total_amount,
    UPPER(TRIM(invoice_status)) AS invoice_status,
    TRIM(billing_period)     AS billing_period,
    _loaded_at               AS etl_loaded_at
FROM bronze.pb_invoices
QUALIFY ROW_NUMBER() OVER (PARTITION BY invoice_id ORDER BY _loaded_at DESC) = 1;

CREATE OR REPLACE TABLE silver.invoice_lines AS
SELECT
    line_id,
    invoice_id,
    TRIM(description)         AS description,
    TRY_TO_NUMBER(quantity)  AS quantity,
    TRY_TO_NUMBER(unit_price) AS unit_price,
    TRY_TO_NUMBER(line_amount) AS line_amount,
    TRY_TO_NUMBER(tax_amount)  AS tax_amount,
    _loaded_at                AS etl_loaded_at
FROM bronze.pb_invoice_lines
QUALIFY ROW_NUMBER() OVER (PARTITION BY line_id ORDER BY _loaded_at DESC) = 1;
