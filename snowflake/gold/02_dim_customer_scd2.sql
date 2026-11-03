-- =============================================================================
-- Gold 02: golden customer keys + bridge + dim_customer (SCD Type 2).
--
-- - golden_customer_keys: stable CUST-##### per cluster_key
-- - bridge_customer_sources: golden customer <-> each source ID (audit trail of
--   HOW each was matched: method + score)
-- - dim_customer: SCD2 via MERGE. Persistent (CREATE TABLE IF NOT EXISTS) so
--   history accumulates across runs; changed tracked-attributes close the
--   current version (effective_to, is_current=false) and insert a new version.
-- =============================================================================
USE WAREHOUSE RECON_TRANSFORM_WH;

-- 1) Stable golden business key per cluster -------------------------------
CREATE OR REPLACE TABLE gold.golden_customer_keys AS
SELECT cluster_key,
       'CUST-' || LPAD(ROW_NUMBER() OVER (ORDER BY cluster_key)::STRING, 5, '0') AS customer_bk
FROM (SELECT DISTINCT cluster_key FROM gold.customer_clusters);

-- 2) Bridge: golden customer <-> source IDs (audit trail of resolution) ---
CREATE OR REPLACE TABLE gold.bridge_customer_sources AS
SELECT g.customer_bk,
       c.source_system,
       c.source_customer_id,
       c.match_method,
       c.match_score,
       CURRENT_TIMESTAMP() AS etl_loaded_at
FROM gold.customer_clusters c
JOIN gold.golden_customer_keys g ON g.cluster_key = c.cluster_key;

-- 3) dim_customer target (persistent, SCD2) -------------------------------
CREATE TABLE IF NOT EXISTS gold.dim_customer (
    customer_sk          NUMBER IDENTITY(1,1),
    customer_bk          STRING   NOT NULL,
    customer_name        STRING,
    tax_id               STRING,
    segment              STRING,
    customer_status      STRING,
    billing_city         STRING,
    billing_postal_code  STRING,
    billing_country      STRING,
    effective_from       TIMESTAMP_NTZ NOT NULL,
    effective_to         TIMESTAMP_NTZ,
    is_current           BOOLEAN  NOT NULL DEFAULT TRUE,
    record_hash          STRING   NOT NULL,
    etl_loaded_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 4) Desired current state per golden customer ----------------------------
-- Pick highest-priority non-null attribute per customer (AX > SF > PB),
-- preferring the system most authoritative for each field.
CREATE OR REPLACE TABLE gold.dim_customer_desired AS
WITH joined AS (
    SELECT b.customer_bk,
           c.customer_name, c.tax_id, c.segment, c.customer_status,
           c.billing_city, c.billing_postal_code, c.billing_country,
           CASE b.source_system WHEN 'DYNAMICS_AX' THEN 1 WHEN 'SALESFORCE' THEN 2 ELSE 3 END AS prio
    FROM gold.bridge_customer_sources b
    JOIN silver.customers c
      ON c.source_system = b.source_system AND c.source_customer_id = b.source_customer_id
)
SELECT customer_bk,
       FIRST_VALUE(customer_name)        IGNORE NULLS OVER w AS customer_name,
       FIRST_VALUE(tax_id)                IGNORE NULLS OVER w AS tax_id,
       FIRST_VALUE(segment)               IGNORE NULLS OVER w AS segment,
       FIRST_VALUE(customer_status)      IGNORE NULLS OVER w AS customer_status,
       FIRST_VALUE(billing_city)          IGNORE NULLS OVER w AS billing_city,
       FIRST_VALUE(billing_postal_code)   IGNORE NULLS OVER w AS billing_postal_code,
       FIRST_VALUE(billing_country)       IGNORE NULLS OVER w AS billing_country,
       MD5(
         COALESCE(FIRST_VALUE(customer_name)      IGNORE NULLS OVER w,'') || '|' ||
         COALESCE(FIRST_VALUE(tax_id)             IGNORE NULLS OVER w,'') || '|' ||
         COALESCE(FIRST_VALUE(segment)            IGNORE NULLS OVER w,'') || '|' ||
         COALESCE(FIRST_VALUE(customer_status)    IGNORE NULLS OVER w,'') || '|' ||
         COALESCE(FIRST_VALUE(billing_city)       IGNORE NULLS OVER w,'') || '|' ||
         COALESCE(FIRST_VALUE(billing_postal_code) IGNORE NULLS OVER w,'') || '|' ||
         COALESCE(FIRST_VALUE(billing_country)    IGNORE NULLS OVER w,'')
       ) AS record_hash
FROM joined
WINDOW w AS (PARTITION BY customer_bk ORDER BY prio)
QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_bk ORDER BY prio) = 1;

-- 5) SCD2: close changed current versions ---------------------------------
MERGE INTO gold.dim_customer AS t
USING gold.dim_customer_desired AS s
ON t.customer_bk = s.customer_bk AND t.is_current = TRUE
WHEN MATCHED AND t.record_hash <> s.record_hash THEN
    UPDATE SET t.effective_to = CURRENT_TIMESTAMP(), t.is_current = FALSE;

-- 6) SCD2: insert new versions (brand-new customers + just-closed) --------
INSERT INTO gold.dim_customer (
    customer_bk, customer_name, tax_id, segment, customer_status,
    billing_city, billing_postal_code, billing_country,
    effective_from, effective_to, is_current, record_hash
)
SELECT customer_bk, customer_name, tax_id, segment, customer_status,
       billing_city, billing_postal_code, billing_country,
       CURRENT_TIMESTAMP(), NULL, TRUE, record_hash
FROM gold.dim_customer_desired s
WHERE NOT EXISTS (
    SELECT 1 FROM gold.dim_customer t
    WHERE t.customer_bk = s.customer_bk AND t.is_current = TRUE
);
