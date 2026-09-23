# IronLog

A personal strength-training tracker for iPhone (SwiftUI + SwiftData, iOS 17+), built in the cloud by GitHub Actions so no Mac is needed.

## Features

| Area | What it does |
|---|---|
| Strength Score | One number (0–600) across all your lifts, normalised for bodyweight and sex, compared to training age, decaying after 3+ weeks off. Six levels (Beginner → World Class), front/back body map lit per muscle group, per-lift progress to the next level, score history. |
| Competition data | Squat/bench/deadlift and DOTS percentiles against **real OpenPowerlifting results** (by sex, bodyweight, age band; all raw or drug-tested only), IPF GL. |
| Tools | Strength level checker, 1RM (7 formulas + RIR), RPE chart/planner, % chart + Prilepin, warm-up ramps, plate calculator (kg/lb, reverse count), training volume (MEV/MRV, prefilled from your log), DOTS, Wilks (original + 2020), body fat (Navy, JP3 skinfolds, BMI), lean body mass (4 formulas), FFMI, ideal weight, BMR (4 equations), TDEE, protein, macros, bulking, recomp. |
| Workout tracking | Fast set logging, "previous" column, smart defaults from last session, warm-up sets, rest timer with lock-screen notification, automatic PR detection (weight, e1RM, reps-at-weight). |
| Adaptive routines | Templates plus a custom builder. Double progression adjusts weight automatically; 2 missed sessions in a row triggers a 10% deload suggestion. |
| Plan builder | Offline rule-based generator (goal, days, equipment, experience, heavy/volume periodisation). Optional Claude-generated plans with your own API key. |
| Exercise library | The 353 exercises from Stronger's library (names, muscles, compound/isolation, level, equipment), logged by type: weight × reps, bodyweight ± added/assisted load, time, cardio (time + distance), carries. Per-exercise standards table at your bodyweight. Steps/photos from free-exercise-db. Custom exercises. |
| Analytics | Per-exercise strength curves and rep records, weekly volume and frequency, activity heatmap, sets per muscle vs the 10–20 set range, recovery status, muscle-balance radar, body measurements. |
| Friends | Leaderboard by Strength Score (DOTS shown too) using share codes (no server or account). |
| Apple Health | Saves workouts, imports bodyweight. |

## How the Strength Score works

- Every scored exercise (294 of 353) maps to an **anchor lift** (bench, squat, deadlift, OHP, row, pulldown, pull-up, dip, push-up, curl, triceps, lateral raise, rear delt, leg press, leg extension, leg curl, hip thrust, calf raise, shrug, wrist curl, weighted crunch, hip machine) and a **factor** (e.g. incline bench = 0.82 × bench, dumbbell press = 0.38 × bench per hand).
- Anchors have level floors as multiples of bodyweight for an 80 kg man / 65 kg woman, scaled to your bodyweight allometrically (`floor × ref × (bw/ref)^0.67`), so lighter lifters need a higher ratio and heavier lifters a lower one.
- Your best estimated 1RM per exercise in the last year (Epley/Brzycki average up to 10 reps, Epley 11–15; bodyweight moves up to 25 reps, with bodyweight counted in the load) becomes 0–600 points: 100 per level, interpolated within the band.
- Each muscle group takes its best lift (machines/variants discounted slightly). Score = average of scored groups, shown once 3+ groups are scored. More groups → more accurate.
- A lift not trained for 21 days loses 0.75 % per week, to a floor of 80 %.
- Training age: set your start date in Profile and the score screen shows the typical score for that many years of training and how far ahead/behind you are.

Tables live in `scripts/build_exercises.py` (edit, re-run, commit). The list of exercises is in `scripts/data/catalog.txt`.

## How the real-data comparison works

The `data` job downloads the full OpenPowerlifting dataset (~4M results, public domain) and `scripts/build_reference_data.py`:

1. Keeps raw (unequipped) results only and counts each lifter once at their best.
2. Builds 1st–99th percentile curves for squat, bench, deadlift and total per sex, in 5 kg bodyweight windows (widened until each has ≥500 lifters), plus DOTS curves overall and by age band.
3. Recomputes DOTS and IPF GL for 20,000 sampled results and compares them to OpenPowerlifting's own columns. **If DOTS disagrees, the build fails.**

The app bundles the resulting `reference.json` and interpolates your e1RM on those curves.

## Setup

1. Create a GitHub repo (public = free unlimited Actions minutes; private repos burn macOS minutes at 10×).
2. Push this folder to `main`. The workflow runs automatically (~10–15 min).
3. Open **Releases** on your phone or PC and download `IronLog.ipa`.

To rebuild without HealthKit (if your sideloading tool rejects the entitlement): Actions → Build IPA → Run workflow → untick *healthkit*.

## Sideloading

The IPA is unsigned; your sideloading tool signs it with your Apple ID.

- **Sideloadly** (Windows/Mac): plug in the phone, drag the IPA in, sign in, Start.
- **AltStore / SideStore**: add the IPA from Files.

Free Apple IDs: apps expire after 7 days (re-sign/refresh to keep them), max 3 sideloaded apps. Turn on Developer Mode on the phone (Settings → Privacy & Security) and trust the profile under Settings → General → VPN & Device Management. Your data survives re-signing as long as the bundle ID stays the same.

## Local notes

- `IronLog.xcodeproj` is generated by XcodeGen from `project.yml`, don't commit it.
- `exercises.json` and `standards.json` are committed and regenerated in CI; `reference.json` is generated in CI only. To test the data script locally: `python scripts/build_reference_data.py --zip openpowerlifting-latest.zip --out reference.json`.

Data: [OpenPowerlifting](https://www.openpowerlifting.org) · [free-exercise-db](https://github.com/yuhonas/free-exercise-db)
