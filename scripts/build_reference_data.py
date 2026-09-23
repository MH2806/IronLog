#!/usr/bin/env python3
"""
Builds IronLog/Resources/reference.json from the OpenPowerlifting bulk CSV.

What it produces
  * Per-lift percentile curves (squat, bench, deadlift, total) by sex and
    bodyweight, for two populations: all raw lifters, and drug-tested raw lifters.
  * DOTS percentile curves by sex, overall and by age band.
  * The DOTS / IPF GL coefficients the app uses, *validated against the
    Dots and Goodlift columns OpenPowerlifting publishes*. If our DOTS formula
    disagrees with the dataset, the build fails, so the app can never ship a
    score that doesn't match the real-world number.

Each lifter counts once per lift (their best raw result), so people with 40
meets don't skew the curves.

Usage:
  python build_reference_data.py --zip openpowerlifting-latest.zip --out reference.json
"""
import argparse
import datetime as dt
import json
import sys
import zipfile

import numpy as np
import pandas as pd

# ---------------------------------------------------------------- formulas
DOTS = {
    "M": [-0.0000010930, 0.0007391293, -0.1918759221, 24.0900756, -307.75076],
    "F": [-0.0000010706, 0.0005158568, -0.1126655495, 13.6175032, -57.96288],
}
DOTS_BW = {"M": (40.0, 210.0), "F": (40.0, 150.0)}

# IPF GL (2020), classic/raw only.
GL = {
    "M": {"sbd": [1199.72839, 1025.18162, 0.00921], "b": [320.98041, 281.40258, 0.01008]},
    "F": {"sbd": [610.32796, 1045.59282, 0.03048], "b": [142.40398, 442.52671, 0.04724]},
}

PCTS = np.arange(1, 100)  # 1..99
BW_CENTERS = list(range(45, 161, 5))  # 45, 50, ... 160 (last one is open-ended above)
MIN_BIN = 500
AGE_BANDS = [(14, 18), (19, 23), (24, 34), (35, 39), (40, 49), (50, 59), (60, 99)]
USECOLS = ["Name", "Sex", "Event", "Equipment", "Age", "BodyweightKg",
           "Best3SquatKg", "Best3BenchKg", "Best3DeadliftKg", "TotalKg",
           "Dots", "Goodlift", "Wilks", "Tested", "Date"]


def dots(total, bw, sex):
    a, b, c, d, e = DOTS[sex]
    lo, hi = DOTS_BW[sex]
    x = np.clip(bw, lo, hi)
    return total * 500.0 / (a * x**4 + b * x**3 + c * x**2 + d * x + e)


def goodlift(total, bw, sex, kind):
    A, B, C = GL[sex][kind]
    return total * 100.0 / (A - B * np.exp(-C * bw))


def load(zip_path):
    with zipfile.ZipFile(zip_path) as zf:
        name = next(n for n in zf.namelist() if n.endswith(".csv"))
        date = name.rsplit("-", 3)[-3:]
        with zf.open(name) as f:
            df = pd.read_csv(f, usecols=USECOLS, low_memory=False,
                             dtype={"Name": str, "Sex": str, "Event": str,
                                    "Equipment": str, "Tested": str, "Date": str})
    return df, "-".join(date).replace(".csv", "")


def validate(df):
    """Compare our formulas to OpenPowerlifting's own computed columns."""
    report = {}
    sbd = df[(df.Event == "SBD") & (df.Equipment == "Raw") & (df.TotalKg > 0)
             & df.BodyweightKg.notna() & df.Sex.isin(["M", "F"])]
    sample = sbd.sample(min(20000, len(sbd)), random_state=1)

    errs = []
    for sex in ("M", "F"):
        s = sample[(sample.Sex == sex) & sample.Dots.notna()]
        errs.append(np.abs(dots(s.TotalKg.values, s.BodyweightKg.values, sex) - s.Dots.values))
    errs = np.concatenate(errs)
    report["dots"] = {"n": int(errs.size), "medianAbsErr": float(np.median(errs)),
                      "p99AbsErr": float(np.percentile(errs, 99))}
    if errs.size < 100 or np.median(errs) > 0.02 or np.percentile(errs, 99) > 0.5:
        sys.exit(f"DOTS validation FAILED against dataset: {report['dots']}")

    gerrs = []
    for sex in ("M", "F"):
        s = sample[(sample.Sex == sex) & sample.Goodlift.notna()]
        gerrs.append(np.abs(goodlift(s.TotalKg.values, s.BodyweightKg.values, sex, "sbd") - s.Goodlift.values))
    gerrs = np.concatenate(gerrs)
    gl_ok = gerrs.size >= 100 and np.median(gerrs) < 0.05
    report["goodlift"] = {"n": int(gerrs.size),
                          "medianAbsErr": float(np.median(gerrs)) if gerrs.size else None,
                          "passed": bool(gl_ok)}
    if not gl_ok:
        print(f"WARNING: GL validation failed, GL points will be hidden in app: {report['goodlift']}")
    # Wilks (original) is only used by the Wilks tool; report agreement, never fail on it.
    W = {"M": [-216.0475144, 16.2606339, -0.002388645, -0.00113732, 7.01863e-06, -1.291e-08],
         "F": [594.31747775582, -27.23842536447, 0.82112226871, -0.00930733913, 4.731582e-05, -9.054e-08]}
    werrs = []
    if "Wilks" in sample.columns:
        for sex in ("M", "F"):
            s = sample[(sample.Sex == sex) & sample.Wilks.notna()]
            x = np.clip(s.BodyweightKg.values, 40 if sex == "M" else 26.51, 201.9 if sex == "M" else 154.53)
            poly = sum(c * x**i for i, c in enumerate(W[sex]))
            werrs.append(np.abs(s.TotalKg.values * 500 / poly - s.Wilks.values))
        werrs = np.concatenate(werrs)
        report["wilks"] = {"n": int(werrs.size), "medianAbsErr": float(np.median(werrs)) if werrs.size else None}
    return report, gl_ok


