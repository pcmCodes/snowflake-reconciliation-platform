# RBAC Matrix

Role-based access control follows least-privilege and separation of duties (SOX/ITGC aligned). The `ACCOUNTADMIN`/`SECURITYADMIN` provisions functional roles; functional roles are granted to named users. No pipeline runs as `ACCOUNTADMIN`.

## Functional roles

| Role | Purpose | Granted on |
|---|---|---|
| `RECON_ADMIN` | Platform owner: provisioning + grants management | OWNERSHIP on all `RECON_PLATFORM` objects; `CREATE` schema |
| `RECON_ENGINEER` | Builds & runs pipelines (Bronze→Gold) | `USAGE` DB/schemas; `INSERT`/`UPDATE`/`CREATE TABLE` on BRONZE/SILVER/GOLD |
| `RECON_ANALYST` | Reads Gold + semantic for QA & dashboards | `SELECT` on GOLD + SEMANTIC only |
| `RECON_READER` | Dashboard consumers | `SELECT` on SEMANTIC only |

## Warehouse assignment

| Role | Default warehouse |
|---|---|
| `RECON_ENGINEER` | `RECON_TRANSFORM_WH` (load step switches to `RECON_LOAD_WH`) |
| `RECON_ANALYST` | `RECON_REPORTING_WH` |
| `RECON_READER` | `RECON_REPORTING_WH` |

## Permission matrix (RECON_PLATFORM database)

| Object | RECON_ADMIN | RECON_ENGINEER | RECON_ANALYST | RECON_READER |
|---|---|---|---|---|
| Database `RECON_PLATFORM` | OWNERSHIP + USAGE | USAGE | USAGE | USAGE |
| Schema `BRONZE` | OWNERSHIP | USAGE + ALL | — | — |
| Schema `SILVER` | OWNERSHIP | USAGE + ALL | — | — |
| Schema `GOLD` | OWNERSHIP | USAGE + ALL | USAGE + SELECT | — |
| Schema `SEMANTIC` | OWNERSHIP | USAGE + CREATE | USAGE + SELECT | USAGE + SELECT |
| Warehouses | OWNERSHIP | USAGE | USAGE | USAGE |

`ALL` here means `SELECT, INSERT, UPDATE, DELETE, CREATE TABLE, CREATE VIEW, CREATE STAGE` (see `snowflake/setup/03_roles_grants.sql` for the exact grants).

## Data masking

PII columns (`email`, `phone`, `tax_id`) carry dynamic masking policies. `RECON_ADMIN`/`RECON_ENGINEER` see clear values; `RECON_ANALYST` and `RECON_READER` see masked/redacted values. See `snowflake/masking/01_dynamic_masking.sql`.

## Environment separation

| Environment | Database | Engineer role |
|---|---|---|
| Dev | `RECON_PLATFORM_DEV` | `RECON_ENGINEER_DEV` |
| Staging | `RECON_PLATFORM_STAGING` | `RECON_ENGINEER_STAGING` |
| Prod | `RECON_PLATFORM` | `RECON_ENGINEER` |

Prod deploys are gated by a GitHub Environment with required reviewers; engineers cannot self-deploy to prod.
