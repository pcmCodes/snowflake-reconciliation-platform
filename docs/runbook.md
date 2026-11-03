# Operations Runbook

## Pipeline execution

### Full run (end-to-end)
```bash
python data_generation/generate_all.py        # 1. Generate source CSVs
python snowflake/orchestration/run_pipeline.py # 2. Provision + load + transform + test
```

`run_pipeline.py` executes steps in order and stops on first failure:
1. Setup: warehouses, database/schemas, RBAC, resource monitors, stages & file format.
2. Bronze: `PUT` CSVs to stage, `COPY INTO` each bronze table.
3. Silver: rebuild conformed tables (idempotent `CREATE OR REPLACE`).
4. Gold: entity resolution → SCD2 dims → facts → leakage engine.
5. Semantic: create/replace dashboard views.
6. Masking: apply dynamic masking policies.
7. Tests: row-count validation + completeness checks → print report.

### Re-run a single layer
Each layer is independent and idempotent. To rebuild only Gold:
```sql
USE WAREHOUSE RECON_TRANSFORM_WH;
@"snowflake/gold/01_entity_resolution.sql";  -- run the file's statements
```
(The runner exposes per-stage entry points; see `run_pipeline.py --help`.)

## Failure handling & alerting

- **Resource monitor tripped** — warehouse suspends; CI/CD reports the run as failed. Increase the monitor cap or investigate the offending query via `SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY`.
- **COPY failure** — `run_pipeline.py` raises on a non-zero `COPY` result; offending file is logged. Re-run after fixing the source CSV. Bronze loads are append-safe because Bronze is rebuilt with `CREATE OR REPLACE` before `COPY`.
- **SCD2 hash collision** — expected when attributes genuinely changed; a new version row is inserted. Unexpected mass inserts indicate a silver normalization regression — check `silver.customers.record_hash`.

## Reconciliation checks (CI gate)

`run_pipeline.py` ends by executing `snowflake/tests/` and printing a pass/fail report. CI fails the build if any check returns `FAIL`. Checks include:
- Bronze row count == generated CSV row count.
- Every `fact_invoice.customer_bk` exists in `dim_customer`.
- No NULL `customer_bk` in `bridge_customer_sources`.
- Every `revenue_leakage_exceptions` row resolves to a `source_ref_id` that exists in its source table (traceability).

## Common operations

| Task | Command / location |
|---|---|
| Add a new source feed | New file in `snowflake/bronze/`, generator in `data_generation/generate_all.py` |
| Rotate Snowflake credentials | Update GitHub Actions secrets `SNOWFLAKE_*` |
| Re-provision infra via IaC | `cd terraform && terraform apply` |
| Inspect leakage exceptions | `SELECT * FROM gold.revenue_leakage_exceptions WHERE exception_status='OPEN'` |
| Audit who saw unmasked PII | `SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY` filtered to masked columns |

## Backups & time travel

Bronze is the immutable landing layer and the recovery point. Snowflake Time Travel (default 1 day, extendable via data retention) allows `UNDROP`/`SELECT ... AT(OFFSET => -n)` for point-in-time recovery of any layer.