def best_per_lifter(df, col):
    d = df[(df[col] > 0) & df.BodyweightKg.notna()]
    idx = d.groupby(["Name", "Sex"])[col].idxmax()
    return d.loc[idx, ["Sex", "BodyweightKg", "Age", col]]


def curve(values):
    return [round(float(v), 1) for v in np.percentile(values, PCTS)]


def bw_bins(best, col):
    """For each 5 kg bodyweight centre, widen the window until >= MIN_BIN lifters."""
    bw = best.BodyweightKg.values
    val = best[col].values
    order = np.argsort(bw)
    bw, val = bw[order], val[order]
    out = []
    for i, c in enumerate(BW_CENTERS):
        open_top = i == len(BW_CENTERS) - 1
        half = 2.5
        while True:
            lo = c - half
            hi = np.inf if open_top else c + half
            l, r = np.searchsorted(bw, lo), np.searchsorted(bw, hi)
            if r - l >= MIN_BIN or half > 25:
                break
            half += 2.5
        if r - l < 50:
            continue
        out.append({"bw": c, "lo": round(lo, 1), "hi": None if open_top else round(hi, 1),
                    "n": int(r - l), "p": curve(val[l:r])})
    return out


def population(df):
    raw = df[df.Equipment == "Raw"]
    full = raw[raw.Event == "SBD"]
    res = {}
    for sex in ("M", "F"):
        r, fp = raw[raw.Sex == sex], full[full.Sex == sex]
        lifts = {}
        for key, col, src in [("squat", "Best3SquatKg", r), ("bench", "Best3BenchKg", r),
                              ("deadlift", "Best3DeadliftKg", r), ("total", "TotalKg", fp)]:
            best = best_per_lifter(src, col)
            lifts[key] = {"n": int(len(best)), "bins": bw_bins(best, col)}
        d = best_per_lifter(fp[fp.Dots.notna()], "Dots")
        bands = []
        for lo, hi in AGE_BANDS:
            b = d[(d.Age >= lo) & (d.Age <= hi)]
            if len(b) >= 200:
                bands.append({"lo": lo, "hi": hi, "n": int(len(b)), "p": curve(b.Dots.values)})
        res[sex] = {"lifts": lifts,
                    "dots": {"all": {"n": int(len(d)), "p": curve(d.Dots.values)}, "ageBands": bands}}
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    df, data_date = load(args.zip)
    df = df[df.Sex.isin(["M", "F"])]
    print(f"Loaded {len(df):,} rows (data {data_date})")

    report, gl_ok = validate(df)
    print("Validation:", json.dumps(report))

    out = {
        "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "dataDate": data_date,
        "source": "OpenPowerlifting (openpowerlifting.org), public domain",
        "percentiles": list(map(int, PCTS)),
        "formulas": {
            "dots": {"M": DOTS["M"], "F": DOTS["F"],
                     "bw": {"M": list(DOTS_BW["M"]), "F": list(DOTS_BW["F"])}},
            "goodlift": GL if gl_ok else None,
        },
        "validation": report,
        "populations": {
            "all": population(df),
            "tested": population(df[df.Tested == "Yes"]),
        },
    }
    with open(args.out, "w") as f:
        json.dump(out, f, separators=(",", ":"))
    m = out["populations"]["all"]["M"]
    print(f"Wrote {args.out}. Raw male lifters: squat {m['lifts']['squat']['n']:,}, "
          f"bench {m['lifts']['bench']['n']:,}, deadlift {m['lifts']['deadlift']['n']:,}")


if __name__ == "__main__":
    main()
