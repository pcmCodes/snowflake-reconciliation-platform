#!/usr/bin/env python3
"""
End-to-end pipeline runner for the Snowflake Reconciliation Platform.

Steps:
  1. Provision infra (setup/*.sql: warehouses, DB/schemas, RBAC, monitors, stages)
  2. PUT generated source CSVs into the internal stage
  3. Load Bronze (COPY), build Silver, Gold, Semantic, apply Masking
  4. Run reconciliation tests -> print PASS/FAIL report; exit non-zero on failure

Configure Snowflake via .env (see .env.example). Requires snowflake-connector-python.
"""
from __future__ import annotations

import os
import pathlib
import sys

try:
    import snowflake.connector
except ImportError:
    print("Missing dependency. Run: pip install -r requirements.txt")
    sys.exit(1)

ROOT = pathlib.Path(__file__).resolve().parents[2]   # repo root
SQL  = ROOT / "snowflake"
DATA = ROOT / "data_output"

CFG_KEYS = ["SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER", "SNOWFLAKE_PASSWORD",
            "SNOWFLAKE_ROLE", "SNOWFLAKE_WAREHOUSE", "SNOWFLAKE_DATABASE"]


def load_env() -> dict:
    env_file = ROOT / ".env"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip())
    return {k: os.environ.get(k, "") for k in CFG_KEYS}


def connect(cfg: dict):
    return snowflake.connector.connect(
        account=cfg["SNOWFLAKE_ACCOUNT"],
        user=cfg["SNOWFLAKE_USER"],
        password=cfg["SNOWFLAKE_PASSWORD"],
        role=cfg["SNOWFLAKE_ROLE"] or "ACCOUNTADMIN",
        warehouse=cfg["SNOWFLAKE_WAREHOUSE"] or "RECON_LOAD_WH",
        database=cfg["SNOWFLAKE_DATABASE"] or "RECON_PLATFORM",
    )


def split_statements(sql: str) -> list[str]:
    """Split SQL on ';' outside single-quoted strings and line comments."""
    stmts, buf, i, in_str = [], [], 0, False
    while i < len(sql):
        ch, nxt = sql[i], sql[i + 1] if i + 1 < len(sql) else ""
        if not in_str and ch == "-" and nxt == "-":          # line comment -> skip
            j = sql.find("\n", i)
            if j == -1:
                break
            i = j
            continue
        if ch == "'":
            in_str = not in_str
        if ch == ";" and not in_str:
            stmt = "".join(buf).strip()
            if stmt:
                stmts.append(stmt)
            buf, i = [], i + 1
            continue
        buf.append(ch)
        i += 1
    last = "".join(buf).strip()
    if last:
        stmts.append(last)
    return stmts


def run_sql_file(cur, path: pathlib.Path) -> list[tuple]:
    """Execute every statement in a file; return [(columns, rows), ...] for rowsets."""
    results = []
    for stmt in split_statements(path.read_text(encoding="utf-8")):
        try:
            cur.execute(stmt)
        except Exception as exc:                       # surface one statement's failure
            raise RuntimeError(f"Failed in {path.name}:\n{stmt[:200]}\n-> {exc}") from exc
        try:
            if cur.description is not None:
                cols = [d[0] for d in cur.description]
                rows = cur.fetchall()
                if rows:
                    results.append((cols, rows))
        except Exception:
            pass
    return results


def put_files(cur):
    if not DATA.exists():
        print("No data_output/ found. Run: python data_generation/generate_all.py")
        sys.exit(1)
    for csv_path in sorted(DATA.rglob("*.csv")):
        rel = csv_path.relative_to(DATA).as_posix()            # e.g. salesforce/sf_accounts.csv
        local = str(csv_path).replace("\\", "/")
        cur.execute(f"PUT 'file://{local}' @recon_csv_stage/{rel} OVERWRITE=TRUE AUTO_COMPRESS=FALSE")
        print(f"  PUT {rel}")


def main():
    cfg = load_env()
    if not cfg["SNOWFLAKE_ACCOUNT"] or not cfg["SNOWFLAKE_USER"]:
        print("Missing Snowflake config. Fill in .env (see .env.example).")
        sys.exit(1)

    conn = connect(cfg)
    cur = conn.cursor()

    stages = [
        ("setup",    SQL / "setup"),
        ("put csvs", None),
        ("bronze",   SQL / "bronze"),
        ("silver",   SQL / "silver"),
        ("gold",     SQL / "gold"),
        ("semantic", SQL / "semantic"),
        ("masking",  SQL / "masking"),
    ]
    for label, folder in stages:
        print(f"\n=== {label.upper()} ===")
        if folder is None:
            put_files(cur)
            continue
        for f in sorted(folder.glob("*.sql")):
            print(f"  {f.name}")
            run_sql_file(cur, f)

    print("\n=== TESTS ===")
    total = failures = 0
    for f in sorted((SQL / "tests").glob("*.sql")):
        print(f"  {f.name}")
        for cols, rows in run_sql_file(cur, f):
            if "status" in [c.lower() for c in cols]:
                for row in rows:
                    d = dict(zip(cols, row))
                    ok = str(d.get("status", "")).upper() == "PASS"
                    total += 1
                    if not ok:
                        failures += 1
                    print(f"    [{'PASS' if ok else 'FAIL'}] {d.get('check_name','?')}: "
                          f"expected={d.get('expected')} actual={d.get('actual')}")
    conn.close()
    print(f"\n=== SUMMARY: {total - failures}/{total} passed, {failures} failed ===")
    if failures:
        print("Pipeline FAILED reconciliation checks.")
        sys.exit(1)
    print("Pipeline complete.")


if __name__ == "__main__":
    main()
