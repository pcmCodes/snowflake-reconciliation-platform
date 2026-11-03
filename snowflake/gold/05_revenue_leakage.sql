-- =============================================================================
-- Gold 05: REVENUE LEAKAGE ENGINE.
-- Emits one row per detected exception with full traceability back to source
-- (source_system + source_ref_id). Each exception is graded by severity and
-- starts OPEN (production would MERGE to preserve REVIEWED/RESOLVED state).
--
-- Exception types:
--   WON_NOT_BILLED         - Salesforce opp Closed Won, no invoice within 90d
--   CONTRACT_NO_INVOICE   - Active AX contract, no invoice in current month
--   WORK_ORDER_NOT_INVOICED- Completed AX work order, no invoice that month
--   BILLING_MISMATCH       - PowerBill invoice != expected (contract / WO)
--   ORPHAN_BILLING         - Billed customer not resolvable to SF / AX
--   OVERDUE_UNCOLLECTED    - Invoice unpaid & > 30 days past due
-- =============================================================================
USE WAREHOUSE RECON_TRANSFORM_WH;

CREATE OR REPLACE TABLE gold.revenue_leakage_exceptions AS

-- 1) WON_NOT_BILLED --------------------------------------------------------
SELECT 'WON_NOT_BILLED'      AS exception_type, b.customer_bk, 'SALESFORCE' AS source_system,
       o.opportunity_id      AS source_ref_id,
       o.amount              AS expected_amount, 0 AS actual_amount, o.amount AS variance_amount,
       o.close_date          AS exception_date,
       IFF(o.amount > 50000, 'HIGH', 'MEDIUM') AS severity, 'OPEN' AS exception_status,
       'Opportunity closed won on ' || o.close_date || ' but no PowerBill invoice in the following 90 days.' AS description,
       CURRENT_TIMESTAMP()   AS detected_at
FROM silver.opportunities o
JOIN gold.bridge_customer_sources b
  ON b.source_system = 'SALESFORCE' AND b.source_customer_id = o.source_account_id
WHERE UPPER(o.stage) = 'CLOSED WON'
  AND NOT EXISTS (
      SELECT 1 FROM gold.fact_invoice fi
      WHERE fi.customer_bk = b.customer_bk
        AND fi.invoice_date >= o.close_date
        AND fi.invoice_date <= DATEADD('day', 90, o.close_date)
  )

UNION ALL

-- 2) CONTRACT_NO_INVOICE ---------------------------------------------------
SELECT 'CONTRACT_NO_INVOICE' AS exception_type, b.customer_bk, 'DYNAMICS_AX' AS source_system,
       c.contract_id        AS source_ref_id,
       c.annual_value / 12.0 AS expected_amount, 0 AS actual_amount, c.annual_value / 12.0 AS variance_amount,
       CURRENT_DATE()       AS exception_date,
       IFF(c.annual_value > 100000, 'HIGH', 'MEDIUM') AS severity, 'OPEN' AS exception_status,
       'Active contract has no PowerBill invoice in the current period.' AS description,
       CURRENT_TIMESTAMP()  AS detected_at
FROM silver.contracts c
JOIN gold.bridge_customer_sources b
  ON b.source_system = 'DYNAMICS_AX' AND b.source_customer_id = c.source_customer_id
WHERE UPPER(c.status) = 'ACTIVE'
  AND CURRENT_DATE() BETWEEN c.start_date AND c.end_date
  AND NOT EXISTS (
      SELECT 1 FROM gold.fact_invoice fi
      WHERE fi.customer_bk = b.customer_bk
        AND DATE_TRUNC('month', fi.invoice_date) = DATE_TRUNC('month', CURRENT_DATE())
  )

UNION ALL

