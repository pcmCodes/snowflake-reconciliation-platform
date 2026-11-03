-- =============================================================================
-- Gold 04: fact_invoice + fact_work_order.
--
-- fact_invoice reconciles ACTUAL billed total (PowerBill) against EXPECTED
-- revenue for the customer-month, sourced from either an active contract
-- (annual_value / 12) or completed work orders in that month. The variance
-- feeds the BILLING_MISMATCH exception in the leakage engine.
-- Tolerance for "mismatch" is parameterised via $tolerance.
-- =============================================================================
USE WAREHOUSE RECON_TRANSFORM_WH;

SET tolerance = 1.00;

-- fact_invoice --------------------------------------------------------------
CREATE OR REPLACE TABLE gold.fact_invoice AS
WITH inv AS (
    SELECT i.invoice_id, i.total_amount, i.invoice_date, i.invoice_status, i.billing_period,
           b.customer_bk,
           DATE_TRUNC('month', i.invoice_date) AS inv_month
    FROM silver.invoices i
    JOIN gold.bridge_customer_sources b
      ON b.source_system = 'POWERBILL' AND b.source_customer_id = i.source_customer_id
),
-- Expected from active contracts in the invoice month (annual_value / 12) --
contract_expected AS (
    SELECT inv.customer_bk, inv.inv_month,
           SUM(c.annual_value / 12.0) AS expected_contract
    FROM inv
    JOIN gold.bridge_customer_sources bc ON bc.source_system = 'DYNAMICS_AX' AND bc.customer_bk = inv.customer_bk
    JOIN silver.contracts c ON c.source_customer_id = bc.source_customer_id
    WHERE c.start_date <= LAST_DAY(inv.inv_month)
      AND c.end_date >= inv.inv_month
      AND c.status = 'ACTIVE'
    GROUP BY inv.customer_bk, inv.inv_month
),
-- Expected from completed work orders in the invoice month (fallback) -----
wo_expected AS (
    SELECT inv.customer_bk, inv.inv_month,
           SUM(w.amount) AS expected_wo
    FROM inv
    JOIN gold.bridge_customer_sources bw ON bw.source_system = 'DYNAMICS_AX' AND bw.customer_bk = inv.customer_bk
    JOIN silver.work_orders w ON w.source_customer_id = bw.source_customer_id
    WHERE DATE_TRUNC('month', w.completed_date) = inv.inv_month
    GROUP BY inv.customer_bk, inv.inv_month
),
-- Pick one active contract bk for linkage (nullable) ---------------------
contract_link AS (
    SELECT inv.customer_bk, inv.inv_month, MAX(c.contract_id) AS contract_bk
    FROM inv
    JOIN gold.bridge_customer_sources bc ON bc.source_system = 'DYNAMICS_AX' AND bc.customer_bk = inv.customer_bk
    JOIN silver.contracts c ON c.source_customer_id = bc.source_customer_id
    WHERE c.start_date <= LAST_DAY(inv.inv_month) AND c.end_date >= inv.inv_month
    GROUP BY inv.customer_bk, inv.inv_month
)
SELECT
    ROW_NUMBER() OVER (ORDER BY inv.invoice_id)             AS invoice_sk,
    inv.invoice_id                                            AS invoice_bk,
    inv.customer_bk,
    cl.contract_bk,
    inv.invoice_date,
    TO_NUMBER(TO_CHAR(inv.invoice_date, 'YYYYMMDD'))         AS invoice_date_key,
    inv.total_amount                                          AS total_amount,
    COALESCE(ce.expected_contract, we.expected_wo, 0)         AS expected_amount,
    inv.total_amount - COALESCE(ce.expected_contract, we.expected_wo, 0) AS variance_amount,
    IFF(ABS(inv.total_amount - COALESCE(ce.expected_contract, we.expected_wo, 0)) > $tolerance, TRUE, FALSE) AS variance_flag,
    inv.invoice_status,
    inv.billing_period,
    'POWERBILL'                                               AS source_system,
    CURRENT_TIMESTAMP()                                        AS etl_loaded_at
FROM inv
LEFT JOIN contract_expected ce ON ce.customer_bk = inv.customer_bk AND ce.inv_month = inv.inv_month
LEFT JOIN wo_expected       we ON we.customer_bk = inv.customer_bk AND we.inv_month = inv.inv_month
LEFT JOIN contract_link     cl ON cl.customer_bk = inv.customer_bk AND cl.inv_month = inv.inv_month;

-- fact_work_order -----------------------------------------------------------
CREATE OR REPLACE TABLE gold.fact_work_order AS
SELECT
    ROW_NUMBER() OVER (ORDER BY w.work_order_id) AS work_order_sk,
    w.work_order_id                              AS work_order_bk,
    b.customer_bk,
    a.asset_bk,
    w.created_date                               AS work_order_date,
    w.completed_date,
    w.quantity,
    w.amount,
    w.status,
    'DYNAMICS_AX'                                AS source_system,
    CURRENT_TIMESTAMP()                           AS etl_loaded_at
FROM silver.work_orders w
JOIN gold.bridge_customer_sources b
  ON b.source_system = 'DYNAMICS_AX' AND b.source_customer_id = w.source_customer_id
LEFT JOIN gold.dim_asset a ON a.asset_bk = w.item_id;
