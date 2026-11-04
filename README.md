# Snowflake Reconciliation Platform

A Snowflake-based reconciliation platform that integrates data from **Salesforce** (CRM), **Microsoft Dynamics AX** (ERP) and **PowerBill** (billing) to create a reconciled "golden thread" across business systems, surface billing mismatches, and prevent revenue leakage.

Built end-to-end with a **medallion architecture** (Bronze → Silver → Gold), **entity resolution** (deterministic + fuzzy), **SCD Type 2** dimensionals, **dynamic data masking**, **RBAC**, **resource monitors**, automated **reconciliation tests**, and **GitHub Actions CI/CD**.

> Fictional client: **BrightFibre Telecom**. All source data is **synthetically generated** by an included Python generator, so the whole platform is reproducible against a free Snowflake trial — no real systems required.

---

## Why this project exists

A portfolio piece demonstrating the skills as a Data Engineer / Snowflake practitioner will do: not a toy notebook, but a layered, governed, testable, deployable data platform with documentation an auditor could read.

### Skills demonstrated (mapped to a typical senior DE role)

| Capability | Where it lives |
|---|---|
| Snowflake ELT pipelines, multi-source integration | `snowflake/bronze/`, `snowflake/orchestration/` |
| Bronze / Silver / Gold medallion architecture | `snowflake/bronze`, `silver`, `gold` |
| Entity resolution — deterministic + fuzzy matching | `snowflake/gold/01_entity_resolution.sql` |
| SCD Type 2 dimensionals | `snowflake/gold/02_dim_customer_scd2.sql`, `03_dim_asset_contract_date.sql` |
| Revenue-leakage / billing-mismatch detection | `snowflake/gold/05_revenue_leakage.sql` |
| Semantic layer for Revenue Assurance dashboards | `snowflake/semantic/` |
| Warehouse sizing, auto-suspend, resource monitors | `snowflake/setup/01_warehouses.sql`, `04_resource_monitors.sql` |
| RBAC + dynamic data masking + governance | `snowflake/setup/03_roles_grants.sql`, `snowflake/masking/` |
| Row-count validation & completeness checks | `snowflake/tests/` |
| Git-based CI/CD, pipeline deployment | `.github/workflows/` |
| IaC (Terraform / Snowflake provider) | `terraform/` |
| Runbooks, RBAC matrix, data-quality docs | `docs/` |
| Python transformation / orchestration logic | `data_generation/`, `snowflake/orchestration/` |

---

## Architecture

```
                   SOURCE SYSTEMS (synthetic CSV)
   ┌───────────────┬───────────────────┬──────────────────┐
   │  Salesforce   │  Dynamics AX      │   PowerBill      │
   │  (CRM)        │  (ERP)            │   (Billing)       │
   └──────┬────────┴─────────┬─────────┴────────┬─────────┘
          │ PUT CSV → internal stage              │
          ▼                                        ▼
   ╔══════════════════════════════════════════════════════╗
   ║  BRONZE  — raw landed, as-is, with lineage metadata  ║
   ╚══════════════════════════════════════════════════════╝
          │ clean / standardize / dedupe / type / normalize
          ▼
   ║  SILVER  — conformed entities, normalized keys       ║
          │ entity resolution + dimensional modelling
          ▼
   ║  GOLD    — dim/fact (SCD2) + revenue-leakage exceptions║
          │
          ▼
   ║  SEMANTIC — Revenue Assurance views for dashboards   ║
   ╚══════════════════════════════════════════════════════╝
          │
   Tests  →  CI/CD  →  Dev / Staging / Prod (Snowflake)
```

See [`docs/architecture.md`](docs/architecture.md) for the full design and [`docs/data-model.md`](docs/data-model.md) for the dimensional model.

---

## The reconciliation problem

BrightFibre captures the same business reality in three systems with different IDs:

| Concept | Salesforce | Dynamics AX | PowerBill |
|---|---|---|---|
| Customer | `Account` | `Customer` | `Customer Code` |
| Sale | `Opportunity` | `Work Order` / `Contract` | `Invoice` |
| Asset / item | — | `Item` | `Invoice Line` |

