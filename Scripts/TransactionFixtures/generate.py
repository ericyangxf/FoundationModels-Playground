"""Generates FM-Playground/transactions.json: 200 Canadian credit card
transactions over the 12 months ending 2026-10-06.

Seeded, so re-running produces the same file. Anything a test question leans
on (trips, recurring bills, the duplicate Netflix charge, the empty windows)
is placed explicitly; the rest is random fill inside fixed windows.
"""
import json
import random
import sys
from datetime import date, timedelta

AS_OF = date(2026, 10, 6)
START = date(2025, 10, 7)
rng = random.Random(27)

TOR = ("Toronto", "Ontario")
MIS = ("Mississauga", "Ontario")
VAN = ("Vancouver", "British Columbia")
WHI = ("Whistler", "British Columbia")
MTL = ("Montreal", "Quebec")
QCC = ("Quebec City", "Quebec")
CAL = ("Calgary", "Alberta")
BNF = ("Banff", "Alberta")
HFX = ("Halifax", "Nova Scotia")

rows = []


def add(d, merchant, amount, place, mcc):
    if isinstance(d, str):
        d = date.fromisoformat(d)
    assert START <= d <= AS_OF, (d, merchant)
    rows.append(dict(date=d, merchant=merchant, amount=round(amount, 2),
                     city=place[0], province=place[1], mcc=mcc))


def rand_date(lo, hi, avoid=()):
    lo, hi = date.fromisoformat(lo), date.fromisoformat(hi)
    while True:
        d = lo + timedelta(days=rng.randint(0, (hi - lo).days))
        if d not in avoid:
            return d


def rand_amount(lo, hi):
    return round(rng.uniform(lo, hi), 2)


# Days the explicit rows own: yesterday and last weekend must only hold what
# is placed on them, so random fill stays off.
RESERVED = {date(2026, 10, 3), date(2026, 10, 4), date(2026, 10, 5), date(2026, 10, 6)}


def fill(merchant, mcc, n, lo, hi, amt, place=TOR, places=None):
    for _ in range(n):
        p = rng.choice(places) if places else place
        add(rand_date(lo, hi, RESERVED), merchant, rand_amount(*amt), p, mcc)


# --- Recurring bills -------------------------------------------------------
# Rogers on the 3rd, with a price increase from March.
for i in range(12):
    m = 11 + i
    y, mo = 2025 + (m - 1) // 12, (m - 1) % 12 + 1
    d = date(y, mo, 3)
    add(d, "Rogers", 92.40 if d < date(2026, 3, 1) else 97.40, TOR, 4814)
# Netflix on the 15th, charged twice in August.
for i in range(12):
    m = 10 + i
    y, mo = 2025 + (m - 1) // 12, (m - 1) % 12 + 1
    add(date(y, mo, 15), "Netflix", 18.99, TOR, 5815)
add("2026-08-16", "Netflix", 18.99, TOR, 5815)
# GoodLife on the 1st.
for i in range(12):
    m = 11 + i
    y, mo = 2025 + (m - 1) // 12, (m - 1) % 12 + 1
    add(date(y, mo, 1), "GoodLife Fitness", 59.99, TOR, 7997)

# --- Trips -----------------------------------------------------------------
# Calgary and Banff, December 2025.
add("2025-11-28", "WestJet", 538.17, TOR, 4511)
add("2025-12-18", "Enterprise Rent-A-Car", 287.45, CAL, 3405)
add("2025-12-18", "Uber", 41.86, CAL, 4121)
add("2025-12-19", "Petro-Canada", 71.32, CAL, 5541)
add("2025-12-19", "Fairmont", 1486.20, BNF, 3590)
add("2025-12-20", "Tim Hortons", 9.85, BNF, 5814)
add("2025-12-21", "The Keg", 186.40, BNF, 5812)
add("2025-12-22", "Starbucks", 12.65, BNF, 5814)
add("2025-12-23", "WestJet", 64.00, CAL, 4511)