-- 3) WORK_ORDER_NOT_INVOICED -----------------------------------------------
SELECT 'WORK_ORDER_NOT_INVOICED' AS exception_type, b.customer_bk, 'DYNAMICS_AX' AS source_system,
       w.work_order_id         AS source_ref_id,
       w.amount                AS expected_amount, 0 AS actual_amount, w.amount AS variance_amount,
       w.completed_date        AS exception_date,
       IFF(w.amount > 25000, 'HIGH', 'MEDIUM') AS severity, 'OPEN' AS exception_status,
       'Completed work order has no matching PowerBill invoice in its month.' AS description,
       CURRENT_TIMESTAMP()     AS detected_at
FROM silver.work_orders w
JOIN gold.bridge_customer_sources b
  ON b.source_system = 'DYNAMICS_AX' AND b.source_customer_id = w.source_customer_id
WHERE UPPER(w.status) = 'COMPLETED' AND w.completed_date IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM gold.fact_invoice fi
      WHERE fi.customer_bk = b.customer_bk
        AND DATE_TRUNC('month', fi.invoice_date) = DATE_TRUNC('month', w.completed_date)
  )

UNION ALL

-- 4) BILLING_MISMATCH ------------------------------------------------------
SELECT 'BILLING_MISMATCH'   AS exception_type, fi.customer_bk, 'POWERBILL' AS source_system,
       fi.invoice_bk        AS source_ref_id,
       fi.expected_amount   AS expected_amount, fi.total_amount AS actual_amount, fi.variance_amount AS variance_amount,
       fi.invoice_date      AS exception_date,
       IFF(ABS(fi.variance_amount) > 10000, 'HIGH', 'MEDIUM') AS severity, 'OPEN' AS exception_status,
       'Invoice total differs from expected (contract / work-order) by ' || fi.variance_amount AS description,
       CURRENT_TIMESTAMP()  AS detected_at
FROM gold.fact_invoice fi
WHERE fi.variance_flag = TRUE

UNION ALL

-- 5) ORPHAN_BILLING (billed customer not in SF / AX) -----------------------
SELECT 'ORPHAN_BILLING'      AS exception_type, orphan.customer_bk, 'POWERBILL' AS source_system,
       orphan.source_customer_id AS source_ref_id,
       orphan.total_billed   AS expected_amount, 0 AS actual_amount, orphan.total_billed AS variance_amount,
       CURRENT_DATE()        AS exception_date,
       'HIGH'                AS severity, 'OPEN' AS exception_status,
       'Billed customer could not be resolved to Salesforce or Dynamics AX.' AS description,
       CURRENT_TIMESTAMP()   AS detected_at
FROM (
    SELECT b.customer_bk, MIN(b.source_customer_id) AS source_customer_id,
           SUM(i.total_amount) AS total_billed
    FROM gold.bridge_customer_sources b
    JOIN silver.invoices i
      ON i.source_customer_id = b.source_customer_id AND b.source_system = 'POWERBILL'
    WHERE b.customer_bk IN (
        SELECT customer_bk FROM gold.bridge_customer_sources
        GROUP BY customer_bk
        HAVING COUNT(DISTINCT source_system) = 1 AND MAX(source_system) = 'POWERBILL'
    )
    GROUP BY b.customer_bk
) orphan

UNION ALL

-- 6) OVERDUE_UNCOLLECTED ---------------------------------------------------
SELECT 'OVERDUE_UNCOLLECTED' AS exception_type, fi.customer_bk, 'POWERBILL' AS source_system,
       fi.invoice_bk        AS source_ref_id,
       fi.total_amount      AS expected_amount, 0 AS actual_amount, fi.total_amount AS variance_amount,
       si.due_date          AS exception_date,
       IFF(DATEDIFF('day', si.due_date, CURRENT_DATE()) > 60, 'HIGH', 'MEDIUM') AS severity,
       'OPEN'               AS exception_status,
       'Invoice unpaid and overdue by ' || DATEDIFF('day', si.due_date, CURRENT_DATE()) || ' days.' AS description,
       CURRENT_TIMESTAMP()  AS detected_at
FROM gold.fact_invoice fi
JOIN silver.invoices si ON si.invoice_id = fi.invoice_bk
WHERE fi.invoice_status <> 'PAID'
  AND si.due_date < DATEADD('day', -30, CURRENT_DATE());