The platform:
1. **Resolves customers** across all three systems into a single golden customer (deterministic on tax-id / name+postcode, then fuzzy via Jaro-Winkler).
2. **Reconciles the commercial thread**: opportunity → contract → invoice, expecting the billed amount to match what was sold/contracted.
3. **Detects leakage**: won-not-billed, active-contract-no-invoice, completed-work-not-invoiced, billing mismatches, orphan billing records, and overdue/uncollected invoices.

---

## Repository structure

```
snowflake-reconciliation-platform/
├── data_generation/            # Python synthetic data generators (Salesforce/AX/PowerBill)
│   └── generate_all.py
├── snowflake/
│   ├── setup/                  # Warehouses, DB/schemas, RBAC, resource monitors, stages
│   ├── bronze/                 # Raw landings per source system
│   ├── silver/                 # Cleaned, conformed entities
│   ├── gold/                   # Entity resolution, SCD2 dims, facts, leakage engine
│   ├── semantic/               # Revenue Assurance dashboard views
│   ├── masking/                # Dynamic data masking policies
│   ├── tests/                  # Row-count validation & completeness checks
│   └── orchestration/          # Python end-to-end pipeline runner
├── terraform/                  # Infrastructure-as-code (Snowflake provider)
├── .github/workflows/          # CI (lint + test) and CD (deploy) pipelines
├── docs/                       # Architecture, data model, RBAC matrix, runbook, data quality
├── requirements.txt
└── README.md
```

---

## Quickstart (free Snowflake trial)

```bash
# 1. Clone
git clone https://github.com/pcmCodes/snowflake-reconciliation-platform.git
cd snowflake-reconciliation-platform

# 2. Python environment
python -m venv .venv
.\.venv\Scripts\Activate.ps1        # Windows  (source .venv/bin/activate on macOS/Linux)
pip install -r requirements.txt

# 3. Configure Snowflake (use a free trial: https://www.snowflake.com/snowflake-free-trial/)
cp .env.example .env                # then fill in account/user/password

# 4. Generate synthetic source data
python data_generation/generate_all.py        # writes CSVs to data_output/

# 5. Provision infra & run the full pipeline (Bronze→Silver→Gold→Semantic→Tests)
python snowflake/orchestration/run_pipeline.py
```

The runner provisions warehousing/RBAC, stages and loads Bronze from the generated CSVs, then builds Silver and Gold, applies masking, and executes reconciliation tests — printing a pass/fail report.

---

## CI/CD

- **`.github/workflows/ci.yml`** — on every push/PR: lints SQL, runs the data generator in CI, and executes reconciliation tests against a CI Snowflake account (secrets stored as encrypted GitHub Actions secrets).
- **`.github/workflows/deploy.yml`** — on merge to `main`: deploys the pipeline to the `prod` Snowflake environment via environment-gated approval (`dev` → `staging` → `prod`).

Snowflake credentials never live in the repo — they are injected as GitHub Actions secrets / environment secrets.

---

## Testing & reconciliation

`snowflake/tests/` performs **source-to-target validation**:

- **Row-count validation** — Bronze row counts vs generated CSV row counts; Silver vs Bronze; Gold vs Silver.
- **Completeness checks** — no NULL business keys, no orphan fact FKs, every invoiced customer resolves to a golden customer, every exception links back to a source row (traceability).

---

## Documentation

- [Architecture](docs/architecture.md)
- [Data model](docs/data-model.md)
- [RBAC matrix](docs/rbac-matrix.md)
- [Operations runbook](docs/runbook.md)
- [Data quality & reconciliation](docs/data-quality.md)

---

## Tech stack

Snowflake (warehouses, stages, COPY, MERGE, masking policies, resource monitors, Snowpark-ready), Python (snowflake-connector-python, Faker, pandas), Terraform (Snowflake provider), GitHub Actions.

## Roadmap

- dbt model layer as an alternative orchestration path
- Snowpark for the iterative fuzzy-matching closure (transitive components)
- Great Expectations integration for declarative data-quality checks
- Power BI / Streamlit Revenue Assurance dashboard on the semantic layer

## License

MIT — see [LICENSE](LICENSE).
