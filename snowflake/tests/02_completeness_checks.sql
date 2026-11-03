-- =============================================================================
-- Tests 02: completeness & data-quality checks. Same row shape as tests 01.
-- =============================================================================
USE WAREHOUSE RECON_TRANSFORM_WH;
USE SCHEMA RECON_PLATFORM;

-- No NULL business keys in the bridge
SELECT 'no_null_bk_bridge' AS check_name,
       0 AS expected,
       (SELECT COUNT(*) FROM gold.bridge_customer_sources WHERE customer_bk IS NULL) AS actual,
       IFF((SELECT COUNT(*) FROM gold.bridge_customer_sources WHERE customer_bk IS NULL) = 0, 'PASS','FAIL') AS status,
       'No NULL customer_bk in bridge_customer_sources' AS detail;

-- Each source customer maps to exactly one golden customer
SELECT 'unique_source_in_bridge' AS check_name,
       0 AS expected,
       (SELECT COUNT(*) FROM (
           SELECT source_system, source_customer_id, COUNT(*) AS c
           FROM gold.bridge_customer_sources GROUP BY source_system, source_customer_id HAVING c > 1
       )) AS actual,
       IFF((SELECT COUNT(*) FROM (
            SELECT source_system, source_customer_id FROM gold.bridge_customer_sources
            GROUP BY source_system, source_customer_id HAVING COUNT(*) > 1
       )) = 0, 'PASS','FAIL') AS status,
       'Each source customer maps to one golden customer only' AS detail;

-- Contract date sanity: end_date >= start_date
SELECT 'contract_date_sanity' AS check_name,
       0 AS expected,
       (SELECT COUNT(*) FROM silver.contracts WHERE end_date < start_date) AS actual,
       IFF((SELECT COUNT(*) FROM silver.contracts WHERE end_date < start_date) = 0, 'PASS','FAIL') AS status,
       'Contract end_date must be >= start_date' AS detail;

-- No NULL business keys in facts/dims
SELECT 'no_null_business_keys' AS check_name,
       0 AS expected,
       (SELECT COUNT(*) FROM gold.fact_invoice WHERE invoice_bk IS NULL)
         + (SELECT COUNT(*) FROM gold.fact_work_order WHERE work_order_bk IS NULL)
         + (SELECT COUNT(*) FROM gold.dim_customer WHERE customer_bk IS NULL) AS actual,
       IFF(((SELECT COUNT(*) FROM gold.fact_invoice WHERE invoice_bk IS NULL)
            + (SELECT COUNT(*) FROM gold.fact_work_order WHERE work_order_bk IS NULL)
            + (SELECT COUNT(*) FROM gold.dim_customer WHERE customer_bk IS NULL)) = 0, 'PASS','FAIL') AS status,
       'No NULL business keys in fact_invoice, fact_work_order, dim_customer' AS detail;

-- Non-negative amounts in silver
SELECT 'non_negative_amounts' AS check_name,
       0 AS expected,
       (SELECT COUNT(*) FROM silver.invoices WHERE total_amount < 0)
         + (SELECT COUNT(*) FROM silver.work_orders WHERE amount < 0) AS actual,
       IFF(((SELECT COUNT(*) FROM silver.invoices WHERE total_amount < 0)
            + (SELECT COUNT(*) FROM silver.work_orders WHERE amount < 0)) = 0, 'PASS','FAIL') AS status,
       'Invoice and work-order amounts must be non-negative' AS detail;
