"""
Synthetic source-data generator for the Snowflake Reconciliation Platform.

Produces CSVs for Salesforce (CRM), Dynamics AX (ERP) and PowerBill (billing)
into ./data_output/<source>/<table>.csv, engineered so the platform exercises
every layer and every revenue-leakage detector:

  - Shared tax_id across systems + slightly different name variants -> exercises
    DETERMINISTIC (tax_id) and FUZZY (Jaro-Winkler) entity resolution.
  - A handful of PowerBill-only customers (no SF/AX counterpart) -> ORPHAN_BILLING.
  - Controlled billing gaps / mismatches -> CONTRACT_NO_INVOICE, BILLING_MISMATCH,
    WON_NOT_BILLED, WORK_ORDER_NOT_INVOICED, OVERDUE_UNCOLLECTED.

Reproducible: random.seed(42). No external systems required.
"""
from __future__ import annotations

import csv
import os
import random
from datetime import date, timedelta

random.seed(42)

OUT = os.path.join(os.path.dirname(__file__), "..", "data_output")
OUT = os.path.abspath(OUT)

# ---------------------------------------------------------------- helpers
def month_offset(base: date, n: int) -> date:
    """First day of the month that is `n` months from base."""
    idx = (base.year * 12 + (base.month - 1)) + n
    y, m = divmod(idx, 12)
    return date(y, m + 1, 1)

def dts(d: date) -> str:
    return d.strftime("%Y-%m-%d %H:%M:%S")

def write_csv(source: str, table: str, rows: list, header: list) -> str:
    d = os.path.join(OUT, source)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, f"{table}.csv")
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"  wrote {source}/{table}.csv  rows={len(rows)}")
    return path

# ---------------------------------------------------------------- name pools
WORD1 = ["Bright","Summit","Apex","Cedar","Nova","Orion","Pine","River","Atlas",
         "Vivid","Cobalt","Indigo","Harbor","Lumen","Quartz","Verge","Meridian",
         "Solace","Tessera","Umbra","Vortex","Wilder","Zenith","Aster","Borealis"]
WORD2 = ["Fibre","Cellular","Networks","Systems","Connect","Cloud","Data","Grid",
         "Wave","Signal","Logic","Matrix","Path","Link","Sync","Forge","Pulse","Node"]

def make_name(i: int) -> str:
    w1 = WORD1[(i * 7) % len(WORD1)]
    w2 = WORD2[(i * 5) % len(WORD2)]
    return f"{w1} {w2} Telecom"

_FIRSTS = ["Thabo", "Lerato", "Sipho", "Naledi", "Kabelo", "Aisha", "Johan", "Priya", "David", "Zanele"]
_LASTS = ["Mokoena", "Naidoo", "van Wyk", "Dlamini", "Botha", "Patel", "Mthembu", "Khumalo", "Singh", "Adams"]

def fake_first():
    return random.choice(_FIRSTS)

def fake_last():
    return random.choice(_LASTS)

# ---------------------------------------------------------------- dimensions
TODAY = date.today()
SEGMENTS = ["Enterprise", "Mid-Market", "SMB"]
CITIES = [("Johannesburg", "ZA"), ("Cape Town", "ZA"), ("Durban", "ZA"),
          ("Pretoria", "ZA"), ("Bloemfontein", "ZA"), ("London", "GB"), ("New York", "US")]

N_CUSTOMERS = 60
N_ORPHANS = 5

# Golden customers ------------------------------------------------------------
golden = []
for i in range(1, N_CUSTOMERS + 1):
    city, country = random.choice(CITIES)
    golden.append({
        "i": i,
        "name": make_name(i),
        "tax_id": f"VAT{i:07d}",
        "postal": f"{1000 + i:04d}",
        "city": city, "country": country,
        "segment": random.choice(SEGMENTS),
    })

# Per-system name variants (normalization leaves differences that keep
# Jaro-Winkler >= 90 across pairs, forcing fuzzy matching where tax_id is absent).
def sf_name(g):  return g["name"] + " Ltd"
def ax_name(g):  return g["name"] + " Limited"
def pb_name(g):  return g["name"]  # no suffix

# Items catalogue -------------------------------------------------------------
ITEMS = []
for j in range(1, 21):
    ITEMS.append({
        "item_id": f"ITM-{j:04d}",
        "item_name": random.choice(["Fibre Line", "Router", "Install Kit",
                                    "Support Pack", "Data SIM", "Upgrade", "Site Survey"]),
        "category": random.choice(["Hardware", "Service", "Installation"]),
        "unit_price": round(random.choice([500, 1200, 2500, 8000, 15000]), 2),
    })

# ---------------------------------------------------------------- writers
sf_accounts, sf_opps, sf_contacts = [], [], []
ax_customers, ax_wos, ax_contracts = [], [], []
pb_customers, pb_invoices, pb_invoice_lines = [], [], []

