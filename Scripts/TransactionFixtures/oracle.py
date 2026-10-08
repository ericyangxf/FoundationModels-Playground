"""Independent ground truth for the 100 cases: filters the JSON the way the
expected scope says and works out each answer, without touching app code.

Usage: python3 -I oracle.py <transactions.json> [--swift <out.swift>]
"""
import json
import sys
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP

import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cases import CASES  # noqa: E402

RANGES = {
    "airlines": [(3000, 3299), (4511, 4511)],
    "hotels": [(3500, 3999), (7011, 7011)],
    "carRental": [(3300, 3441), (7512, 7519)],
    "cruises": [(4411, 4411)],
    "travelAgencies": [(4722, 4722)],
    "publicTransit": [(4111, 4112), (4131, 4131)],
    "taxiAndRideshare": [(4121, 4121)],
    "parkingAndTolls": [(4784, 4784), (7523, 7523)],
    "gasStations": [(5541, 5542)],
    "groceries": [(5411, 5499)],
    "restaurants": [(5811, 5814)],
    "liquorStores": [(5921, 5921)],
    "departmentAndDiscountStores": [(5300, 5399)],
    "clothing": [(5611, 5699)],
    "electronics": [(5732, 5732), (5734, 5734)],
    "furniture": [(5712, 5722)],
    "homeImprovement": [(5200, 5261)],
    "sportingGoods": [(5940, 5941)],
    "toysAndHobbies": [(5945, 5945)],
    "booksAndNews": [(5942, 5942), (5994, 5994)],
    "jewelry": [(5944, 5944)],
    "giftsAndFlowers": [(5947, 5947), (5992, 5992)],
    "utilities": [(4900, 4900)],
    "phoneInternetAndCable": [(4812, 4816), (4899, 4899)],
    "streamingAndDigitalGoods": [(5815, 5818)],
    "insurance": [(6300, 6300)],
    "financialServices": [(6010, 6051), (6211, 6211)],
    "laundryAndDryCleaning": [(7210, 7216)],
    "autoPartsAndService": [(5531, 5533), (7531, 7549)],
    "pharmacies": [(5912, 5912)],
    "healthcare": [(4119, 4119), (8011, 8099)],
    "beautyAndSpa": [(5977, 5977), (7230, 7230), (7298, 7298)],
    "gymsAndFitness": [(7941, 7941), (7997, 7997)],
    "petsAndVets": [(742, 742), (5995, 5995)],
    "entertainment": [(7832, 7832), (7922, 7922), (7991, 7991), (7996, 7996), (7998, 7998)],
    "education": [(8211, 8299)],
    "childcare": [(8351, 8351)],
    "charity": [(8398, 8398)],
    "government": [(9211, 9402)],
}
TITLES = {
    "airlines": "Airlines", "hotels": "Hotels & Lodging", "carRental": "Car Rental",
    "publicTransit": "Public Transit", "taxiAndRideshare": "Taxi & Rideshare",
    "parkingAndTolls": "Parking & Tolls", "gasStations": "Gas Stations", "groceries": "Groceries",
    "restaurants": "Restaurants & Bars", "liquorStores": "Liquor Stores",
    "departmentAndDiscountStores": "Department & Discount Stores", "clothing": "Clothing & Apparel",
    "electronics": "Electronics & Software", "furniture": "Furniture & Home Furnishings",
    "homeImprovement": "Home Improvement & Hardware", "sportingGoods": "Sporting Goods & Bicycles",
    "booksAndNews": "Books & Newsstands", "phoneInternetAndCable": "Phone, Internet & Cable",
    "streamingAndDigitalGoods": "Streaming & Digital Goods", "autoPartsAndService": "Auto Parts & Service",
    "pharmacies": "Pharmacies", "beautyAndSpa": "Beauty & Spas", "gymsAndFitness": "Gyms & Fitness",
    "petsAndVets": "Pets & Veterinary", "entertainment": "Entertainment & Attractions",
    "charity": "Charity & Donations",
}
ORDER = list(RANGES)  # first matching category wins, as in Swift (allCases order)
MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August",
          "September", "October", "November", "December"]


def category(mcc):
    for name in ORDER:
        if any(lo <= mcc <= hi for lo, hi in RANGES[name]):
            return name
    return None


def compact(text):
    return "".join(ch for ch in text.lower() if ch.isalnum())


def matches(t, scope, dates=None):
    dates = scope["dates"] if dates is None else dates
    if scope["merchant"]:
        a, b = compact(t["merchant"]), compact(scope["merchant"])
        if not (a in b or b in a):
            return False
    if scope["categories"] and not scope["merchant"]:
        if category(t["mcc"]) not in scope["categories"]:
            return False
    if scope["min"] is not None and t["cents"] < scope["min"] * 100:
        return False
    if scope["max"] is not None and t["cents"] > scope["max"] * 100:
        return False
    if dates:
        if t["date"] < dates[0] or t["date"] > dates[1]:
            return False
    return True


