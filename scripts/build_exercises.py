#!/usr/bin/env python3
"""
Builds IronLog/Resources/exercises.json and standards.json.

- Exercise list: scripts/data/catalog.txt (353 exercises, names + muscles/mechanic/level/equipment).
- Instructions + photos: matched from free-exercise-db (public domain) only where the match is confident.
- Strength standards: each scored exercise maps to an anchor lift and a factor. Anchor lifts have
  level floors (Novice..World Class) as multiples of bodyweight for a reference lifter
  (80 kg men / 65 kg women), scaled allometrically for other bodyweights in the app.

Run: python scripts/build_exercises.py   (re-run whenever catalog.txt or the tables below change)
"""
import difflib
import json
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "scripts", "data", "catalog.txt")
OUT_DIR = os.path.join(ROOT, "IronLog", "Resources")
FEDB_URL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"

# ------------------------------------------------------------------ anchors
# Level floors (Novice, Intermediate, Advanced, Elite, World Class) as x bodyweight
# at the reference bodyweight. Beginner starts at 0. "load" = what the e1RM measures:
#   external = weight on the bar/stack/per dumbbell (as logged)
#   total    = bodyweight share + added weight (pull-ups, dips, push-ups)
ANCHORS = {
    "bench":      {"M": [0.55, 0.80, 1.15, 1.50, 1.85], "F": [0.30, 0.50, 0.75, 1.00, 1.30]},
    "squat":      {"M": [0.75, 1.15, 1.60, 2.10, 2.60], "F": [0.50, 0.80, 1.15, 1.50, 1.90]},
    "deadlift":   {"M": [0.95, 1.40, 1.90, 2.40, 2.90], "F": [0.60, 1.00, 1.35, 1.75, 2.20]},
    "ohp":        {"M": [0.35, 0.55, 0.75, 0.95, 1.20], "F": [0.20, 0.35, 0.50, 0.65, 0.85]},
    "row":        {"M": [0.50, 0.75, 1.00, 1.30, 1.60], "F": [0.30, 0.50, 0.70, 0.90, 1.10]},
    "pulldown":   {"M": [0.50, 0.75, 1.00, 1.25, 1.50], "F": [0.30, 0.50, 0.70, 0.90, 1.10]},
    "pullup":     {"M": [0.85, 1.05, 1.30, 1.60, 1.90], "F": [0.55, 0.75, 1.00, 1.25, 1.50], "load": "total"},
    "dip":        {"M": [0.90, 1.15, 1.45, 1.80, 2.10], "F": [0.60, 0.85, 1.10, 1.35, 1.65], "load": "total"},
    "pushup":     {"M": [0.75, 0.95, 1.20, 1.45, 1.75], "F": [0.45, 0.60, 0.80, 1.00, 1.25], "load": "total"},
    "curl":       {"M": [0.20, 0.35, 0.55, 0.75, 0.95], "F": [0.10, 0.20, 0.35, 0.50, 0.65]},
    "triceps":    {"M": [0.20, 0.35, 0.55, 0.75, 0.95], "F": [0.10, 0.20, 0.35, 0.50, 0.65]},
    "lateral":    {"M": [0.06, 0.12, 0.20, 0.28, 0.36], "F": [0.03, 0.06, 0.11, 0.16, 0.21]},
    "reardelt":   {"M": [0.15, 0.25, 0.40, 0.55, 0.70], "F": [0.08, 0.15, 0.25, 0.35, 0.45]},
    "legpress":   {"M": [1.00, 1.75, 2.50, 3.50, 4.50], "F": [0.70, 1.20, 1.80, 2.50, 3.30]},
    "legext":     {"M": [0.40, 0.65, 0.95, 1.25, 1.60], "F": [0.25, 0.45, 0.70, 0.95, 1.20]},
    "legcurl":    {"M": [0.30, 0.50, 0.75, 1.00, 1.30], "F": [0.20, 0.35, 0.55, 0.75, 1.00]},
    "hipthrust":  {"M": [0.75, 1.25, 1.80, 2.40, 3.00], "F": [0.60, 1.00, 1.50, 2.10, 2.70]},
    "calf":       {"M": [0.50, 1.00, 1.50, 2.10, 2.70], "F": [0.35, 0.70, 1.10, 1.50, 2.00]},
    "shrug":      {"M": [0.60, 1.00, 1.40, 1.85, 2.30], "F": [0.35, 0.60, 0.90, 1.20, 1.50]},
    "wrist":      {"M": [0.15, 0.30, 0.45, 0.60, 0.80], "F": [0.08, 0.16, 0.28, 0.40, 0.55]},
    "crunch":     {"M": [0.30, 0.50, 0.75, 1.00, 1.30], "F": [0.20, 0.35, 0.55, 0.75, 1.00]},
    "hipmachine": {"M": [0.40, 0.70, 1.00, 1.30, 1.60], "F": [0.35, 0.60, 0.90, 1.20, 1.50]},
}

# slug -> (anchor, factor, confidence). Key lifts have confidence 1.0.
S = {}
def std(anchor, conf, **items):
    for slug, f in items.items():
        S[slug.replace("_", "-")] = (anchor, f, conf)

std("bench", 1.0, barbell_bench_press=1.0)
std("bench", 0.9, wide_grip_barbell_bench_press=0.98, close_grip_bench_press=0.9, incline_bench_press=0.82,
    decline_bench_press=1.05, reverse_grip_barbell_bench_press=0.9, barbell_larsen_press=0.92,
    barbell_guillotine_press=0.75, incline_close_grip_barbell_bench_press=0.75, smith_machine_bench=1.0,
    decline_smith_machine_bench=1.05, incline_smith_machine_bench=0.82, wide_grip_smith_machine_bench_press=0.98,
    close_grip_smith_machine_bench_press=0.9, incline_close_grip_smith_machine_bench_press=0.75,
    dumbbell_press=0.38, incline_dumbbell_press=0.33, decline_dumbbell_press=0.40, dumbbell_larsen_press=0.34,
    dumbbell_hex_press=0.30, barbell_jm_press=0.65, smith_machine_jm_press=0.65)
