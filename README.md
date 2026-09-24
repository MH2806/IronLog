# IronLog

A personal strength-training tracker for iPhone (SwiftUI + SwiftData, iOS 17+), built in the cloud by GitHub Actions so no Mac is needed.

## Features

Dark, card-based UI with five tabs:

| Tab | What's in it |
|---|---|
| **Log** | Monday-first week strip (tap a day to filter), start/next-up buttons, workout cards grouped Today / This week / Last week / by month with PB count, muscle tags, volume · reps and a one-tap **repeat**. Workout detail with a body diagram of muscles worked. |
| **Train** | *Workouts*: your saved routine days + a 17-workout library (Push/Pull/Legs/Upper/Lower/Full body/Arms/Shoulders/Core) with exercises, ~minutes, level and a play button. *Routines*: your adaptive routines + proven templates. *Coach*: recovery ring, a suggested workout picked from what's recovered, next routine day, plan builder (rule-based or Claude). |
| **Progress** | *Analytics → Overview*: strength-profile ring (0–100, rank, points to next rank, DOTS percentile, expandable body map), lift carousel with e1RM, change and sparklines, muscle readiness, Total Lifted with milestones (piano → Boeing 747 → Titanic), badge case, journey stats, training split vs your usual split with a tip. *This week*: comparisons with last week, body heat map of sets, PRs. *Trends*: score history, weekly volume, frequency, key lifts. *Exercises*: search, muscle-diagram filters, My lifts (e1RM, change, sparkline, 🔥 for PRs this week) / All exercises. *Bodyweight*: chart, log, Health import. |
| **Community** | Podium + leaderboard by Strength Score via share codes (no server), competition comparison. |
| **Profile** | Rank, stats, activity heatmap (26 weeks), streak, this-week tiles, Strength Score and Recovery links, badges (36+), calculators, Edit profile (settings). |

Other screens: **Strength Score** (rank badge, 18 ranks Beginner I → World Class III, percentile bell curve, muscle map, climb-the-ranks, per-muscle and per-lift ranks, history, training age), **Recovery** (0–100 readiness from muscle recovery, training load vs 4-week average and, with the HealthKit build, sleep + resting HR; body map by readiness), **Exercise detail** (Overview with rank + standards + muscle diagram + records + steps, Charts for max weight / e1RM / set volume / reps with 1M·3M·6M·All and % vs first record, History).

Under the hood: fast set logging with previous values, warm-ups, rest timer notifications, PR detection, double progression with deload suggestions, 353 exercises with tracking types, 19 calculators, JSON export, Apple Health (workouts, bodyweight, sleep, resting HR).

Artwork is IronLog's own (body diagram paths, hexagon rank badges, SF Symbols); nothing is copied from Stronger.

## How the Strength Score works

- Every scored exercise (294 of 353) maps to an **anchor lift** (bench, squat, deadlift, OHP, row, pulldown, pull-up, dip, push-up, curl, triceps, lateral raise, rear delt, leg press, leg extension, leg curl, hip thrust, calf raise, shrug, wrist curl, weighted crunch, hip machine) and a **factor** (e.g. incline bench = 0.82 × bench, dumbbell press = 0.38 × bench per hand).
- Anchors have level floors as multiples of bodyweight for an 80 kg man / 65 kg woman, scaled to your bodyweight allometrically (`floor × ref × (bw/ref)^0.67`), so lighter lifters need a higher ratio and heavier lifters a lower one.
- Your best estimated 1RM per exercise in the last year (Epley/Brzycki average up to 10 reps, Epley 11–15; bodyweight moves up to 25 reps, with bodyweight counted in the load) becomes 0–600 internal points (100 per level, interpolated within the band). The app shows this as a 0–100 score (points ÷ 6), and each level is split into I / II / III, giving 18 ranks.
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