def money(cents):
    return f"${cents // 100:,}.{cents % 100:02d}"


def dollars(cents):
    return f"{cents // 100}.{cents % 100:02d}"


def group_key(t, by):
    if by == "merchant":
        return t["merchant"]
    if by == "category":
        c = category(t["mcc"])
        return TITLES.get(c, c) if c else "Other"
    if by == "city":
        return f"{t['city']}, {t['province']}"
    if by == "province":
        return t["province"]
    if by == "month":
        y, m, _ = t["date"].split("-")
        return f"{MONTHS[int(m) - 1]} {y}"


def breakdown(rows, by):
    groups = {}
    for t in rows:
        k = group_key(t, by)
        g = groups.setdefault(k, [k, 0, 0])
        g[1] += t["cents"]
        g[2] += 1
    return sorted(groups.values(), key=lambda g: (-g[1], g[0]))


def newest_first(rows):
    return sorted(rows, key=lambda t: (t["date"], t["id"]), reverse=True)


def answer(rows, check):
    kind = check[0]
    if kind == "total":
        return dict(amount=sum(t["cents"] for t in rows))
    if kind == "count":
        return dict(count=len(rows))
    if kind == "average":
        total = Decimal(sum(t["cents"] for t in rows))
        avg = (total / len(rows)).quantize(Decimal(1), rounding=ROUND_HALF_UP)
        return dict(amount=int(avg))
    if kind in ("largest", "smallest"):
        ordered = newest_first(rows)
        pick = max(ordered, key=lambda t: t["cents"]) if kind == "largest" else min(ordered, key=lambda t: t["cents"])
        ties = [t for t in rows if t["cents"] == pick["cents"] and t["merchant"] != pick["merchant"]]
        assert not ties, f"tie on {kind}: {pick} vs {ties}"
        return dict(merchant=pick["merchant"], amount=pick["cents"], date=pick["date"])
    if kind in ("latest", "latestAmount"):
        t = newest_first(rows)[0]
        return dict(date=t["date"], amount=t["cents"], merchant=t["merchant"])
    if kind == "earliest":
        t = newest_first(rows)[-1]
        return dict(date=t["date"], amount=t["cents"], merchant=t["merchant"])
    if kind == "list":
        _, order, n = check
        if order == "newest":
            ordered = newest_first(rows)
        else:
            ordered = sorted(rows, key=lambda t: (t["cents"], t["date"]), reverse=True)
        shown = ordered[:n]
        amounts = [t["cents"] for t in shown]
        assert len(set(amounts)) == len(amounts) or order != "largest", f"duplicate amounts in list {amounts}"
        return dict(amounts=amounts, rows=shown)
    if kind == "listDates":
        return dict(dates=sorted(t["date"] for t in rows))
    if kind == "group":
        _, by, name = check
        groups = breakdown(rows, by)
        if name is None:
            assert len(groups) < 2 or groups[0][1] != groups[1][1], f"tie at top of {by}: {groups[:2]}"
            g = groups[0]
        else:
            g = next(g for g in groups if g[0] == name or g[0].startswith(name + ","))
        return dict(group=g[0], amount=g[1], count=g[2], groups=groups[:4])
    if kind == "nothing":
        assert not rows, f"expected nothing, got {rows}"
        return dict()
    raise ValueError(kind)


def shifted(d, days):
    return (date.fromisoformat(d) + timedelta(days=days)).isoformat()


def main():
    data = json.load(open(sys.argv[1]))
    rows = data["transactions"]
    for t in rows:
        t["cents"] = round(t["amount"] * 100)
    results = []
    problems = []
    for name, question, scope, check in CASES:
        hits = [t for t in rows if matches(t, scope)]
        try:
            if check[0] != "nothing":
                assert hits, "no matching transactions"
            result = answer(hits, check)
        except AssertionError as e:
            problems.append(f"{name}: {e}")
            print(f"{name:40s} PROBLEM: {e}")
            continue
        # Off-by-one sensitivity at the start of a lookback window.
        warn = ""
        if scope["dates"]:
            for delta in (-1, 1):
                alt = (shifted(scope["dates"][0], delta), scope["dates"][1])
                if [t for t in rows if matches(t, scope, alt)] != hits:
                    warn += f" [start{delta:+d} changes set]"
        results.append((name, question, scope, check, hits, result))
        print(f"{name:40s} n={len(hits):3d} {check} -> "
              + ", ".join(f"{k}={money(v) if k == 'amount' else v}" for k, v in result.items() if k not in ('rows', 'groups'))
              + warn)
        if check[0] == "group":
            print("      ", [(g[0], money(g[1]), g[2]) for g in result["groups"]])
    print(f"\n{len(problems)} problems")
    for p in problems:
        print("  ", p)
    return data, results, problems


if __name__ == "__main__":
    main()