std("bench", 0.75, iso_lateral_chest_press=1.0, iso_lateral_decline_chest_press=1.05, iso_lateral_incline_chest_press=0.85,
    seated_chest_press_machine=0.9, machine_dip=1.2, plate_loaded_machine_dip=1.2, cable_chest_press=0.5,
    seated_cable_chest_press=0.6, incline_cable_press=0.5, dumbbell_fly=0.2, incline_dumbbell_fly=0.18,
    decline_dumbbell_fly=0.22, cable_crossover=0.2, cable_fly_high_to_low=0.18, cable_fly_low_to_high=0.15,
    pec_deck_machine=0.6)

std("squat", 1.0, barbell_back_squat=1.0)
std("squat", 0.9, barbell_box_squat=0.95, barbell_front_squat=0.82, zercher_squat=0.8, smith_machine_squat=1.0,
    belt_squat=1.0, hack_squat=1.1, pendulum_squat=0.9, landmine_squat=0.5, goblet_squat=0.35, dumbbell_squat=0.3,
    barbell_bulgarian_split_squat=0.55, barbell_split_squat=0.6, barbell_reverse_lunge=0.6,
    barbell_walking_lunge=0.55, bulgarian_split_squat=0.25, dumbbell_split_squat=0.27, dumbbell_lunge=0.27,
    dumbbell_reverse_lunge=0.27, dumbbell_walking_lunge=0.25, dumbbell_front_elevated_split_squat=0.25,
    dumbbell_step_up=0.22, kettlebell_front_lunge=0.25, kettlebell_reverse_lunge=0.27, smith_machine_lunge=0.6,
    smith_machine_split_squat=0.6, smith_machine_rear_elevated_split_squat=0.55,
    smith_machine_front_elevated_split_squat=0.6)
std("legpress", 0.85, leg_press=1.0, machine_leg_press=1.0, single_leg_leg_press=0.5)
std("legext", 0.8, leg_extension=1.0, single_leg_leg_extension=0.5)

std("deadlift", 1.0, deadlift=1.0)
std("deadlift", 0.9, sumo_deadlift=1.0, trap_bar_deadlift=1.05, barbell_rack_pull=1.15, barbell_rdl=0.75,
    stiff_legged_deadlift=0.7, good_morning=0.5, smith_machine_good_morning=0.5, clean=0.55, snatch=0.42,
    dumbbell_rdl=0.3, kettlebell_deadlift=0.4, kettlebell_rdl=0.3, single_leg_dumbbell_rdl=0.15, cable_rdl=0.4)
std("hipthrust", 0.85, hip_thrust=1.0, barbell_glute_bridge=0.9, barbell_kas_glute_bridge=0.8,
    smith_machine_hip_thrust=1.0, dumbbell_hip_thrust=0.35, dumbbell_glute_bridge=0.3, dumbbell_kas_glute_bridge=0.3)
std("legcurl", 0.8, leg_curl=1.0, lying_leg_curl=1.0, seated_single_leg_leg_curl=0.5, standing_single_leg_leg_curl=0.4)

std("ohp", 1.0, military_press=1.0)
std("ohp", 0.9, seated_barbell_overhead_press=0.95, behind_the_back_barbell_overhead_press=0.9, barbell_z_press=0.85,
    barbell_push_press=1.2, clean_press=0.95, smith_machine_shoulder_press=1.0, landmine_press=0.6,
    single_arm_landmine_press=0.35, dumbbell_shoulder_press=0.38, arnold_press=0.33, dumbbell_push_press=0.45,
    dumbbell_z_press=0.32, kettlebell_military_press=0.35, upright_row=0.75, barbell_upright_row=0.75,
    dumbbell_upright_row=0.3, kettlebell_upright_row=0.35)
std("ohp", 0.75, iso_lateral_shoulder_press=1.0, shoulder_press_machine=0.9, neutral_grip_machine_shoulder_press=0.9,
    cable_shoulder_press=0.5, cable_upright_row=0.6)
std("lateral", 0.85, dumbbell_lateral_raise=1.0, seated_lateral_raise=0.9, incline_side_lateral_raise=0.8,
    cable_lateral_raise=0.8, high_cable_lateral_raise=0.7, dumbbell_front_raise=1.1, seated_dumbbell_front_raise=1.0,
    incline_dumbbell_front_raise=0.9, cable_front_raise=1.0, barbell_front_raise=2.2, plate_front_raise=2.0,
    dumbbell_incline_y_raise=0.6, cable_standing_y_raise=0.6, cuffed_cable_seated_y_raise=0.6)
std("lateral", 0.7, lateral_raise_machine=3.0, plate_loaded_machine_lateral_raise=3.0)
std("reardelt", 0.8, face_pull=1.0, cable_rear_delt_fly=0.4, dumbbell_rear_delt_fly=0.35, rear_delt_fly_machine=1.2,
    dumbbell_face_pull=0.35)

std("row", 1.0, barbell_row=1.0)
std("row", 0.9, pendlay_row=0.95, reverse_grip_barbell_row=1.0, t_bar_row=1.0, bent_over_t_bar_row=0.9,
    bent_over_underhand_grip_t_bar_row=0.9, underhand_grip_t_bar_row=0.9, neutral_grip_t_bar_row=0.9,
    barbell_incline_row=0.8, smith_machine_row=1.0, dumbbell_row=0.45, dumbbell_one_arm_row=0.5,
    chest_supported_dumbbell_row=0.38, incline_dumbbell_row=0.38, kettlebell_row=0.4, single_arm_kettlebell_row=0.45,
    cable_row=1.0, close_neutral_grip_cable_row=1.0, seated_row_machine=1.0, single_arm_cable_row=0.5)
std("row", 0.75, iso_lateral_row_machine=1.0, iso_lateral_low_row=1.0, iso_lateral_high_row=1.0,
    neutral_grip_seated_machine_row=1.0, underhand_grip_seated_machine_row=1.0)