# Vancouver and Whistler, February 2026.
add("2026-02-03", "Air Canada", 684.21, TOR, 3009)
add("2026-02-12", "Uber", 38.74, VAN, 4121)
add("2026-02-12", "Hilton", 742.18, VAN, 3504)
add("2026-02-12", "Cactus Club Cafe", 96.55, VAN, 5812)
add("2026-02-13", "TransLink", 11.25, VAN, 4111)
add("2026-02-13", "Starbucks", 8.40, VAN, 5814)
add("2026-02-13", "Lyft", 22.31, VAN, 4121)
add("2026-02-14", "Cactus Club Cafe", 142.80, WHI, 5812)
add("2026-02-14", "Save-On-Foods", 46.12, WHI, 5411)
add("2026-02-15", "TransLink", 11.25, VAN, 4111)
add("2026-02-15", "Lyft", 27.66, VAN, 4121)
add("2026-02-15", "Save-On-Foods", 23.87, VAN, 5411)
add("2026-02-16", "Air Canada", 58.00, VAN, 3009)

# Montreal and Quebec City, July 2026.
add("2026-07-08", "VIA Rail", 164.30, TOR, 4112)
add("2026-07-09", "Marriott", 689.40, MTL, 3509)
add("2026-07-09", "STM", 14.50, MTL, 4111)
add("2026-07-10", "Uber", 26.93, MTL, 4121)
add("2026-07-10", "SAQ", 54.75, MTL, 5921)
add("2026-07-11", "IGA", 38.62, MTL, 5411)
add("2026-07-11", "STM", 14.50, MTL, 4111)
add("2026-07-12", "Tim Hortons", 7.35, QCC, 5814)
add("2026-07-13", "VIA Rail", 158.90, MTL, 4112)

# Halifax, August 2026.
add("2026-08-05", "Porter Airlines", 329.44, TOR, 4511)
add("2026-08-21", "Marriott", 412.66, HFX, 3509)
add("2026-08-22", "Uber", 19.47, HFX, 4121)

# --- Hand-placed days ------------------------------------------------------
# Last weekend (Sat Oct 3, Sun Oct 4) and yesterday (Mon Oct 5).
add("2026-10-03", "Uber", 18.20, TOR, 4121)
add("2026-10-04", "Cineplex", 38.50, TOR, 7832)
add("2026-10-05", "Loblaws", 87.34, TOR, 5411)
add("2026-10-05", "Tim Hortons", 6.45, TOR, 5814)

# Lyft at home, well before the past month.
add("2026-05-22", "Lyft", 16.84, TOR, 4121)

# September and the summer, so "last month" and "since June" have something.
add("2026-09-09", "Tim Hortons", 5.85, TOR, 5814)
add("2026-09-24", "Tim Hortons", 11.20, TOR, 5814)
add("2026-06-27", "LCBO", 42.80, TOR, 5921)
add("2026-08-29", "LCBO", 67.15, TOR, 5921)
add("2026-03-11", "Shoppers Drug Mart", 36.48, TOR, 5912)
add("2026-09-19", "Best Buy", 429.99, TOR, 5732)
add("2026-09-17", "No Frills", 58.36, TOR, 5411)
add("2026-09-26", "Metro", 44.18, TOR, 5411)

# --- Everyday spending (random fill) ----------------------------------------
fill("Uber", 4121, 4, "2025-10-07", "2026-04-01", (11, 34))
fill("Uber", 4121, 3, "2026-04-10", "2026-10-01", (9, 36))
add("2026-09-12", "Uber", 13.85, TOR, 4121)
add("2025-11-14", "Uber", 12.40, TOR, 4121)
fill("Presto", 4111, 4, "2025-10-07", "2026-10-01", (20, 60))

fill("Petro-Canada", 5541, 4, "2025-10-07", "2026-10-01", (52, 78))
fill("Esso", 5541, 3, "2025-10-07", "2026-10-01", (45, 70))
fill("Shell", 5541, 2, "2025-10-07", "2026-10-01", (44, 66))

