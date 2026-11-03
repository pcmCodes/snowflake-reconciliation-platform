-- =============================================================================
-- Tests 01: row-count validation & source-to-target reconciliation.
-- Each statement returns one row: (check_name, expected, actual, status, detail).
-- status = PASS when actual = expected. The orchestrator fails the run if any
-- row returns status = FAIL.
-- =============================================================================
USE WAREHOUSE RECON_TRANSFORM_WH;
USE SCHEMA RECON_PLATFORM;

-- Every PowerBill invoice resolves into fact_invoice (orphan customers still
-- resolve via the PowerBill bridge; they are separately flagged as ORPHAN_BILLING)
SELECT 'invoice_reconciliation' AS check_name,
       (SELECT COUNT(*) FROM silver.invoices) AS expected,
       (SELECT COUNT(*) FROM gold.fact_invoice) AS actual,
       IFF((SELECT COUNT(*) FROM silver.invoices) = (SELECT COUNT(*) FROM gold.fact_invoice),
           'PASS','FAIL') AS status,
       'Every Silver invoice must land in fact_invoice' AS detail;

-- Every current golden customer has at least one source in the bridge
SELECT 'customer_bridge_coverage' AS check_name,
       (SELECT COUNT(*) FROM gold.dim_customer WHERE is_current) AS expected,
       (SELECT COUNT(DISTINCT customer_bk) FROM gold.bridge_customer_sources) AS actual,
       IFF((SELECT COUNT(*) FROM gold.dim_customer WHERE is_current)
            = (SELECT COUNT(DISTINCT customer_bk) FROM gold.bridge_customer_sources),
           'PASS','FAIL') AS status,
       'Every golden customer must have >=1 mapped source' AS detail;

-- Referential integrity: fact_invoice.customer_bk -> dim_customer
SELECT 'fk_fact_invoice_customer' AS check_name,
       0 AS expected,
       (SELECT COUNT(*) FROM gold.fact_invoice fi
         LEFT JOIN gold.dim_customer d ON d.customer_bk = fi.customer_bk AND d.is_current
         WHERE d.customer_bk IS NULL) AS actual,
       IFF((SELECT COUNT(*) FROM gold.fact_invoice fi
             LEFT JOIN gold.dim_customer d ON d.customer_bk = fi.customer_bk AND d.is_current
             WHERE d.customer_bk IS NULL) = 0, 'PASS','FAIL') AS status,
       'No orphan customer_bk in fact_invoice' AS detail;

-- Referential integrity: fact_work_order.customer_bk -> dim_customer
SELECT 'fk_fact_work_order_customer' AS check_name,
       0 AS expected,
       (SELECT COUNT(*) FROM gold.fact_work_order fw
         LEFT JOIN gold.dim_customer d ON d.customer_bk = fw.customer_bk AND d.is_current
         WHERE d.customer_bk IS NULL) AS actual,
       IFF((SELECT COUNT(*) FROM gold.fact_work_order fw
             LEFT JOIN gold.dim_customer d ON d.customer_bk = fw.customer_bk AND d.is_current
             WHERE d.customer_bk IS NULL) = 0, 'PASS','FAIL') AS status,
       'No orphan customer_bk in fact_work_order' AS detail;

-- Invoice header total == sum of invoice lines
SELECT 'invoice_line_total' AS check_name,
       0 AS expected,
       (SELECT COUNT(*) FROM (
           SELECT i.invoice_id, i.total_amount, SUM(l.line_amount) AS line_sum
           FROM silver.invoices i JOIN silver.invoice_lines l ON l.invoice_id = i.invoice_id
           GROUP BY i.invoice_id, i.total_amount
           HAVING ABS(i.total_amount - SUM(l.line_amount)) > 0.01
       )) AS actual,
       IFF((SELECT COUNT(*) FROM (
            SELECT i.invoice_id FROM silver.invoices i JOIN silver.invoice_lines l ON l.invoice_id = i.invoice_id
            GROUP BY i.invoice_id, i.total_amount
            HAVING ABS(i.total_amount - SUM(l.line_amount)) > 0.01
       )) = 0, 'PASS','FAIL') AS status,
       'Invoice header total must equal sum of its lines' AS detail;

-- Traceability: orphan exceptions reference real PowerBill customers
SELECT 'orphan_traceability' AS check_name,
       0 AS expected,
       (SELECT COUNT(*) FROM gold.revenue_leakage_exceptions e
         WHERE e.exception_type = 'ORPHAN_BILLING'
           AND NOT EXISTS (SELECT 1 FROM silver.customers c
                           WHERE c.source_system = 'POWERBILL' AND c.source_customer_id = e.source_ref_id)) AS actual,
       IFF((SELECT COUNT(*) FROM gold.revenue_leakage_exceptions e
             WHERE e.exception_type = 'ORPHAN_BILLING'
               AND NOT EXISTS (SELECT 1 FROM silver.customers c
                               WHERE c.source_system = 'POWERBILL' AND c.source_customer_id = e.source_ref_id)) = 0,
           'PASS','FAIL') AS status,
       'Every orphan exception must trace to a real PowerBill customer' AS detail;