std("pulldown", 1.0, pulldown=1.0)
std("pulldown", 0.9, neutral_grip_pulldown=1.0, neutral_close_grip_pulldown=1.0, close_grip_pulldown=1.0,
    reverse_grip_pulldown=1.0, single_arm_lat_pulldown=0.5, dumbbell_pullover=0.35, barbell_pullover=0.45,
    ez_bar_pullover=0.45, bar_pullover=0.45, cable_pullover=0.5, rope_pullover=0.5)
std("pulldown", 0.75, iso_lateral_pulldown=1.0, iso_lateral_close_grip_pulldown=1.0, iso_lateral_wide_pulldown=1.0,
    machine_pullover=0.8)
std("pullup", 1.0, pull_up=1.0, weighted_pull_up=1.0)
std("pullup", 0.9, chin_up=1.05, close_grip_chin_up=1.05, close_grip_pull_up=1.0, wide_grip_pull_up=0.95,
    wide_grip_chin_up=1.0, assisted_pull_up=1.0, assisted_chin_up=1.05, band_assisted_pull_up=1.0,
    band_assisted_chin_up=1.05)
std("dip", 0.9, dips=1.0, weighted_dips=1.0, assisted_dip=1.0)
std("pushup", 0.7, push_up=1.0, wide_grip_push_up=1.0, close_grip_push_up=0.9, diamond_push_up=0.9,
    decline_push_up=1.0)

std("curl", 1.0, barbell_bicep_curl=1.0)
std("curl", 0.9, ez_bar_curl=1.0, close_grip_ez_bar_curl=0.95, ez_bar_preacher_curl=0.85, barbell_drag_curl=0.85,
    dumbbell_bicep_curl=0.45, hammer_curl=0.5, seated_dumbbell_bicep_curl=0.43, seated_dumbbell_hammer_curl=0.48,
    incline_dumbbell_curl=0.38, incline_hammer_curl=0.4, dumbbell_incline_hammer_curl=0.4, dumbbell_preacher_curl=0.38,
    dumbbell_preacher_hammer_curl=0.4, concentration_curl=0.4, spider_curl=0.35, dumbbell_zottman_curl=0.4,
    seated_dumbbell_zottman_curl=0.4, kettlebell_bicep_curl=0.45, cable_curl=1.0, bar_cable_curl=1.0,
    seated_cable_curl=0.9, face_away_cable_curl=0.4, cable_concentration_curl=0.45, cable_hammer_curl=0.5,
    rope_hammer_curl=1.0, preacher_curl_machine=0.9, reverse_barbell_curl=0.7, reverse_ez_bar_curl=0.7,
    reverse_ez_bar_preacher_curl=0.6, reverse_dumbbell_curl=0.32, seated_reverse_dumbbell_curl=0.3,
    reverse_cable_curl=0.7, reverse_single_arm_cable_curl=0.35)
std("wrist", 0.8, barbell_wrist_curl=1.0, wrist_curl=1.0, ez_bar_wrist_curl=1.0, cable_wrist_curl=0.9,
    barbell_wrist_extension=0.6, ez_bar_wrist_extension=0.6, dumbbell_wrist_extension=0.3,
    barbell_standing_back_wrist_curl=1.1, ez_bar_standing_back_wrist_curl=1.1, dumbbell_standing_back_wrist_curl=0.5,
    cable_standing_back_wrist_curl=1.0, reverse_cable_wrist_curl=0.6)
std("triceps", 1.0, bar_pushdown=1.0)
std("triceps", 0.9, rope_pushdown=0.85, cable_straight_bar_pushdown=1.0, cable_v_bar_pushdown=1.0, cable_kickback=0.3,
    cable_single_arm_extension=0.45, cable_cuffed_single_arm_tricep_extension=0.4, katana_extension=0.4,
    rope_overhead_tricep_extension=0.85, rope_overhead_extension=0.85, cable_dual_overhead_tricep_extension=0.8,
    cable_straight_bar_overhead_tricep_extension=0.9, cable_single_arm_overhead_tricep_extension=0.4,
    barbell_overhead_tricep_extension=0.9, barbell_skullcrusher=1.0, ez_bar_skullcrusher=1.0,
    dumbbell_skullcrusher=0.4, dumbbell_tricep_extension=0.8, tricep_extension=0.8, dumbbell_kickback=0.25,
    machine_tricep_extension=1.0, machine_overhead_tricep_extension=1.0)
std("shrug", 0.85, barbell_shrug=1.0, barbell_behind_the_back_shrug=0.9, smith_machine_shrug=1.0,
    smith_machine_behind_the_back_shrug=0.9, dumbbell_shrug=0.45, kettlebell_shrug=0.4, cable_shrug=0.8,
    dumbbell_kelso_shrug=0.3, machine_row_kelso_shrug=0.8)
std("calf", 0.85, standing_machine_calf_raise=1.0, calf_raises=1.0, barbell_calf_raise=0.8, smith_machine_calf_raise=0.9,
    elevated_smith_machine_calf_raise=0.9, hack_squat_calf_raise=1.0, machine_leg_press_calf_raise=1.3,
    seated_machine_calf_raise=0.7, seated_single_leg_machine_calf_raise=0.35, standing_dumbbell_calf_raise=0.25)
std("crunch", 0.8, cable_crunch=1.0, standing_cable_crunch=0.9, machine_crunch=1.0, cable_side_crunch=0.5)
std("hipmachine", 0.7, hip_abductor=1.0, hip_adductor=1.0)