fill("Loblaws", 5411, 7, "2025-10-07", "2026-10-01", (38, 165))
fill("Metro", 5411, 3, "2025-10-07", "2026-10-01", (25, 120))
fill("No Frills", 5411, 3, "2025-10-07", "2026-10-01", (30, 110))
fill("Sobeys", 5411, 2, "2025-10-07", "2026-10-01", (40, 95))
fill("T&T Supermarket", 5411, 3, "2025-10-07", "2026-10-01", (28, 88), place=MIS)

fill("Costco", 5300, 5, "2025-10-07", "2026-10-01", (68, 340), place=MIS)
fill("Walmart", 5311, 3, "2025-10-07", "2026-08-31", (18, 120))
fill("Dollarama", 5331, 2, "2025-10-07", "2026-10-01", (3, 24))

fill("Tim Hortons", 5814, 6, "2025-10-07", "2026-10-01", (2, 14))
fill("Starbucks", 5814, 7, "2025-10-07", "2026-10-01", (4, 16))
fill("McDonald's", 5814, 3, "2025-10-07", "2026-10-01", (7, 22))
fill("The Keg", 5812, 1, "2025-10-07", "2026-10-01", (95, 210))
fill("Cactus Club Cafe", 5812, 1, "2025-10-07", "2026-10-01", (48, 120))
fill("Boston Pizza", 5812, 1, "2025-10-07", "2026-10-01", (35, 80))
fill("DoorDash", 5812, 4, "2025-10-07", "2026-10-01", (24, 62))
fill("SkipTheDishes", 5814, 2, "2025-10-07", "2026-10-01", (21, 48))

fill("LCBO", 5921, 1, "2025-10-07", "2026-10-01", (18, 95))
fill("Shoppers Drug Mart", 5912, 4, "2025-10-07", "2026-10-01", (9, 85))
fill("Best Buy", 5732, 1, "2025-10-07", "2026-10-01", (45, 420))
fill("Apple Store", 5732, 2, "2025-10-07", "2026-08-31", (29, 380))
fill("Home Depot", 5200, 2, "2025-10-07", "2026-10-01", (35, 260))
fill("IKEA", 5712, 2, "2025-10-07", "2026-10-01", (60, 640), place=MIS)
fill("Canadian Tire", 5531, 4, "2025-10-07", "2026-10-01", (22, 190))
fill("Sport Chek", 5941, 2, "2025-10-07", "2026-10-01", (40, 210))
fill("Indigo", 5942, 2, "2025-10-07", "2026-10-01", (16, 64))
fill("Lululemon", 5655, 2, "2025-10-07", "2026-10-01", (68, 198))
fill("Winners", 5651, 2, "2025-10-07", "2026-10-01", (25, 110))
fill("Cineplex", 7832, 2, "2025-10-07", "2026-09-30", (16, 45))
fill("Ticketmaster", 7922, 2, "2025-10-07", "2026-09-15", (85, 290))
fill("PetSmart", 5995, 2, "2025-10-07", "2026-10-01", (24, 96))
fill("Green P Parking", 7523, 2, "2025-10-07", "2026-10-01", (6, 28))
fill("Sephora", 5977, 1, "2025-10-07", "2026-08-15", (32, 120))
fill("Amazon", 5999, 7, "2025-10-07", "2026-10-01", (14, 160))
fill("Canadian Red Cross", 8398, 1, "2025-10-07", "2026-10-01", (25, 100))

if len(rows) != 200:
    sys.exit(f"expected 200 rows, got {len(rows)}")

rows.sort(key=lambda r: (r["date"], r["merchant"]))
out = []
for i, r in enumerate(rows, 1):
    out.append(dict(
        id=f"TXN-{i:04d}",
        date=r["date"].isoformat(),
        merchant=r["merchant"],
        amount=r["amount"],
        city=r["city"],
        province=r["province"],
        country="Canada",
        mcc=r["mcc"],
    ))

path = sys.argv[1]
with open(path, "w") as f:
    json.dump({"asOf": AS_OF.isoformat(), "currency": "CAD", "transactions": out}, f, indent=2)
    f.write("\n")
print(f"wrote {len(out)} transactions to {path}")
