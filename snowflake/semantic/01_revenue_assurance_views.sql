-- =============================================================================
-- Semantic layer: Revenue Assurance views over Gold (for dashboards / QA).
-- =============================================================================
USE WAREHOUSE RECON_REPORTING_WH;
USE SCHEMA RECON_PLATFORM.SEMANTIC;

-- Summary: counts + exposure per exception type ----------------------------
CREATE OR REPLACE VIEW v_revenue_assurance_summary AS
SELECT
    exception_type,
    severity,
    COUNT(*)                                          AS exception_count,
    SUM(expected_amount)                              AS expected_exposure,
    SUM(actual_amount)                                AS actual_amount,
    SUM(variance_amount)                              AS leakage_amount,
    SUM(IFF(exception_status = 'OPEN', 1, 0))         AS open_count
FROM gold.revenue_leakage_exceptions
GROUP BY exception_type, severity;

-- Leakage by category (one row per exception type) -------------------------
CREATE OR REPLACE VIEW v_leakage_by_category AS
SELECT
    exception_type,
    COUNT(*)                       AS exception_count,
    SUM(variance_amount)           AS total_leakage,
    SUM(IFF(severity = 'HIGH', 1, 0)) AS high_severity_count
FROM gold.revenue_leakage_exceptions
GROUP BY exception_type
ORDER BY total_leakage DESC NULLS LAST;

-- Customer 360: golden customer with match quality + billing + leakage -----
CREATE OR REPLACE VIEW v_customer_360 AS
SELECT
    d.customer_bk,
    d.customer_name,
    d.segment,
    d.customer_status,
    bs.source_count,
    bs.match_methods,
    COALESCE(i.total_billed, 0)        AS total_billed,
    COALESCE(e.exception_count, 0)    AS open_exceptions,
    COALESCE(e.leakage_amount, 0)     AS leakage_amount
FROM gold.dim_customer d
LEFT JOIN (
    SELECT customer_bk,
           COUNT(DISTINCT source_system)                       AS source_count,
           LISTAGG(DISTINCT match_method, ', ') WITHIN GROUP (ORDER BY match_method) AS match_methods
    FROM gold.bridge_customer_sources GROUP BY customer_bk
) bs ON bs.customer_bk = d.customer_bk
LEFT JOIN (
    SELECT customer_bk, SUM(total_amount) AS total_billed
    FROM gold.fact_invoice GROUP BY customer_bk
) i  ON i.customer_bk = d.customer_bk
LEFT JOIN (
    SELECT customer_bk, COUNT(*) AS exception_count, SUM(variance_amount) AS leakage_amount
    FROM gold.revenue_leakage_exceptions
    WHERE exception_status = 'OPEN'
    GROUP BY customer_bk
) e  ON e.customer_bk = d.customer_bk
WHERE d.is_current = TRUE;

-- Invoice vs expected (reconciliation detail) -------------------------------
CREATE OR REPLACE VIEW v_invoice_vs_expected AS
SELECT
    fi.invoice_bk,
    fi.customer_bk,
    d.customer_name,
    fi.invoice_date,
    fi.billing_period,
    fi.total_amount,
    fi.expected_amount,
    fi.variance_amount,
    fi.variance_flag,
    fi.invoice_status
FROM gold.fact_invoice fi
LEFT JOIN gold.dim_customer d ON d.customer_bk = fi.customer_bk AND d.is_current = TRUE;