# ------------------------------------------------------------------ tracking
CARDIO = {"assault-bike", "elliptical", "exercise-bike", "rowing-machine", "ski-ergometer", "stairmaster", "treadmill"}
DURATION = {"plank", "reverse-plank", "l-sit", "dead-hang", "mountain-climber"}
DISTANCE = {"farmer-carry", "kettlebell-farmer-carry"}
ASSISTED = {"assisted-chin-up", "assisted-dip", "assisted-pull-up", "band-assisted-chin-up", "band-assisted-pull-up"}
# share of bodyweight moved, for bodyweight exercises (added weight is logged on top)
BODYWEIGHT = {
    "archer-pull-up": 1.0, "chin-up": 1.0, "close-grip-chin-up": 1.0, "close-grip-pull-up": 1.0, "pull-up": 1.0,
    "wide-grip-chin-up": 1.0, "wide-grip-pull-up": 1.0, "weighted-pull-up": 1.0, "muscle-up": 1.0,
    "dips": 1.0, "weighted-dips": 1.0, "bench-dip": 0.6, "weighted-bench-dip": 0.6,
    "push-up": 0.64, "close-grip-push-up": 0.64, "diamond-push-up": 0.64, "wide-grip-push-up": 0.64,
    "decline-push-up": 0.70, "incline-push-up": 0.45, "kneeling-push-up": 0.49, "pike-push-up": 0.7,
    "handstand-push-up": 0.9, "barbell-inverted-row": 0.6, "bodyweight-pistol-squat": 0.9, "lunge": 0.8,
    "sissy-squat": 0.7, "nordic-curl": 0.6, "hyperextension": 0.5, "bodyweight-glute-bridge": 0.5,
    "single-leg-bodyweight-glute-bridge": 0.5, "single-leg-bodyweight-hip-thrust": 0.5, "donkey-kick": 0.2,
    "bodyweight-elevated-calf-raise": 1.0, "glute-ham-raise": 0.6, "crunch": 0.3, "bicycle-crunch": 0.3,
    "sit-up": 0.4, "decline-sit-up": 0.45, "leg-raise": 0.3, "reverse-crunch": 0.3, "russian-twist": 0.3,
    "weighted-russian-twist": 0.3, "hanging-knee-raise": 0.3, "captains-chair-knee-raise": 0.3,
    "captains-chair-leg-raise": 0.35, "glute-ham-raise-sit-up": 0.45, "wheel-rollout": 0.5,
    "standing-wheel-rollout": 0.7, "barbell-rollout": 0.5, "standing-barbell-rollout": 0.7,
}
ASSIST_SHARE = {"assisted-dip": 1.0}

def tracking(slug):
    if slug in CARDIO: return "cardio"
    if slug in DURATION: return "duration"
    if slug in DISTANCE: return "weightDistance"
    if slug in ASSISTED: return "assistedReps"
    if slug in BODYWEIGHT: return "bodyweightReps"
    return "weightReps"

def secondary(slug, primary, mech):
    s = set()
    if mech == "compound":
        if "chest" in primary: s |= {"triceps", "shoulders"}
        if "shoulders" in primary and ("press" in slug or "push" in slug): s |= {"triceps"}
        if ("row" in slug or "pulldown" in slug or "pull-up" in slug or "chin" in slug) and "upright" not in slug:
            s |= {"biceps", "forearms"}
        if "quadriceps" in primary: s |= {"glutes"}
        if "deadlift" in slug or "rack-pull" in slug: s |= {"forearms", "traps", "lats"}
        if "rdl" in slug or "good-morning" in slug or "stiff" in slug: s |= {"glutes", "back"}
        if "hip-thrust" in slug or "glute-bridge" in slug: s |= {"hamstrings"}
    return sorted(s - set(primary))

def norm(name):
    n = name.lower().replace("-", " ").replace("_", " ")
    n = re.sub(r"\s+", " ", n).strip()
    return n