# Controlled injection sets
won_not_billed_set = set(range(1, 7))                 # 6 customers -> WON_NOT_BILLED
contract_no_invoice_set = set(range(7, 27))           # 20 customers -> CONTRACT_NO_INVOICE
wo_not_invoiced_set = set(range(27, 35))              # 8 customers -> WORK_ORDER_NOT_INVOICED
mismatch_set = set(range(35, 45))                     # 10 customers -> one BILLING_MISMATCH
overdue_set = set(range(45, 51))                       # 6 customers -> OVERDUE_UNCOLLECTED

seq = {"op": 0, "wo": 0, "inv": 0, "line": 0, "ct": 0, "con": 0}

def new_id(kind, pfx):
    seq[kind] += 1
    return f"{pfx}-{seq[kind]:05d}"

for g in golden:
    i = g["i"]
    sf_id = f"SF-ACC-{i:04d}"
    ax_id = f"AX-CUST-{i:04d}"
    pb_id = f"PB-CUST-{i:04d}"

    # tax_id presence across systems (AX always; SF 70%; PB 60%)
    sf_tax = g["tax_id"] if i % 10 < 7 else ""
    ax_tax = g["tax_id"]
    pb_tax = g["tax_id"] if i % 10 < 6 else ""

    sf_accounts.append([
        sf_id, sf_name(g), g["city"], g["postal"], g["country"],
        f"+27{1000000+i}", f"www.{g['name'].split()[0].lower()}.co.za",
        "Telecommunications", g["segment"], "Active",
        dts(TODAY - timedelta(days=720)), dts(TODAY - timedelta(days=random.randint(1, 30))),
    ])
    ax_customers.append([
        ax_id, ax_name(g), g["city"], g["postal"], g["country"],
        f"+27{2000000+i}", f"billing{i}@{g['name'].split()[0].lower()}.co.za", ax_tax,
        round(random.choice([50000, 100000, 250000]), 2), "Active",
    ])
    pb_customers.append([
        pb_id, pb_name(g), g["city"], g["postal"], g["country"],
        f"info{i}@{g['name'].split()[0].lower()}.co.za", f"+27{3000000+i}", "Active",
    ])

    # SF contact (1 per account)
    sf_contacts.append([
        new_id("ct", "SF-CON"), sf_id, fake_first(), fake_last(),
        f"contact{i}@example.co.za", f"+27{4000000+i}",
    ])

    # Opportunities: 1-2 per account; ~won for chosen sets
    n_opp = random.randint(1, 2)
    for _ in range(n_opp):
        is_won = i in won_not_billed_set or random.random() < 0.25
        stage = "Closed Won" if is_won else random.choice(["Prospecting", "Qualification", "Proposal", "Negotiation"])
        amount = round(random.choice([15000, 40000, 75000, 120000, 250000]), 2)
        if i in won_not_billed_set:
            # close ~120 days ago; billing gap in the following 90 days
            close = TODAY - timedelta(days=120)
        else:
            close = TODAY - timedelta(days=random.randint(5, 60))
        sf_opps.append([
            new_id("op", "SF-OPP"), sf_id, f"{g['name']} - Renewal", stage, amount,
            close.isoformat(), dts(close - timedelta(days=60)),
        ])

    # Contract: active for first 50, expired for last 10
    active = i <= 50
    start = TODAY - timedelta(days=365) if active else TODAY - timedelta(days=730)
    end = TODAY + timedelta(days=365) if active else TODAY - timedelta(days=60)
    annual = random.choice([12000, 24000, 36000, 60000, 120000, 180000, 240000])
    ax_contracts.append([
        new_id("con", "AX-CON"), ax_id, f"{g['name']} MSA", start.isoformat(),
        end.isoformat(), annual, ("Active" if active else "Expired"),
    ])

    # Work orders: 0-3, some completed
    n_wo = random.randint(0, 3)
    for w in range(n_wo):
        completed = random.random() < 0.7
        item = random.choice(ITEMS)
        qty = random.randint(1, 5)
        amt = round(qty * item["unit_price"], 2)
        created = TODAY - timedelta(days=random.randint(10, 200))
        completed_dt = created + timedelta(days=random.randint(1, 20)) if completed else None
        # Inject: customers in wo_not_invoiced_set get a completed WO in a month with NO invoice
        if i in wo_not_invoiced_set and w == 0:
            completed = True
            completed_dt = month_offset(TODAY, -6) + timedelta(days=10)  # month -6, no invoice there
        ax_wos.append([
            new_id("wo", "AX-WO"), ax_id, item["item_id"], item["item_name"], qty, amt,
            ("Completed" if completed else random.choice(["Open", "In Progress"])),
            dts(created), (dts(completed_dt) if completed_dt else ""),
        ])

    # ---- invoices -------------------------------------------------------
    monthly = round(annual / 12, 2)
    skip_current = i in contract_no_invoice_set
    skip_gap = i in won_not_billed_set  # skip months -4..-1 to create the won-not-billed gap

    invoice_months = list(range(-11, 1))  # -11 .. 0
    if skip_current:
        invoice_months = [m for m in invoice_months if m != 0]
    if skip_gap:
        invoice_months = [m for m in invoice_months if m not in (-4, -3, -2, -1)]

    for m in invoice_months:
        inv_date = month_offset(TODAY, m) + timedelta(days=random.randint(1, 25))
        due = inv_date + timedelta(days=30)

        # expected amount for the month: contract monthly (active) else work-order sum
        if active:
            expected = monthly
        else:
            # expired-contract: expected from completed work orders in that month
            expected = round(sum(
                wo[5] for wo in ax_wos
                if wo[1] == ax_id and wo[6] == "Completed"
                and wo[8] and month_offset(date.fromisoformat(wo[8][:10]), 0) == month_offset(inv_date, 0)
            ), 2)

        # billing mismatch injection
        if i in mismatch_set and m == -8:
            total = round(expected + 5000, 2) if expected else 7500.0
        else:
            total = round(expected + random.uniform(-0.5, 0.5), 2)

        # overdue injection: due date in past and unpaid
        if i in overdue_set and m == -3:
            inv_date = TODAY - timedelta(days=70)
            due = inv_date + timedelta(days=30)
            status = "Open"
        else:
            status = "Paid" if m <= -2 else random.choice(["Paid", "Open"])

        inv_id = new_id("inv", "PB-INV")
        pb_invoices.append([
            inv_id, pb_id, inv_date.isoformat(), due.isoformat(), total, status, inv_date.strftime("%Y-%m"),
        ])

        # invoice lines that sum exactly to total
        n_lines = random.randint(1, 3)
        parts = [total // n_lines] * n_lines if n_lines else [total]
        # distribute remainder
        rem = round(total - sum(parts), 2)
        parts[-1] = round(parts[-1] + rem, 2)
        for p in parts:
            qty = 1
            pb_invoice_lines.append([
                new_id("line", "PB-LN"), inv_id, "Telecom service", qty, round(p, 2),
                round(p, 2), round(p * 0.15, 2),
            ])

# ---------------------------------------------------------------- orphans
for k in range(1, N_ORPHANS + 1):
    name = f"Unknown Billing Co {k}"
    pb_id = f"PB-ORPH-{k:04d}"
    pb_customers.append([
        pb_id, name, "Sandton", "2196", "ZA",
        f"orph{k}@nowhere.co.za", f"+27{9000000+k}", "Active",
    ])
    for m in (-5, -2, 0):
        inv_date = month_offset(TODAY, m) + timedelta(days=5)
        due = inv_date + timedelta(days=30)
        total = round(random.choice([3200, 5400, 8800]), 2)
        inv_id = new_id("inv", "PB-INV")
        pb_invoices.append([inv_id, pb_id, inv_date.isoformat(), due.isoformat(), total, "Paid", inv_date.strftime("%Y-%m")])
        pb_invoice_lines.append([new_id("line", "PB-LN"), inv_id, "Service", 1, total, total, round(total*0.15, 2)])

# ---------------------------------------------------------------- write all
print("Generating source data ->", OUT)
write_csv("salesforce", "sf_accounts", sf_accounts,
          ["account_id","account_name","billing_city","billing_postal_code","billing_country",
           "phone","website","industry","segment","account_status","created_date","last_modified_date"])
write_csv("salesforce", "sf_opportunities", sf_opps,
          ["opportunity_id","account_id","opportunity_name","stage","amount","close_date","created_date"])
write_csv("salesforce", "sf_contacts", sf_contacts,
          ["contact_id","account_id","first_name","last_name","email","phone"])
write_csv("dynamics_ax", "ax_customers", ax_customers,
          ["customer_id","customer_name","city","postal_code","country","phone","email",
           "tax_id","credit_limit","status"])
write_csv("dynamics_ax", "ax_work_orders", ax_wos,
          ["work_order_id","customer_id","item_id","description","quantity","amount",
           "status","created_date","completed_date"])
write_csv("dynamics_ax", "ax_items", ITEMS,
          ["item_id","item_name","category","unit_price"])
write_csv("dynamics_ax", "ax_contracts", ax_contracts,
          ["contract_id","customer_id","contract_name","start_date","end_date","annual_value","status"])
write_csv("powerbill", "pb_customers", pb_customers,
          ["customer_code","customer_name","address_city","postal_code","country",
           "email","phone","account_status"])
write_csv("powerbill", "pb_invoices", pb_invoices,
          ["invoice_id","customer_code","invoice_date","due_date","total_amount",
           "invoice_status","billing_period"])
write_csv("powerbill", "pb_invoice_lines", pb_invoice_lines,
          ["line_id","invoice_id","description","quantity","unit_price","line_amount","tax_amount"])

print("Done.")
