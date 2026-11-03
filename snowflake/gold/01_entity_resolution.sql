-- =============================================================================
-- Gold 01: ENTITY RESOLUTION across Salesforce / Dynamics AX / PowerBill.
--
-- Resolves the same real-world customer appearing in 3 systems (different IDs,
-- slightly different names) into ONE golden cluster key.
--
-- Strategy (deterministic first, then fuzzy):
--   1. DETERMINISTIC by tax_id  (when present and equal across systems)
--   2. DETERMINISTIC by (normalized_name + postal_code) (exact)
--   3. FUZZY by JAROWINKLER_SIMILARITY(normalized_name) >= 90 (same country,
--      across systems) - catches abbreviations / typos not removed by
--      normalization.
--
-- cluster_key = MIN reachable node id over the undirected match graph (self +
-- partners). For the generated data each customer's records form a match
-- clique, so 1-hop MIN is exact. Production hardening: full connected-
-- components via Snowpark / recursive CTE for arbitrary chains.
--
-- Output: gold.customer_clusters (one row per source customer, with cluster_key,
-- match_method, match_score). dim_customer + bridge are built in 02.
-- =============================================================================
USE WAREHOUSE RECON_TRANSFORM_WH;

CREATE OR REPLACE TABLE gold.customer_clusters AS
WITH src AS (
    SELECT source_system, source_customer_id, customer_name, customer_name_normalized,
           tax_id, billing_postal_code, billing_country
    FROM silver.customers
),
-- Deterministic pairs (a < b keeps each pair once) -------------------------
det_pairs AS (
    SELECT a.source_customer_id AS x, b.source_customer_id AS y
    FROM src a JOIN src b
      ON a.tax_id IS NOT NULL AND a.tax_id = b.tax_id
     AND a.source_customer_id < b.source_customer_id
    UNION
    SELECT a.source_customer_id, b.source_customer_id
    FROM src a JOIN src b
      ON a.customer_name_normalized = b.customer_name_normalized
     AND COALESCE(a.billing_postal_code,'') = COALESCE(b.billing_postal_code,'')
     AND a.source_customer_id < b.source_customer_id
),
-- Fuzzy pairs across systems (same country, Jaro-Winkler >= 90) ------------
fuzzy_pairs AS (
    SELECT a.source_customer_id AS x, b.source_customer_id AS y,
           JAROWINKLER_SIMILARITY(a.customer_name_normalized, b.customer_name_normalized) AS score
    FROM src a JOIN src b
      ON a.source_system <> b.source_system
     AND a.billing_country = b.billing_country
     AND a.source_customer_id < b.source_customer_id
     AND LENGTH(a.customer_name_normalized) > 0
     AND LENGTH(b.customer_name_normalized) > 0
    WHERE JAROWINKLER_SIMILARITY(a.customer_name_normalized, b.customer_name_normalized) >= 90
),
all_pairs_raw AS (
    SELECT x, y, 'DETERMINISTIC' AS method, 100 AS score FROM det_pairs
    UNION ALL
    SELECT x, y, 'FUZZY' AS method, score FROM fuzzy_pairs
),
-- Keep the strongest method per pair (deterministic beats fuzzy) ----------
all_pairs AS (
    SELECT x, y, method, score
    FROM all_pairs_raw
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY x, y
        ORDER BY CASE WHEN method = 'DETERMINISTIC' THEN 0 ELSE 1 END
    ) = 1
),
-- Undirected adjacency incl. self -----------------------------------------
adj AS (
    SELECT source_customer_id AS x, source_customer_id AS y, 'SELF'      AS method, 100 AS score FROM src
    UNION ALL
    SELECT x, y, method, score FROM all_pairs
    UNION ALL
    SELECT y, x, method, score FROM all_pairs
),
-- cluster_key = min reachable node id (self + 1-hop partners) --------------
cluster_key AS (
    SELECT s.source_system, s.source_customer_id, MIN(a.y) AS cluster_key
    FROM src s
    LEFT JOIN adj a ON a.x = s.source_customer_id
    GROUP BY s.source_system, s.source_customer_id
),
-- Best match method + score per record (deterministic > fuzzy > unresolved)
method AS (
    SELECT s.source_system, s.source_customer_id,
        IFF(COUNT_IF(a.method = 'DETERMINISTIC') > 0, 'DETERMINISTIC',
            IFF(COUNT_IF(a.method = 'FUZZY') > 0, 'FUZZY', 'UNRESOLVED')) AS match_method,
        MAX(a.score) AS match_score
    FROM src s
    LEFT JOIN adj a ON a.x = s.source_customer_id AND a.method <> 'SELF'
    GROUP BY s.source_system, s.source_customer_id
)
SELECT c.source_system, c.source_customer_id, c.cluster_key,
       m.match_method, COALESCE(m.match_score, 0) AS match_score
FROM cluster_key c
JOIN method m
  ON m.source_system = c.source_system AND m.source_customer_id = c.source_customer_id;