# Hand-checked pairings to free-exercise-db ids for exact-movement matches.
ALIASES = {
    "barbell-back-squat": "Barbell_Squat", "barbell-bench-press": "Barbell_Bench_Press_-_Medium_Grip",
    "deadlift": "Barbell_Deadlift", "military-press": "Standing_Military_Press", "barbell-row": "Bent_Over_Barbell_Row",
    "pull-up": "Pullups", "chin-up": "Chin-Up", "push-up": "Pushups", "dips": "Dips_-_Triceps_Version",
    "barbell-bicep-curl": "Barbell_Curl", "hammer-curl": "Hammer_Curls", "dumbbell-bicep-curl": "Dumbbell_Bicep_Curl",
    "leg-press": "Leg_Press", "leg-extension": "Leg_Extensions", "lying-leg-curl": "Lying_Leg_Curls",
    "leg-curl": "Lying_Leg_Curls", "hip-thrust": "Barbell_Hip_Thrust", "barbell-glute-bridge": "Barbell_Glute_Bridge",
    "barbell-rdl": "Romanian_Deadlift", "stiff-legged-deadlift": "Stiff-Legged_Barbell_Deadlift",
    "sumo-deadlift": "Sumo_Deadlift", "trap-bar-deadlift": "Trap_Bar_Deadlift", "good-morning": "Good_Morning",
    "barbell-front-squat": "Front_Barbell_Squat", "goblet-squat": "Goblet_Squat", "dumbbell-squat": "Dumbbell_Squat",
    "dumbbell-lunge": "Dumbbell_Lunges", "dumbbell-rdl": "Stiff-Legged_Dumbbell_Deadlift",
    "incline-bench-press": "Barbell_Incline_Bench_Press_-_Medium_Grip", "decline-bench-press": "Decline_Barbell_Bench_Press",
    "close-grip-bench-press": "Close-Grip_Barbell_Bench_Press", "wide-grip-barbell-bench-press": "Wide-Grip_Barbell_Bench_Press",
    "barbell-guillotine-press": "Barbell_Guillotine_Bench_Press", "dumbbell-press": "Dumbbell_Bench_Press",
    "incline-dumbbell-press": "Incline_Dumbbell_Press", "decline-dumbbell-press": "Decline_Dumbbell_Bench_Press",
    "dumbbell-fly": "Dumbbell_Flyes", "incline-dumbbell-fly": "Incline_Dumbbell_Flyes", "decline-dumbbell-fly": "Decline_Dumbbell_Flyes",
    "cable-crossover": "Cable_Crossover", "pec-deck-machine": "Butterfly", "dumbbell-shoulder-press": "Dumbbell_Shoulder_Press",
    "arnold-press": "Arnold_Dumbbell_Press", "seated-barbell-overhead-press": "Seated_Barbell_Military_Press",
    "barbell-push-press": "Push_Press", "dumbbell-lateral-raise": "Side_Lateral_Raise", "seated-lateral-raise": "Seated_Side_Lateral_Raise",
    "dumbbell-front-raise": "Front_Dumbbell_Raise", "face-pull": "Face_Pull", "dumbbell-rear-delt-fly": "Seated_Bent-Over_Rear_Delt_Raise",
    "upright-row": "Upright_Barbell_Row", "barbell-upright-row": "Upright_Barbell_Row", "dumbbell-upright-row": "Standing_Dumbbell_Upright_Row",
    "barbell-shrug": "Barbell_Shrug", "dumbbell-shrug": "Dumbbell_Shrug", "barbell-behind-the-back-shrug": "Barbell_Shrug_Behind_The_Back",
    "smith-machine-behind-the-back-shrug": "Smith_Machine_Behind_the_Back_Shrug", "pendlay-row": "Bent_Over_Barbell_Row",
    "t-bar-row": "T-Bar_Row_with_Handle", "dumbbell-one-arm-row": "One-Arm_Dumbbell_Row", "dumbbell-row": "Bent_Over_Two-Dumbbell_Row",
    "cable-row": "Seated_Cable_Rows", "seated-row-machine": "Seated_Cable_Rows", "pulldown": "Wide-Grip_Lat_Pulldown",
    "close-grip-pulldown": "Close-Grip_Front_Lat_Pulldown", "reverse-grip-pulldown": "Underhand_Cable_Pulldowns",
    "single-arm-lat-pulldown": "One_Arm_Lat_Pulldown", "wide-grip-pull-up": "Wide-Grip_Rear_Pull-Up",
    "dumbbell-pullover": "Bent-Arm_Dumbbell_Pullover", "barbell-pullover": "Bent-Arm_Barbell_Pullover",
    "rope-pushdown": "Triceps_Pushdown_-_Rope_Attachment", "bar-pushdown": "Triceps_Pushdown",
    "cable-v-bar-pushdown": "Triceps_Pushdown_-_V-Bar_Attachment", "cable-straight-bar-pushdown": "Triceps_Pushdown",
    "rope-overhead-tricep-extension": "Cable_Rope_Overhead_Triceps_Extension",
    "rope-overhead-extension": "Cable_Rope_Overhead_Triceps_Extension", "barbell-skullcrusher": "Lying_Triceps_Press",
    "ez-bar-skullcrusher": "EZ-Bar_Skullcrusher", "dumbbell-kickback": "Tricep_Dumbbell_Kickback",
    "tricep-extension": "Standing_Dumbbell_Triceps_Extension", "dumbbell-tricep-extension": "Standing_Dumbbell_Triceps_Extension",
    "ez-bar-curl": "EZ-Bar_Curl", "ez-bar-preacher-curl": "Preacher_Curl", "concentration-curl": "Concentration_Curls",
    "incline-dumbbell-curl": "Incline_Dumbbell_Curl", "spider-curl": "Spider_Curl", "dumbbell-zottman-curl": "Zottman_Curl",
    "cable-curl": "Standing_Biceps_Cable_Curl", "bar-cable-curl": "Standing_Biceps_Cable_Curl",
    "cable-hammer-curl": "Cable_Hammer_Curls_-_Rope_Attachment", "rope-hammer-curl": "Cable_Hammer_Curls_-_Rope_Attachment",
    "reverse-barbell-curl": "Reverse_Barbell_Curl", "reverse-cable-curl": "Reverse_Cable_Curl",
    "barbell-wrist-curl": "Palms-Up_Barbell_Wrist_Curl_Over_A_Bench", "wrist-curl": "Palms-Up_Barbell_Wrist_Curl_Over_A_Bench",
    "barbell-wrist-extension": "Palms-Down_Wrist_Curl_Over_A_Bench", "barbell-standing-back-wrist-curl": "Standing_Palms-Up_Barbell_Behind_The_Back_Wrist_Curl",
    "calf-raises": "Standing_Calf_Raises", "standing-machine-calf-raise": "Standing_Calf_Raises",
    "seated-machine-calf-raise": "Seated_Calf_Raise", "barbell-calf-raise": "Standing_Barbell_Calf_Raise",
    "smith-machine-calf-raise": "Smith_Machine_Calf_Raise", "machine-leg-press-calf-raise": "Calf_Press_On_The_Leg_Press_Machine",
    "standing-dumbbell-calf-raise": "Standing_Dumbbell_Calf_Raise", "hack-squat": "Hack_Squat", "smith-machine-squat": "Smith_Machine_Squat",
    "smith-machine-bench": "Smith_Machine_Bench_Press", "incline-smith-machine-bench": "Smith_Machine_Incline_Bench_Press",
    "decline-smith-machine-bench": "Smith_Machine_Decline_Press", "close-grip-smith-machine-bench-press": "Smith_Machine_Close-Grip_Bench_Press",
    "smith-machine-shoulder-press": "Smith_Machine_Overhead_Shoulder_Press", "smith-machine-row": "Smith_Machine_Bent_Over_Row",
    "smith-machine-hip-thrust": "Smith_Machine_Hip_Raise",
    "cable-crunch": "Cable_Crunch", "machine-crunch": "Ab_Crunch_Machine", "crunch": "Crunches", "plank": "Plank",
    "sit-up": "Sit-Up", "decline-sit-up": "Decline_Crunch", "russian-twist": "Russian_Twist", "hanging-knee-raise": "Hanging_Leg_Raise",
    "leg-raise": "Flat_Bench_Lying_Leg_Raise", "reverse-crunch": "Reverse_Crunch", "bicycle-crunch": "Air_Bike",
    "mountain-climber": "Mountain_Climbers", "wheel-rollout": "Ab_Roller", "barbell-rollout": "Barbell_Ab_Rollout",
    "standing-barbell-rollout": "Barbell_Ab_Rollout", "hyperextension": "Hyperextensions_Back_Extensions",
    "glute-ham-raise": "Glute_Ham_Raise", "nordic-curl": "Natural_Glute_Ham_Raise", "farmer-carry": "Farmers_Walk",
    "bulgarian-split-squat": "Split_Squat_with_Dumbbells", "dumbbell-split-squat": "Split_Squat_with_Dumbbells",
    "dumbbell-step-up": "Dumbbell_Step_Ups", "dumbbell-reverse-lunge": "Dumbbell_Rear_Lunge", "barbell-walking-lunge": "Barbell_Walking_Lunge",
    "barbell-reverse-lunge": "Elevated_Back_Lunge", "lunge": "Bodyweight_Walking_Lunge", "bodyweight-pistol-squat": "Kettlebell_Pistol_Squat",
    "zercher-squat": "Zercher_Squats", "barbell-box-squat": "Box_Squat", "landmine-press": "Landmine_Linear_Jammer",
    "clean": "Power_Clean", "snatch": "Power_Snatch", "clean-press": "Clean_and_Press", "hip-abductor": "Thigh_Abductor",
    "hip-adductor": "Thigh_Adductor", "cable-hip-abductor": "Cable_Hip_Adduction", "donkey-kick": "Glute_Kickback",
    "cable-glute-kickback": "One-Legged_Cable_Kickback", "bodyweight-glute-bridge": "Butt_Lift_Bridge",
    "diamond-push-up": "Push-Ups_-_Close_Triceps_Position", "close-grip-push-up": "Push-Ups_-_Close_Triceps_Position",
    "decline-push-up": "Decline_Push-Up", "incline-push-up": "Incline_Push-Up", "wide-grip-push-up": "Push-Up_Wide",
    "handstand-push-up": "Handstand_Push-Ups", "bench-dip": "Bench_Dips", "barbell-inverted-row": "Inverted_Row",
    "muscle-up": "Muscle_Up", "weighted-pull-up": "Weighted_Pull_Ups", "band-assisted-pull-up": "Band_Assisted_Pull-Up",
    "chest-supported-dumbbell-row": "Dumbbell_Incline_Row", "incline-dumbbell-row": "Dumbbell_Incline_Row",
    "kettlebell-row": "One-Arm_Kettlebell_Row", "single-arm-kettlebell-row": "One-Arm_Kettlebell_Row",
    "kettlebell-military-press": "Two-Arm_Kettlebell_Military_Press", "rowing-machine": "Rowing_Stationary",
    "treadmill": "Running_Treadmill", "exercise-bike": "Bicycling_Stationary", "elliptical": "Elliptical_Trainer",
    "stairmaster": "Stairmaster", "dead-hang": "Chin-Up",  # overwritten below (no hang entry)
}
ALIASES.pop("dead-hang")

