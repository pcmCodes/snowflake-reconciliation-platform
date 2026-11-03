-- =============================================================================
-- Silver: conformed CUSTOMERS (Salesforce accounts + Dynamics AX customers +
-- PowerBill customers). source_system + source_customer_id retained for lineage.
-- Cleaning: normalize name (upper, alnum-only), phone (digits-only), email,
-- tax_id. Latest row wins per natural key (dedupe by _loaded_at).
-- Entity RESOLUTION is deferred to Gold; Silver is one row per source customer.
-- =============================================================================
USE WAREHOUSE RECON_TRANSFORM_WH;

CREATE OR REPLACE TABLE silver.customers AS
WITH unioned AS (
    SELECT 'SALESFORCE'   AS source_system, account_id AS source_customer_id,
           account_name   AS customer_name, NULL       AS tax_id,
           billing_city, billing_postal_code, billing_country,
           phone, NULL      AS email, segment, account_status AS customer_status,
           TRY_TO_TIMESTAMP_NTZ(last_modified_date) AS source_extracted_at, _loaded_at
    FROM bronze.sf_accounts
    UNION ALL
    SELECT 'DYNAMICS_AX',  customer_id, customer_name, tax_id,
           city, postal_code, country, phone, email, NULL, status,
           NULL, _loaded_at
    FROM bronze.ax_customers
    UNION ALL
    SELECT 'POWERBILL',    customer_code, customer_name, NULL,
           address_city, postal_code, country, phone, email, NULL, account_status,
           NULL, _loaded_at
    FROM bronze.pb_customers
),
cleaned AS (
    SELECT
        source_system,
        source_customer_id,
        UPPER(TRIM(customer_name)) AS customer_name,
        REGEXP_REPLACE(UPPER(TRIM(customer_name)), '[^A-Z0-9]', '') AS customer_name_normalized,
        NULLIF(UPPER(REGEXP_REPLACE(TRIM(tax_id), '[^A-Z0-9]', '')), '') AS tax_id,
        LOWER(TRIM(email)) AS email,
        phone,
        NULLIF(REGEXP_REPLACE(phone, '[^0-9]', ''), '') AS phone_normalized,
        TRIM(billing_city)            AS billing_city,
        TRIM(billing_postal_code)      AS billing_postal_code,
        UPPER(TRIM(billing_country))   AS billing_country,
        TRIM(segment)                  AS segment,
        UPPER(TRIM(customer_status))   AS customer_status,
        source_extracted_at,
        _loaded_at                     AS etl_loaded_at
    FROM unioned
)
SELECT * FROM cleaned
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY source_system, source_customer_id
    ORDER BY etl_loaded_at DESC
) = 1;
