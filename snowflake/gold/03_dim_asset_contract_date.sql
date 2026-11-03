-- =============================================================================
-- Gold 03: dim_asset (SCD1) + dim_contract (SCD2) + dim_date (calendar).
-- =============================================================================
USE WAREHOUSE RECON_TRANSFORM_WH;

-- dim_asset (current snapshot, SCD1) ---------------------------------------
CREATE OR REPLACE TABLE gold.dim_asset AS
SELECT ROW_NUMBER() OVER (ORDER BY item_id) AS asset_sk,
       item_id    AS asset_bk,
       item_name, category, unit_price
FROM silver.assets;

-- dim_contract (SCD2, persistent) -----------------------------------------
CREATE TABLE IF NOT EXISTS gold.dim_contract (
    contract_sk   NUMBER IDENTITY(1,1),
    contract_bk   STRING   NOT NULL,
    customer_bk   STRING,
    contract_name STRING,
    start_date    DATE,
    end_date      DATE,
    annual_value  NUMBER(18,2),
    status        STRING,
    effective_from TIMESTAMP_NTZ NOT NULL,
    effective_to   TIMESTAMP_NTZ,
    is_current     BOOLEAN  NOT NULL DEFAULT TRUE,
    record_hash    STRING   NOT NULL,
    etl_loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE gold.dim_contract_desired AS
SELECT c.contract_id AS contract_bk,
       b.customer_bk,
       c.contract_name, c.start_date, c.end_date, c.annual_value, c.status,
       MD5(
         COALESCE(c.contract_name,'') || '|' ||
         COALESCE(c.annual_value::STRING,'') || '|' ||
         COALESCE(c.status,'') || '|' ||
         COALESCE(c.end_date::STRING,'')
       ) AS record_hash
FROM silver.contracts c
JOIN gold.bridge_customer_sources b
  ON b.source_system = 'DYNAMICS_AX' AND b.source_customer_id = c.source_customer_id;

MERGE INTO gold.dim_contract AS t
USING gold.dim_contract_desired AS s
ON t.contract_bk = s.contract_bk AND t.is_current = TRUE
WHEN MATCHED AND t.record_hash <> s.record_hash THEN
    UPDATE SET t.effective_to = CURRENT_TIMESTAMP(), t.is_current = FALSE;

INSERT INTO gold.dim_contract (
    contract_bk, customer_bk, contract_name, start_date, end_date, annual_value,
    status, effective_from, effective_to, is_current, record_hash
)
SELECT contract_bk, customer_bk, contract_name, start_date, end_date, annual_value,
       status, CURRENT_TIMESTAMP(), NULL, TRUE, record_hash
FROM gold.dim_contract_desired s
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_contract t WHERE t.contract_bk = s.contract_bk AND t.is_current = TRUE);

-- dim_date (calendar 2023-01-01 .. 2028-12-31) ----------------------------
CREATE OR REPLACE TABLE gold.dim_date AS
SELECT
    d.full_date,
    TO_NUMBER(TO_CHAR(d.full_date, 'YYYYMMDD'))         AS date_key,
    DAY(d.full_date)                                     AS day_of_month,
    MONTH(d.full_date)                                   AS month_number,
    MONTHNAME(d.full_date)                               AS month_name,
    QUARTER(d.full_date)                                 AS quarter_number,
    YEAR(d.full_date)                                    AS year_number,
    IFF(DAYOFWEEK(d.full_date) IN (0, 6), TRUE, FALSE)    AS is_weekend
FROM (
    SELECT DATEADD('day', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2023-01-01'::DATE) AS full_date
    FROM TABLE(GENERATOR(ROWCOUNT => 2192))
);