# Close variants: borrow the base movement's photos/steps, shown in-app as "similar movement".
SIMILAR = {
    "archer-pull-up": "Pullups", "assisted-chin-up": "Chin-Up", "assisted-pull-up": "Pullups", "band-assisted-chin-up": "Chin-Up",
    "assisted-dip": "Dip_Machine", "close-grip-chin-up": "Chin-Up", "close-grip-pull-up": "Pullups", "wide-grip-chin-up": "Chin-Up",
    "weighted-dips": "Dips_-_Triceps_Version", "machine-dip": "Dip_Machine", "plate-loaded-machine-dip": "Dip_Machine",
    "bar-pullover": "Bent-Arm_Barbell_Pullover", "ez-bar-pullover": "Bent-Arm_Barbell_Pullover", "cable-pullover": "Straight-Arm_Pulldown",
    "rope-pullover": "Straight-Arm_Pulldown", "machine-pullover": "Straight-Arm_Pulldown",
    "barbell-bulgarian-split-squat": "Smith_Single-Leg_Split_Squat", "barbell-split-squat": "Barbell_Lunge",
    "smith-machine-split-squat": "Smith_Single-Leg_Split_Squat", "smith-machine-rear-elevated-split-squat": "Smith_Single-Leg_Split_Squat",
    "smith-machine-front-elevated-split-squat": "Smith_Single-Leg_Split_Squat", "smith-machine-lunge": "Barbell_Lunge",
    "dumbbell-front-elevated-split-squat": "Split_Squat_with_Dumbbells", "dumbbell-walking-lunge": "Dumbbell_Lunges",
    "kettlebell-front-lunge": "Dumbbell_Lunges", "kettlebell-reverse-lunge": "Dumbbell_Rear_Lunge", "cable-step-up": "Dumbbell_Step_Ups",
    "barbell-drag-curl": "Barbell_Curl", "kettlebell-bicep-curl": "Dumbbell_Bicep_Curl", "seated-dumbbell-bicep-curl": "Dumbbell_Bicep_Curl",
    "seated-dumbbell-hammer-curl": "Hammer_Curls", "dumbbell-incline-hammer-curl": "Incline_Dumbbell_Curl",
    "dumbbell-preacher-curl": "Preacher_Curl", "dumbbell-preacher-hammer-curl": "Preacher_Curl", "seated-dumbbell-zottman-curl": "Zottman_Curl",
    "cable-concentration-curl": "Concentration_Curls", "face-away-cable-curl": "Standing_Biceps_Cable_Curl",
    "seated-cable-curl": "Standing_Biceps_Cable_Curl", "preacher-curl-machine": "Machine_Preacher_Curls",
    "reverse-dumbbell-curl": "Standing_Dumbbell_Reverse_Curl", "seated-reverse-dumbbell-curl": "Standing_Dumbbell_Reverse_Curl",
    "reverse-ez-bar-curl": "Reverse_Barbell_Curl", "reverse-ez-bar-preacher-curl": "Reverse_Barbell_Preacher_Curls",
    "reverse-single-arm-cable-curl": "Reverse_Cable_Curl",
    "ez-bar-wrist-curl": "Palms-Up_Barbell_Wrist_Curl_Over_A_Bench", "ez-bar-wrist-extension": "Palms-Down_Wrist_Curl_Over_A_Bench",
    "dumbbell-wrist-extension": "Palms-Down_Dumbbell_Wrist_Curl_Over_A_Bench",
    "ez-bar-standing-back-wrist-curl": "Standing_Palms-Up_Barbell_Behind_The_Back_Wrist_Curl",
    "dumbbell-standing-back-wrist-curl": "Standing_Palms-Up_Barbell_Behind_The_Back_Wrist_Curl",
    "cable-standing-back-wrist-curl": "Standing_Palms-Up_Barbell_Behind_The_Back_Wrist_Curl",
    "reverse-cable-wrist-curl": "Palms-Down_Wrist_Curl_Over_A_Bench",
    "barbell-overhead-tricep-extension": "Cable_Rope_Overhead_Triceps_Extension",
    "cable-dual-overhead-tricep-extension": "Cable_Rope_Overhead_Triceps_Extension",
    "cable-straight-bar-overhead-tricep-extension": "Cable_Rope_Overhead_Triceps_Extension",
    "cable-single-arm-overhead-tricep-extension": "Cable_One_Arm_Tricep_Extension", "cable-single-arm-extension": "Cable_One_Arm_Tricep_Extension",
    "cable-cuffed-single-arm-tricep-extension": "Cable_One_Arm_Tricep_Extension", "katana-extension": "Cable_One_Arm_Tricep_Extension",
    "cable-kickback": "Tricep_Dumbbell_Kickback", "dumbbell-skullcrusher": "Lying_Triceps_Press",
    "machine-tricep-extension": "Machine_Triceps_Extension", "machine-overhead-tricep-extension": "Machine_Triceps_Extension",
    "barbell-jm-press": "Close-Grip_Barbell_Bench_Press", "smith-machine-jm-press": "Smith_Machine_Close-Grip_Bench_Press",
    "barbell-larsen-press": "Barbell_Bench_Press_-_Medium_Grip", "reverse-grip-barbell-bench-press": "Barbell_Bench_Press_-_Medium_Grip",
    "incline-close-grip-barbell-bench-press": "Barbell_Incline_Bench_Press_-_Medium_Grip",
    "incline-close-grip-smith-machine-bench-press": "Smith_Machine_Incline_Bench_Press",
    "wide-grip-smith-machine-bench-press": "Smith_Machine_Bench_Press", "dumbbell-larsen-press": "Dumbbell_Bench_Press",
    "dumbbell-hex-press": "Dumbbell_Bench_Press_with_Neutral_Grip", "iso-lateral-chest-press": "Leverage_Chest_Press",
    "seated-chest-press-machine": "Leverage_Chest_Press", "iso-lateral-incline-chest-press": "Leverage_Incline_Chest_Press",
    "iso-lateral-decline-chest-press": "Leverage_Decline_Chest_Press", "seated-cable-chest-press": "Cable_Chest_Press",
    "incline-cable-press": "Cable_Chest_Press", "cable-fly-high-to-low": "Cable_Crossover", "cable-fly-low-to-high": "Cable_Crossover",
    "barbell-push-press": "Push_Press", "dumbbell-push-press": "Push_Press", "barbell-z-press": "Seated_Barbell_Military_Press",
    "behind-the-back-barbell-overhead-press": "Standing_Military_Press", "dumbbell-z-press": "Seated_Dumbbell_Press",
    "iso-lateral-shoulder-press": "Leverage_Shoulder_Press", "shoulder-press-machine": "Machine_Shoulder_Military_Press",
    "neutral-grip-machine-shoulder-press": "Machine_Shoulder_Military_Press", "single-arm-landmine-press": "Landmine_Linear_Jammer",
    "barbell-front-raise": "Front_Dumbbell_Raise", "plate-front-raise": "Front_Plate_Raise", "cable-front-raise": "Front_Cable_Raise",
    "seated-dumbbell-front-raise": "Front_Dumbbell_Raise", "incline-dumbbell-front-raise": "Front_Dumbbell_Raise",
    "cable-lateral-raise": "Cable_Seated_Lateral_Raise", "high-cable-lateral-raise": "Cable_Seated_Lateral_Raise",
    "incline-side-lateral-raise": "Side_Lateral_Raise", "lateral-raise-machine": "Side_Lateral_Raise",
    "plate-loaded-machine-lateral-raise": "Side_Lateral_Raise", "dumbbell-incline-y-raise": "Dumbbell_Incline_Shoulder_Raise",
    "cable-standing-y-raise": "Cable_Seated_Lateral_Raise", "cuffed-cable-seated-y-raise": "Cable_Seated_Lateral_Raise",
    "cable-rear-delt-fly": "Cable_Rear_Delt_Fly", "rear-delt-fly-machine": "Reverse_Machine_Flyes",
    "dumbbell-face-pull": "Seated_Bent-Over_Rear_Delt_Raise", "cable-external-rotation": "External_Rotation_with_Cable",
    "dumbbell-external-rotation": "External_Rotation", "cable-internal-rotation": "Internal_Rotation_with_Band",
    "dumbbell-internal-rotation": "Internal_Rotation_with_Band", "cable-upright-row": "Upright_Barbell_Row",
    "kettlebell-upright-row": "Standing_Dumbbell_Upright_Row", "kettlebell-shrug": "Dumbbell_Shrug", "smith-machine-shrug": "Barbell_Shrug",
    "dumbbell-kelso-shrug": "Dumbbell_Shrug", "machine-row-kelso-shrug": "Barbell_Shrug", "cable-shrug": "Barbell_Shrug",
    "barbell-rack-pull": "Rack_Pulls", "reverse-grip-barbell-row": "Reverse_Grip_Bent-Over_Rows", "barbell-incline-row": "Dumbbell_Incline_Row",
    "bent-over-t-bar-row": "T-Bar_Row_with_Handle", "bent-over-underhand-grip-t-bar-row": "T-Bar_Row_with_Handle",
    "underhand-grip-t-bar-row": "T-Bar_Row_with_Handle", "neutral-grip-t-bar-row": "T-Bar_Row_with_Handle",
    "single-arm-cable-row": "Seated_One-arm_Cable_Pulley_Rows", "close-neutral-grip-cable-row": "Seated_Cable_Rows",
    "iso-lateral-row-machine": "Leverage_Iso_Row", "iso-lateral-low-row": "Leverage_Iso_Row", "iso-lateral-high-row": "Leverage_High_Row",
    "neutral-grip-seated-machine-row": "Leverage_Iso_Row", "underhand-grip-seated-machine-row": "Leverage_Iso_Row",
    "neutral-grip-pulldown": "V-Bar_Pulldown", "neutral-close-grip-pulldown": "V-Bar_Pulldown",
    "iso-lateral-pulldown": "Wide-Grip_Lat_Pulldown", "iso-lateral-wide-pulldown": "Wide-Grip_Lat_Pulldown",
    "iso-lateral-close-grip-pulldown": "Close-Grip_Front_Lat_Pulldown",
    "belt-squat": "Barbell_Squat", "pendulum-squat": "Hack_Squat", "landmine-squat": "Goblet_Squat", "machine-leg-press": "Leg_Press",
    "single-leg-leg-press": "Leg_Press", "sissy-squat": "Weighted_Sissy_Squat",
    "kettlebell-deadlift": "Kettlebell_One-Legged_Deadlift", "kettlebell-rdl": "Stiff-Legged_Dumbbell_Deadlift",
    "single-leg-dumbbell-rdl": "Kettlebell_One-Legged_Deadlift", "cable-rdl": "Cable_Deadlifts",
    "smith-machine-good-morning": "Smith_Machine_Stiff-Legged_Deadlift", "barbell-kas-glute-bridge": "Barbell_Glute_Bridge",
    "dumbbell-glute-bridge": "Barbell_Glute_Bridge", "dumbbell-kas-glute-bridge": "Barbell_Glute_Bridge",
    "dumbbell-hip-thrust": "Barbell_Hip_Thrust", "single-leg-bodyweight-glute-bridge": "Single_Leg_Glute_Bridge",
    "single-leg-bodyweight-hip-thrust": "Single_Leg_Glute_Bridge", "machine-rear-kickback": "Glute_Kickback",
    "seated-single-leg-leg-curl": "Seated_Leg_Curl", "standing-single-leg-leg-curl": "Standing_Leg_Curl",
    "machine-back-extension": "Hyperextensions_Back_Extensions", "seated-single-leg-machine-calf-raise": "Seated_Calf_Raise",
    "elevated-smith-machine-calf-raise": "Smith_Machine_Calf_Raise", "hack-squat-calf-raise": "Standing_Calf_Raises",
    "bodyweight-elevated-calf-raise": "Standing_Calf_Raises", "standing-cable-crunch": "Cable_Crunch", "cable-side-crunch": "Cable_Crunch",
    "captains-chair-knee-raise": "Knee_Hip_Raise_On_Parallel_Bars", "captains-chair-leg-raise": "Knee_Hip_Raise_On_Parallel_Bars",
    "standing-wheel-rollout": "Ab_Roller", "weighted-russian-twist": "Russian_Twist", "glute-ham-raise-sit-up": "Sit-Up",
    "reverse-plank": "Plank", "l-sit": "Hanging_Pike", "kneeling-push-up": "Pushups", "pike-push-up": "Handstand_Push-Ups",
    "kettlebell-farmer-carry": "Farmers_Walk", "ski-ergometer": "Rowing_Stationary", "assault-bike": "Recumbent_Bike",
}

# Written for IronLog where no public-domain source exists.
OWN_CUES = {
    "dead-hang": [
        "Grab a pull-up bar with an overhand grip, hands just outside shoulder width.",
        "Lift your feet and hang with arms straight, shoulders gently pulled down away from your ears.",
        "Keep your ribs down and legs still; breathe steadily and hold for time.",
        "Step down under control before your grip fails completely.",
    ],
}


def main():
    try:
        with urllib.request.urlopen(FEDB_URL, timeout=60) as r:
            fedb = {e["id"]: e for e in json.load(r)}
    except Exception as e:
        print(f"WARNING: couldn't fetch free-exercise-db ({e}); building without instructions/photos")
        fedb = {}
    byname = {norm(e["name"]): e["id"] for e in fedb.values()}

    out, matched, unmatched, bad_alias = [], 0, [], []
    for line in open(CATALOG):
        slug, name, muscles, mech, level, equip = line.rstrip("\n").split("|")
        primary = muscles.split(",")
        equipment = equip.split(",")
        fid = ALIASES.get(slug)
        if fid and fid not in fedb:
            bad_alias.append((slug, fid)); fid = None
        if not fid and fedb:
            m = difflib.get_close_matches(norm(name), list(byname), n=1, cutoff=0.93)
            fid = byname[m[0]] if m else None
        src = fedb.get(fid) if fid else None
        similar_name = None
        if not src and SIMILAR.get(slug) in fedb:
            src = fedb[SIMILAR[slug]]
            similar_name = src["name"]
        own = OWN_CUES.get(slug)
        if src or own: matched += 1
        else: unmatched.append(slug)

        t = tracking(slug)
        ex = {
            "id": slug, "name": name, "force": None, "level": level, "mechanic": mech,
            "equipment": equipment[0], "equipmentList": equipment,
            "primaryMuscles": primary, "secondaryMuscles": secondary(slug, primary, mech),
            "instructions": own or (src["instructions"] if src else []),
            "category": "cardio" if t == "cardio" else "strength",
            "images": src["images"] if src and not own else [],
            "tracking": t,
            "instructionsFrom": similar_name,
            "bodyweightShare": BODYWEIGHT.get(slug, ASSIST_SHARE.get(slug, 1.0 if t == "assistedReps" else None)),
        }
        if slug in S:
            a, f, c = S[slug]
            ex["standard"] = {"anchor": a, "factor": f, "confidence": c}
        out.append(ex)

    unknown = set(S) - {e["id"] for e in out}
    if unknown: sys.exit(f"Standards reference unknown slugs: {sorted(unknown)}")
    if bad_alias: print("Aliases not found in free-exercise-db (ignored):", bad_alias)

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, "exercises.json"), "w") as f:
        json.dump(out, f, separators=(",", ":"))
    with open(os.path.join(OUT_DIR, "standards.json"), "w") as f:
        json.dump({"reference": {"M": 80.0, "F": 65.0}, "allometricExponent": 0.67,
                   "levels": ["Beginner", "Novice", "Intermediate", "Advanced", "Elite", "World Class"],
                   "anchors": ANCHORS}, f, separators=(",", ":"), indent=None)
    scored = sum(1 for e in out if "standard" in e)
    print(f"{len(out)} exercises, {scored} with strength standards, {matched} with instructions/photos")
    print("No instructions for:", unmatched)


if __name__ == "__main__":
    main()
