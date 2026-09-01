"""
wardrobe_algorithm.py — Outfit scoring and suggestion engine.
Implements outfit.md v1.0 specification end-to-end.

SQL schema (run once):
  See SCHEMA constant at the bottom of this file.

Integration: add `router` to your main FastAPI app:
  from wardrobe_algorithm import router as wardrobe_router
  app.include_router(wardrobe_router)
"""
from __future__ import annotations

import math
import re
from datetime import date, datetime, timedelta
from typing import Optional

# ─── COLOR CONSTANTS ──────────────────────────────────────────────────────────

COLORS = ["NE","BL","GC","GA","BE","CR","MA","RY","CE","OL","VB","VM","CH","CA","BU","RO","RP","MO","TE","LA"]
_CI = {c: i for i, c in enumerate(COLORS)}

# Luminosity class 1-5 (1=very dark, 5=very light)
COLOR_L = {"NE":1,"BL":5,"GC":4,"GA":2,"BE":4,"CR":5,"MA":1,"RY":3,"CE":4,"OL":2,"VB":2,"VM":4,"CH":2,"CA":3,"BU":2,"RO":3,"RP":4,"MO":3,"TE":3,"LA":3}
# Saturation class 0-3 (0=achromatic, 1=muted, 2=medium, 3=vivid)
COLOR_S = {"NE":0,"BL":0,"GC":0,"GA":0,"BE":0,"CR":1,"MA":1,"RY":3,"CE":1,"OL":1,"VB":1,"VM":1,"CH":1,"CA":1,"BU":1,"RO":3,"RP":1,"MO":2,"TE":2,"LA":1}
# Temperature W=warm, C=cool, N=neutral
COLOR_T = {"NE":"N","BL":"N","GC":"N","GA":"N","BE":"N","CR":"W","MA":"C","RY":"C","CE":"C","OL":"W","VB":"C","VM":"C","CH":"W","CA":"W","BU":"W","RO":"W","RP":"C","MO":"W","TE":"W","LA":"C"}
# Neutral-soft set (M4 suelo)
NEUTRAL_SOFT = {"CR","MA","OL","CH","CA"}
ABS_NEUTRAL  = {"NE","BL","GC","GA","BE"}

# ─── 20×20 COLOR MATRIX (§2.4) ────────────────────────────────────────────────
# Upper triangle from outfit.md; symmetrized below.
_UPPER: list[list[float]] = [
    # NE    BL    GC    GA    BE    CR    MA    RY    CE    OL    VB    VM    CH    CA    BU    RO    RP    MO    TE    LA
    [0.80, 0.90, 0.90, 0.75, 0.90, 0.85, 0.75, 0.90, 0.85, 0.85, 0.85, 0.85, 0.85, 0.85, 0.85, 0.90, 0.85, 0.85, 0.85, 0.85],  # NE
    [0.00, 0.80, 0.75, 0.90, 0.75, 0.60, 0.85, 0.90, 0.85, 0.85, 0.85, 0.85, 0.85, 0.85, 0.85, 0.90, 0.85, 0.85, 0.85, 0.85],  # BL
    [0.00, 0.00, 0.80, 0.90, 0.75, 0.85, 0.85, 0.85, 0.75, 0.85, 0.85, 0.75, 0.85, 0.85, 0.85, 0.85, 0.75, 0.85, 0.85, 0.85],  # GC
    [0.00, 0.00, 0.00, 0.80, 0.90, 0.85, 0.85, 0.85, 0.85, 0.75, 0.75, 0.85, 0.75, 0.85, 0.75, 0.85, 0.85, 0.85, 0.85, 0.85],  # GA
    [0.00, 0.00, 0.00, 0.00, 0.80, 0.85, 0.80, 0.80, 0.70, 0.85, 0.80, 0.70, 0.85, 0.85, 0.85, 0.85, 0.70, 0.85, 0.85, 0.80],  # BE
    [0.00, 0.00, 0.00, 0.00, 0.00, 0.60, 0.85, 0.70, 0.80, 0.78, 0.70, 0.70, 0.82, 0.82, 0.78, 0.78, 0.74, 0.82, 0.78, 0.70],  # CR
    [0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.60, 0.82, 0.82, 0.70, 0.70, 0.78, 0.70, 0.85, 0.75, 0.80, 0.75, 0.78, 0.70, 0.78],  # MA
    [0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.60, 0.58, 0.70, 0.60, 0.78, 0.70, 0.70, 0.56, 0.31, 0.60, 0.68, 0.48, 0.78],  # RY
    [0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.60, 0.70, 0.78, 0.78, 0.75, 0.78, 0.56, 0.64, 0.62, 0.64, 0.64, 0.78],  # CE
    [0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.60, 0.74, 0.74, 0.78, 0.78, 0.75, 0.78, 0.74, 0.78, 0.78, 0.70],  # OL
    [0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.60, 0.82, 0.70, 0.70, 0.72, 0.56, 0.60, 0.72, 0.56, 0.60],  # VB
    [0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.60, 0.70, 0.70, 0.64, 0.56, 0.62, 0.56, 0.56, 0.60],  # VM
    [0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.60, 0.82, 0.78, 0.70, 0.74, 0.70, 0.70, 0.70],  # CH
    [0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.60, 0.78, 0.78, 0.74, 0.70, 0.70, 0.70],  # CA
    [0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.60, 0.58, 0.78, 0.78, 0.78, 0.56],  # BU
    [0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.60, 0.54, 0.78, 0.58, 0.41],  # RO
    [0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.60, 0.74, 0.74, 0.60],  # RP
    [0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.60, 0.78, 0.41],  # MO
    [0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.60, 0.41],  # TE
    [0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.60],  # LA
]

# Build full symmetric matrix
COLOR_MATRIX: list[list[float]] = [[0.0]*20 for _ in range(20)]
for _i in range(20):
    for _j in range(20):
        if _j >= _i:
            COLOR_MATRIX[_i][_j] = _UPPER[_i][_j]
        else:
            COLOR_MATRIX[_i][_j] = _UPPER[_j][_i]

def pair_compat_codes(c1: str, c2: str) -> float:
    return COLOR_MATRIX[_CI[c1]][_CI[c2]]

# ─── SEASON SCORES (§3.2) ─────────────────────────────────────────────────────
# [spring, summer, autumn, winter]
SEASON_SCORES: dict[str, list[float]] = {
    "NE": [0.30, 0.40, 0.40, 1.00],
    "BL": [0.50, 0.60, 0.40, 1.00],
    "GC": [0.50, 0.90, 0.40, 0.70],
    "GA": [0.40, 0.60, 0.50, 0.90],
    "BE": [0.80, 0.60, 0.90, 0.40],
    "CR": [0.90, 0.50, 0.90, 0.30],
    "MA": [0.60, 0.80, 0.50, 0.90],
    "RY": [0.70, 0.60, 0.40, 0.90],
    "CE": [0.90, 0.90, 0.40, 0.60],
    "OL": [0.50, 0.30, 1.00, 0.30],
    "VB": [0.40, 0.40, 0.90, 0.70],
    "VM": [0.90, 0.70, 0.30, 0.50],
    "CH": [0.50, 0.30, 1.00, 0.40],
    "CA": [0.80, 0.40, 1.00, 0.30],
    "BU": [0.40, 0.50, 0.80, 0.80],
    "RO": [0.70, 0.40, 0.60, 0.90],
    "RP": [0.70, 0.90, 0.30, 0.50],
    "MO": [0.70, 0.20, 1.00, 0.30],
    "TE": [0.80, 0.30, 1.00, 0.30],
    "LA": [0.50, 0.90, 0.20, 0.70],
}
_SEASON_IDX = {"spring":0, "summer":1, "autumn":2, "winter":3}

def season_score_for(code: str, season: str) -> float:
    idx = _SEASON_IDX.get(season, 0)
    return SEASON_SCORES.get(code, [0.5,0.5,0.5,0.5])[idx]

# ─── DATA CLASSES ─────────────────────────────────────────────────────────────

class ItemColor:
    __slots__ = ("code","pct")
    def __init__(self, code: str, pct: float):
        self.code = code; self.pct = pct

class Item:
    __slots__ = ("id","name","category","subcategory","colors","formality","warmth",
                 "reuse_days","state","tags","photo_url","fungible_group_id",
                 "last_used","uses_14d")
    def __init__(self, id: int, name: str, category: str, subcategory: str,
                 colors: list, formality: int, warmth: int, reuse_days: int,
                 state: str, tags: list, photo_url: Optional[str],
                 fungible_group_id: Optional[str], last_used: Optional[date],
                 uses_14d: int):
        self.id = id; self.name = name; self.category = category
        self.subcategory = subcategory; self.colors = colors
        self.formality = formality; self.warmth = warmth
        self.reuse_days = reuse_days; self.state = state
        self.tags = [t.lower() for t in tags]; self.photo_url = photo_url
        self.fungible_group_id = fungible_group_id
        self.last_used = last_used; self.uses_14d = uses_14d

class Slot:
    __slots__ = ("top","bottom","shoes","outerwear","headwear","accessories",
                 "socks","underwear","score")
    def __init__(self, top=None, bottom=None, shoes=None, outerwear=None,
                 headwear=None, accessories=None, socks=None, underwear=None,
                 score=0.0):
        self.top = top; self.bottom = bottom; self.shoes = shoes
        self.outerwear = outerwear; self.headwear = headwear
        self.accessories = accessories or []; self.socks = socks
        self.underwear = underwear; self.score = score

    def visible_items(self) -> list[Item]:
        return [x for x in [self.outerwear, self.top, self.bottom, self.shoes,
                             self.headwear] + self.accessories if x is not None]

    def visible_ids(self) -> frozenset[int]:
        return frozenset(i.id for i in self.visible_items())

    def structural_ids(self) -> frozenset[int]:
        return frozenset(i.id for i in [self.top, self.bottom, self.shoes] if i)

class Weather:
    __slots__ = ("temp_c","wind_kmh","condition","precip_pct","temp_max","temp_min")
    def __init__(self, temp_c: float, wind_kmh: float = 0, condition: str = "cloudy",
                 precip_pct: float = 0, temp_max: Optional[float] = None,
                 temp_min: Optional[float] = None):
        self.temp_c = temp_c; self.wind_kmh = wind_kmh
        self.condition = condition.lower(); self.precip_pct = precip_pct
        self.temp_max = temp_max if temp_max is not None else temp_c
        self.temp_min = temp_min if temp_min is not None else temp_c

class Context:
    __slots__ = ("weather","target_formality","formality_label","today",
                 "user_season","bimodal","afternoon_target","afternoon_label")
    def __init__(self, weather: Weather, target_formality: int,
                 formality_label: str, today: date,
                 user_season: str = "winter", bimodal: bool = False,
                 afternoon_target: Optional[int] = None,
                 afternoon_label: Optional[str] = None):
        self.weather = weather; self.target_formality = target_formality
        self.formality_label = formality_label; self.today = today
        self.user_season = user_season.lower(); self.bimodal = bimodal
        self.afternoon_target = afternoon_target
        self.afternoon_label = afternoon_label

# ─── THERMAL MODEL (§5.1) ─────────────────────────────────────────────────────

def t_feel(w: Weather) -> float:
    t = w.temp_c
    if t <= 12 and w.wind_kmh > 10:
        t -= min(5.0, 0.10 * (w.wind_kmh - 10))
    if t >= 26 and w.condition == "sunny":
        t += 1.0
    return t

def w_star(t: float) -> float:
    return max(1.0, min(5.0, 1.0 + (26.0 - t) / 5.5))

def w_outfit(slot: Slot) -> float:
    if slot.outerwear:
        return (0.45 * slot.outerwear.warmth + 0.25 * (slot.top.warmth if slot.top else 2)
                + 0.20 * (slot.bottom.warmth if slot.bottom else 2)
                + 0.10 * (slot.shoes.warmth if slot.shoes else 2))
    else:
        return (0.45 * (slot.top.warmth if slot.top else 2)
                + 0.35 * (slot.bottom.warmth if slot.bottom else 2)
                + 0.20 * (slot.shoes.warmth if slot.shoes else 2))

def s_thermal(slot: Slot, ctx: Context) -> float:
    w = ctx.weather
    tf = t_feel(w)
    ws = w_star(tf)
    wo = w_outfit(slot)
    dw = wo - ws
    if abs(dw) >= 2.5:
        return 0.0  # disqualify
    sigma = 0.55 if (w.temp_c >= 26 and dw > 0) else 0.70
    score = math.exp(-dw**2 / (2 * sigma**2))
    # Double restriction for large daily range
    if w.temp_max - w.temp_min > 10:
        ws_max = w_star(t_feel(Weather(w.temp_max, w.wind_kmh, w.condition, w.precip_pct)))
        ws_min = w_star(t_feel(Weather(w.temp_min, w.wind_kmh, w.condition, w.precip_pct)))
        wo_full = w_outfit(slot)
        # outfit without outerwear
        s2 = Slot(slot.top, slot.bottom, slot.shoes); wo_bare = w_outfit(s2)
        sc_min = math.exp(-(wo_full - ws_min)**2 / (2*0.70**2)) if abs(wo_full - ws_min) < 2.5 else 0.0
        sc_max = math.exp(-(wo_bare - ws_max)**2 / (2*0.70**2)) if abs(wo_bare - ws_max) < 2.5 else 0.0
        score = min(sc_min, sc_max)
    return score

# ─── FORMALITY MODEL (§4.1-4.5) ──────────────────────────────────────────────

def f_outfit(slot: Slot, target: int) -> float:
    if slot.outerwear:
        f_base = (0.20 * slot.outerwear.formality
                  + 0.30 * (slot.top.formality if slot.top else target)
                  + 0.25 * (slot.bottom.formality if slot.bottom else target)
                  + 0.25 * (slot.shoes.formality if slot.shoes else target))
    else:
        f_base = (0.40 * (slot.top.formality if slot.top else target)
                  + 0.33 * (slot.bottom.formality if slot.bottom else target)
                  + 0.27 * (slot.shoes.formality if slot.shoes else target))

    delta = 0.0
    acc_delta = 0.0
    cap_f = None
    for item in ([slot.headwear] if slot.headwear else []) + slot.accessories:
        if not item: continue
        tags = item.tags
        cat = item.category
        if cat == "headwear":
            sub = item.subcategory.lower()
            if "deportiv" in sub or any(t in tags for t in ("deportiva","running","sport")):
                delta -= 0.75; cap_f = min(cap_f or 99, 2.75)
            elif "gorra" in sub or "plana" in sub or "snapback" in sub:
                delta -= 0.50; cap_f = min(cap_f or 99, 3.25)
            elif "gorro" in sub or "lana" in sub or "beanie" in sub:
                delta -= 0.25; cap_f = min(cap_f or 99, 3.50)
            elif "fedora" in sub or "panama" in sub or "sombrero" in sub:
                if f_base >= 3: delta += 0.50; cap_f = min(cap_f or 99, 4.50)
        elif cat == "accessories":
            sub = item.subcategory.lower()
            if "cinturon" in sub or "belt" in tags:
                if "cuero" in sub or "leather" in tags: acc_delta += 0.30
                elif "lona" in sub or "tela" in sub: acc_delta -= 0.10
            if "reloj" in sub or "watch" in tags:
                if any(t in tags for t in ("vestir","dress","cuero","metal_fino")):
                    acc_delta += 0.30
                elif any(t in tags for t in ("deportivo","sport","silicona","smartwatch")):
                    acc_delta -= 0.10
            if "maleta" in sub or "maletín" in sub: acc_delta += 0.30
            if "mochila" in sub or "backpack" in tags:
                if target >= 4: acc_delta -= 0.30

    acc_delta = max(-0.50, min(0.50, acc_delta))
    f = f_base + delta + acc_delta
    if cap_f is not None: f = min(f, cap_f)
    return max(1.0, min(5.0, f))

def s_formality(slot: Slot, target: int) -> float:
    fo = f_outfit(slot, target)
    delta = fo - target
    sigma = 0.9 if delta < 0 else 1.4
    score = math.exp(-delta**2 / (2 * sigma**2))
    # zapatillas gap penalty
    if slot.shoes:
        gap = target - slot.shoes.formality
        if target == 5 and slot.shoes.formality <= 2:
            return 0.0  # disqualify
        if gap >= 2:
            score *= 0.85
    return score

# ─── FRESHNESS MODEL (§6.3-6.4) ──────────────────────────────────────────────

def freshness(item: Item, today: date, force_value: Optional[float] = None) -> float:
    if force_value is not None: return force_value
    if item.last_used is None: return 1.0
    N = (today - item.last_used).days
    R = item.reuse_days
    if N < R: return 0.0  # not available — disqualifies
    return 1.0 - math.exp(-(N - R + 1) / 3.0)

def saturation_factor(uses_14d: int) -> float:
    return max(0.70, 1.0 - 0.08 * max(0, uses_14d - 3))

def s_freshness(slot: Slot, today: date,
                recent_outfit_ids: list[frozenset[int]],
                recent_pair_ids: list[frozenset[int]],
                relaxation: int = 0) -> float:
    def eff_fresh(item: Item) -> float:
        fv = None if relaxation < 1 else 0.60
        f = freshness(item, today, force_value=fv)
        if f == 0.0: return 0.0  # disqualifies outside relaxation
        return f * saturation_factor(item.uses_14d)

    visible = slot.visible_items()
    if not visible: return 0.0
    weights = {"outerwear":0.15,"tops":0.30,"bottoms":0.25,"shoes":0.20,"headwear":0.05}
    cats = {"outerwear": slot.outerwear, "tops": slot.top,
            "bottoms": slot.bottom, "shoes": slot.shoes, "headwear": slot.headwear}
    acc_f = sum(eff_fresh(a) for a in slot.accessories) / max(len(slot.accessories),1) if slot.accessories else None

    base = 0.0; total_w = 0.0
    for cat, item in cats.items():
        if item:
            base += weights[cat] * eff_fresh(item); total_w += weights[cat]
    if slot.accessories:
        base += 0.05 * (acc_f or 0.0); total_w += 0.05
    if total_w > 0: base /= total_w

    # outfit exact repetition penalty
    visible_ids = slot.visible_ids()
    for prev in recent_outfit_ids:
        if prev == visible_ids: base = 0.10; break

    # pair repetition penalty (§6.4)
    current_pairs = set()
    vis = slot.visible_items()
    for a in range(len(vis)):
        for b in range(a+1, len(vis)):
            current_pairs.add(frozenset([vis[a].id, vis[b].id]))

    repeated = sum(1 for p in current_pairs if p in {x for s in recent_pair_ids for x in [s]})
    factor = 0.5 if relaxation >= 1 else 1.0
    base -= 0.10 * min(3, repeated) * factor
    return max(0.0, min(1.0, base))

# ─── SEASON SCORE (§3.3) ──────────────────────────────────────────────────────

def s_season(slot: Slot, user_season: str) -> float:
    # Proximity weights (renormalized to present items)
    prox = {"headwear":0.20,"tops":0.35,"outerwear":0.25,"bottoms":0.07,"shoes":0.03}
    cats = {"tops": slot.top, "bottoms": slot.bottom, "shoes": slot.shoes,
            "outerwear": slot.outerwear, "headwear": slot.headwear}
    total = 0.0; weight = 0.0
    for cat, item in cats.items():
        if item and item.colors:
            w = prox[cat]; weight += w
            item_score = sum(c["pct"] * season_score_for(c["code"], user_season)
                             for c in item.colors if c["code"] in SEASON_SCORES)
            total += w * item_score
    return total / weight if weight > 0 else 0.5

# ─── METEO SCORE (§5.2) ──────────────────────────────────────────────────────

_RAIN_BLACKLIST_SUBS = {"sandalias","alpargatas","lona","ante","gamuza"}
_RAIN_WHITELIST_TAGS = {"impermeable","water_resistant","cuero_tratado","goma","membrana"}
_RAIN_BLACKLIST_OUTERWEAR = {"ante","gamuza"}

def is_rain_safe(item: Item) -> bool:
    sub = item.subcategory.lower()
    tags = set(item.tags)
    if tags & _RAIN_WHITELIST_TAGS: return True
    return not (sub in _RAIN_BLACKLIST_SUBS or
                any(b in sub for b in _RAIN_BLACKLIST_SUBS))

def s_meteo(slot: Slot, weather: Weather) -> float:
    w = weather
    score = 1.0
    tf = t_feel(w)
    rainy = w.condition in ("rainy","rain") or w.precip_pct >= 50

    if rainy:
        # Linen soft penalty
        for item in slot.visible_items():
            if "lino" in item.subcategory.lower() or "lino" in item.tags:
                score -= 0.10

        # Waterproof outerwear bonus
        if w.precip_pct >= 70 and slot.outerwear:
            if any(t in slot.outerwear.tags for t in ("impermeable","capucha")):
                score += 0.15

    # Wind bonus for windproof
    if w.wind_kmh > 30 and tf < 18:
        for item in slot.visible_items():
            if "cortavientos" in item.tags:
                score += 0.10

    # Intense sun (§5.2)
    if w.condition == "sunny" and w.temp_c >= 27:
        surface_dark = 0.0; surface_total = 0.0
        for item in [slot.outerwear, slot.top]:
            if item and item.colors:
                area = 0.85 if item == slot.outerwear else 0.70
                if slot.outerwear and item == slot.top: area *= 0.4
                surface_total += area
                for c in item.colors:
                    if COLOR_L.get(c["code"],3) <= 2:
                        surface_dark += area * c["pct"]
        if surface_total > 0 and surface_dark / surface_total >= 0.50:
            score -= 0.30
        if slot.headwear:
            score += 0.20

    return max(0.0, min(1.0, score))

# ─── COLOR PAIR COMPATIBILITY (§2.5-2.7) ─────────────────────────────────────

def pair_compat_items(a: Item, b: Item) -> float:
    if not a.colors or not b.colors: return 0.80  # default if no color
    compat = 0.0
    for ca in a.colors:
        for cb in b.colors:
            compat += ca["pct"] * cb["pct"] * pair_compat_codes(ca["code"], cb["code"])
    # Eco bonus (§2.7): color in a appears in b with pct >= 20%
    for ca in a.colors:
        if ca["pct"] >= 0.20:
            for cb in b.colors:
                if cb["code"] == ca["code"] and cb["pct"] >= 0.20:
                    compat = min(0.95, compat + 0.05)
    return compat

def _dominant_code(item: Item) -> Optional[str]:
    if not item.colors: return None
    return max(item.colors, key=lambda c: c["pct"])["code"]

def s_color(slot: Slot) -> float:
    visible = slot.visible_items()
    if len(visible) < 2: return 0.80

    # Pair weights (§2.5), renormalized
    raw_pairs: dict[tuple[str,str], float] = {}
    slots_map = {
        "top": slot.top, "bottom": slot.bottom, "shoes": slot.shoes,
        "outerwear": slot.outerwear, "headwear": slot.headwear,
    }
    RAW_W = {
        ("top","bottom"):0.28, ("outerwear","top"):0.16, ("top","shoes"):0.14,
        ("bottom","shoes"):0.14, ("outerwear","bottom"):0.10, ("headwear","top"):0.05,
        ("outerwear","shoes"):0.04, ("headwear","outerwear"):0.03,
    }
    for (s1, s2), w in RAW_W.items():
        i1, i2 = slots_map.get(s1), slots_map.get(s2)
        if i1 and i2: raw_pairs[(s1,s2)] = w

    # Accessories vs dominant
    dom = None
    for item in visible:
        d = _dominant_code(item)
        if d: dom = item; break
    if slot.accessories and dom:
        acc_w = 0.06 / max(len(slot.accessories), 1)
        for _ in slot.accessories:
            raw_pairs[("acc_dom", _)] = acc_w

    if not raw_pairs: return 0.80

    total_w = sum(raw_pairs.values())
    scored_pairs: list[tuple[float, float]] = []  # (compat, weight)

    for (s1, s2), w in raw_pairs.items():
        if s1 == "acc_dom":
            c = pair_compat_items(s2, dom)  # type: ignore
        else:
            i1, i2 = slots_map.get(s1), slots_map.get(s2)
            if i1 and i2: c = pair_compat_items(i1, i2)
            else: continue
        scored_pairs.append((c, w))

    if not scored_pairs: return 0.80
    tw = sum(w for _, w in scored_pairs)
    media_w = sum(c * w for c, w in scored_pairs) / tw
    min_c = min(c for c, _ in scored_pairs)

    # P_6030 penalty (§2.6)
    all_colors: dict[str, float] = {}
    area_map = {"outerwear":0.85,"top":0.70,"bottom":0.80,"shoes":0.25,"headwear":0.12}
    if slot.outerwear: area_map["top"] = area_map.get("top",0.70) * 0.4
    for sname, item in slots_map.items():
        if item and item.colors:
            a = area_map.get(sname, 0.10)
            for c in item.colors:
                all_colors[c["code"]] = all_colors.get(c["code"], 0.0) + a * c["pct"]
    total_area = sum(all_colors.values())
    if total_area > 0:
        shares = {c: v/total_area for c, v in all_colors.items()}
        n_prot = sum(1 for c, s in shares.items() if COLOR_S.get(c,0) == 3 and s >= 0.25)
        p_prot = min(0.25, 0.12 * max(0, n_prot - 1))
        p_ancla = 0.08 if (max(shares.values()) < 0.45) else 0.0
    else:
        p_prot = p_ancla = 0.0

    raw = 0.70 * media_w + 0.30 * min_c - (p_prot + p_ancla)
    return max(0.0, min(1.0, raw))

# ─── DISQUALIFIERS (§7.2) ─────────────────────────────────────────────────────

def disqualified(slot: Slot, ctx: Context, relaxation: int = 0) -> bool:
    w = ctx.weather
    tf = t_feel(w)
    # 1. Incomplete outfit
    if not (slot.top and slot.bottom and slot.shoes): return True
    # 2. Dirty or washing state
    for item in slot.visible_items() + ([slot.socks] if slot.socks else []) + ([slot.underwear] if slot.underwear else []):
        if item and item.state in ("sucia","lavadora"): return True
    # 3. Freshness = 0 (only in normal mode)
    if relaxation == 0:
        for item in slot.visible_items():
            if freshness(item, ctx.today) == 0.0: return True
    # 4. Rain + blacklist (never relaxed at precip >= 70%)
    rainy = w.condition in ("rainy","rain") or w.precip_pct >= 50
    if rainy:
        for item in slot.visible_items():
            if not is_rain_safe(item):
                if w.precip_pct >= 70: return True
    # 5. Thermal extreme
    wo = w_outfit(slot); ws = w_star(tf)
    if abs(wo - ws) >= 2.5: return True
    # 6. Strong wind without outerwear
    if w.wind_kmh > 30 and tf < 18 and slot.outerwear is None: return True
    # 7. Formal target with sneakers
    if ctx.target_formality == 5 and slot.shoes and slot.shoes.formality <= 2: return True
    # 8. Snow + sandals
    if w.condition == "snowy":
        for item in [slot.shoes]:
            if item and item.subcategory.lower() in ("sandalias","alpargatas"): return True
    return False

# ─── TOTAL SCORE (§7.1) ───────────────────────────────────────────────────────

def score_outfit(
    slot: Slot, ctx: Context,
    recent_outfit_ids: list[frozenset[int]],
    recent_pair_ids: list[frozenset[int]],
    relaxation: int = 0,
) -> float:
    if disqualified(slot, ctx, relaxation): return 0.0
    sc = s_color(slot)
    st = s_thermal(slot, ctx)
    sf = s_formality(slot, ctx.target_formality)
    sfr = s_freshness(slot, ctx.today, recent_outfit_ids, recent_pair_ids, relaxation)
    ss = s_season(slot, ctx.user_season)
    sm = s_meteo(slot, ctx.weather)
    if relaxation >= 2: ss = 0.50  # step 2: neutralize season
    total = 0.25*st + 0.25*sf + 0.22*sc + 0.13*sfr + 0.10*ss + 0.05*sm
    return round(total, 4)

# ─── SEARCH ALGORITHM (§7.3) ─────────────────────────────────────────────────

def _phase0_filter(items: list[Item], ctx: Context, relaxation: int) -> dict[str,list[Item]]:
    w = ctx.weather; tf = t_feel(w); ws = w_star(tf)
    rainy = w.condition in ("rainy","rain") or w.precip_pct >= 50
    snowy = w.condition == "snowy"
    tol_f = 1.5 if relaxation < 3 else 2.5
    tol_w = 1.5
    result: dict[str,list[Item]] = {
        "tops":[], "bottoms":[], "shoes":[], "outerwear":[], "headwear":[], "accessories":[]
    }
    for item in items:
        if not item.state == "limpia": continue
        cat = item.category
        if cat not in result: continue
        if relaxation == 0 and freshness(item, ctx.today) == 0.0: continue
        if abs(item.warmth - ws) > tol_w and cat not in ("accessories","headwear"): continue
        if abs(item.formality - ctx.target_formality) > tol_f and cat not in ("accessories","headwear"): continue
        if rainy and cat in ("shoes","outerwear"):
            if not is_rain_safe(item):
                if w.precip_pct >= 70: continue
        if snowy and cat == "shoes":
            if item.subcategory.lower() in ("sandalias","alpargatas"): continue
        result[cat].append(item)
    return result

def suggest_outfit(
    items: list[Item],
    ctx: Context,
    recent_outfit_ids: list[frozenset[int]],
    recent_pair_ids: list[frozenset[int]],
    fungibles: dict[str, dict] = {},  # group_id -> {total, clean}
    relaxation: int = -1,
) -> dict:
    BEAM_K = 25
    MIN_SCORE = 0.55
    stock_alerts: list[str] = []

    # Check fungibles
    for gid, grp in fungibles.items():
        clean = grp.get("clean", 0)
        label = grp.get("label", gid)
        if clean == 0:
            stock_alerts.append(f"Sin {label} limpia — lavadora necesaria")
        elif clean == 1:
            stock_alerts.append(f"Ultima {label} limpia — pon lavadora hoy")
        elif clean == 2:
            stock_alerts.append(f"Quedan 2 {label} limpias — pon lavadora pronto")

    # Auto-detect relaxation level
    if relaxation < 0:
        relaxation = 0

    for attempt in range(4):  # relajación 0→1→2→3
        filtered = _phase0_filter(items, ctx, attempt)
        tops = filtered["tops"]; bottoms = filtered["bottoms"]
        shoes_list = filtered["shoes"]
        outerwear_list = [None] + filtered["outerwear"]
        headwear_list = [None] + filtered["headwear"]
        accessories_list = filtered["accessories"]

        if not tops or not bottoms or not shoes_list:
            continue

        # Phase 1: nucleus (top × bottom × shoes)
        candidates: list[tuple[float, Slot]] = []
        for top in tops:
            for bottom in bottoms:
                for shoe in shoes_list:
                    sl = Slot(top=top, bottom=bottom, shoes=shoe)
                    sc = score_outfit(sl, ctx, recent_outfit_ids, recent_pair_ids, attempt)
                    if sc > 0: candidates.append((sc, sl))

        candidates.sort(key=lambda x: -x[0])
        top_k = [s for _, s in candidates[:BEAM_K]]
        if not top_k: continue

        # Phase 2: beam search with outerwear + headwear
        expanded: list[tuple[float, Slot]] = []
        for base_slot in top_k:
            for outer in outerwear_list:
                for head in headwear_list:
                    sl = Slot(base_slot.top, base_slot.bottom, base_slot.shoes,
                              outer, head)
                    sc = score_outfit(sl, ctx, recent_outfit_ids, recent_pair_ids, attempt)
                    if sc > 0: expanded.append((sc, sl))

        expanded.sort(key=lambda x: -x[0])
        finalists = [s for _, s in expanded[:BEAM_K]]
        if not finalists: continue

        # Phase 3: greedy accessories
        best_outfits: list[tuple[float, Slot]] = []
        for base_slot in finalists[:10]:
            best_slot = base_slot
            best_sc = score_outfit(base_slot, ctx, recent_outfit_ids, recent_pair_ids, attempt)
            used_acc: list[Item] = []
            for _ in range(3):
                gained: list[tuple[float, Item]] = []
                for acc in accessories_list:
                    if acc in used_acc: continue
                    sl = Slot(best_slot.top, best_slot.bottom, best_slot.shoes,
                              best_slot.outerwear, best_slot.headwear, used_acc + [acc])
                    sc2 = score_outfit(sl, ctx, recent_outfit_ids, recent_pair_ids, attempt)
                    if sc2 > best_sc: gained.append((sc2 - best_sc, acc))
                if not gained: break
                best_acc = max(gained, key=lambda x: x[0])[1]
                used_acc.append(best_acc)
                best_slot = Slot(best_slot.top, best_slot.bottom, best_slot.shoes,
                                 best_slot.outerwear, best_slot.headwear, used_acc[:])
                best_sc += max(gained, key=lambda x: x[0])[0]
            best_slot.score = score_outfit(best_slot, ctx, recent_outfit_ids, recent_pair_ids, attempt)
            best_outfits.append((best_slot.score, best_slot))

        best_outfits.sort(key=lambda x: -x[0])
        if not best_outfits: continue

        main_slot = best_outfits[0][1]
        if main_slot.score >= MIN_SCORE or attempt == 3:
            # Pick socks/underwear from fungibles
            socks_item = next((i for i in items if i.category == "socks" and i.state == "limpia"), None)
            underwear_item = next((i for i in items if i.category == "underwear" and i.state == "limpia"), None)
            main_slot.socks = socks_item; main_slot.underwear = underwear_item

            # MMR alternatives (§7.4)
            all_scored = [(sc, sl) for sc, sl in best_outfits[1:]]
            alternatives: list[Slot] = []
            for _ in range(3):
                best_alt = None; best_mmr = -1.0
                for sc, sl in all_scored:
                    if sl is main_slot or sl in alternatives: continue
                    jaccard_max = max(
                        (len(sl.visible_ids() & prev.visible_ids()) /
                         max(len(sl.visible_ids() | prev.visible_ids()), 1))
                        for prev in [main_slot] + alternatives
                    )
                    if jaccard_max > 0.5: continue
                    struct_diff = sum(
                        1 for a, b in [
                            (sl.top, main_slot.top),(sl.bottom, main_slot.bottom),
                            (sl.shoes, main_slot.shoes)
                        ] if a and b and a.id != b.id
                    )
                    if struct_diff < 2: continue
                    mmr = 0.70 * sc - 0.30 * jaccard_max
                    if mmr > best_mmr: best_mmr = mmr; best_alt = sl
                if best_alt: alternatives.append(best_alt)
                else: break

            if attempt > 0:
                stock_alerts.insert(0, f"Armario ajustado (relajacion nivel {attempt})")

            return {
                "main": main_slot, "alternatives": alternatives,
                "stock_alerts": stock_alerts,
                "formality_context": ctx.formality_label,
                "target_formality": ctx.target_formality,
            }

    return {
        "main": None, "alternatives": [], "stock_alerts": stock_alerts,
        "formality_context": ctx.formality_label, "target_formality": ctx.target_formality,
    }

# ─── CONTEXT PARSER (§4.3-4.4) ───────────────────────────────────────────────

_FORMALITY_KEYWORDS: list[tuple[int, list[str]]] = [
    (1, ["gym","gimnasio","entreno","entrenamiento","workout","training","deporte",
         "sport","run","running","correr","futbol","football","soccer","basket",
         "baloncesto","padel","tenis","tennis","crossfit","natacion","swim","yoga",
         "pilates","senderismo","hike","ruta","bici","ciclismo","cycling","escalada",
         "climbing","partido","match","caminata"]),
    (2, ["amigos","friends","cine","movie","pelicula","compras","shopping","paseo",
         "walk","parque","park","quedada","hangout","plan","videojuegos","gaming",
         "mercado","market","recados","errands","barbacoa","bbq","concierto","concert",
         "festival","playa","beach","piscina","pool","brunch","cumple","cumpleaños",
         "birthday"]),
    (3, ["clase","class","universidad","university","uni","facultad","campus",
         "instituto","cafeteria","coffee","coworking","biblioteca","library","estudio",
         "study","oficina","office","trabajo","work","taller","workshop","seminario",
         "seminar","laboratorio","lab","tutoria","mentoring","hackathon","charla",
         "talk","meetup","practicas","internship"]),
    (4, ["cita","date","reunion","meeting","cliente","client","cena","dinner",
         "restaurante","restaurant","demo","networking","evento","event","teatro",
         "theater","theatre","aniversario","anniversary","exposicion","exhibition",
         "conferencia","conference","iglesia","church","misa","visita","kickoff","junta"]),
    (5, ["entrevista","interview","boda","wedding","funeral","tanatorio",
         "presentacion","presentation","defensa","defense","tribunal","gala",
         "ceremonia","ceremony","premios","awards","opera","banquete","banquet",
         "comunion","bautizo","baptism","graduacion","graduation","juicio","court",
         "notario","notary","firma","signing"]),
]

_FORMALITY_LABELS = {1:"Deportivo",2:"Casual",3:"Smart casual",4:"Semiformal",5:"Formal"}

def _event_formality(title: str) -> Optional[int]:
    text = re.sub(r"[áàä]","a", re.sub(r"[éèë]","e", re.sub(r"[íìï]","i",
           re.sub(r"[óòö]","o", re.sub(r"[úùü]","u", title.lower()))))).strip()
    tokens = re.split(r"\W+", text)
    best = None
    for level, kws in _FORMALITY_KEYWORDS:
        for kw in kws:
            if any(kw in t for t in tokens):
                best = max(best or 0, level)
    # Ambiguity: cena+amigos → 2
    if best == 4 and any(t in tokens for t in ("amigos","casa","pizza","familia")): best = 2
    return best

def parse_context(
    events: list[dict],         # [{title, start_iso, end_iso?}]
    weather: dict,              # {temp_c, wind_kmh?, condition?, precip_pct?, temp_max?, temp_min?}
    user_season: str = "winter",
    now: Optional[datetime] = None,
) -> Context:
    now = now or datetime.now()
    today = now.date()
    wt = Weather(
        temp_c     = weather.get("temp_c", 18),
        wind_kmh   = weather.get("wind_kmh", 0),
        condition  = weather.get("condition", "cloudy"),
        precip_pct = weather.get("precip_pct", 0),
        temp_max   = weather.get("temp_max"),
        temp_min   = weather.get("temp_min"),
    )

    # Determine formality target from events 07:00-22:00
    window_start = now.replace(hour=7, minute=0, second=0)
    window_end   = now.replace(hour=22, minute=0, second=0)
    event_targets: list[tuple[int,int,int]] = []  # (target, start_h, end_h)
    for ev in events:
        try:
            start = datetime.fromisoformat(ev["start_iso"])
            end   = datetime.fromisoformat(ev.get("end_iso") or ev["start_iso"])
            end   = max(end, start + timedelta(hours=1))
        except Exception:
            continue
        if start > window_end or end < window_start: continue
        f = _event_formality(ev.get("title",""))
        if f: event_targets.append((f, start.hour, end.hour))

    if not event_targets:
        hour = now.hour
        target = 3 if 8 <= hour <= 18 else 2
        label = _FORMALITY_LABELS[target]
    else:
        target = max(t for t,_,_ in event_targets)
        label = _FORMALITY_LABELS[target]

    # Bimodal detection (§8.2)
    bimodal = False; afternoon_target = None; afternoon_label = None
    if len(event_targets) >= 2:
        t_min = min(t for t,_,_ in event_targets)
        t_max = target
        if t_max - t_min >= 2:
            # Check gap >= 90 min
            sorted_evs = sorted(event_targets, key=lambda x: x[1])
            for i in range(len(sorted_evs)-1):
                gap = (sorted_evs[i+1][1] - sorted_evs[i][2]) * 60
                if gap >= 90:
                    bimodal = True
                    afternoon_target = sorted_evs[-1][0]
                    afternoon_label = f"Outfit para las {sorted_evs[-1][1]:02d}:00 ({_FORMALITY_LABELS[afternoon_target]})"
                    target = sorted_evs[0][0]  # morning outfit uses lower target
                    label = _FORMALITY_LABELS[target]
                    break

    return Context(wt, target, label, today, user_season, bimodal,
                   afternoon_target, afternoon_label)

# ─── SLOT ↔ JSON SERIALIZATION ───────────────────────────────────────────────

def _item_to_dict(item: Optional[Item]) -> Optional[dict]:
    if item is None: return None
    return {
        "id": item.id, "name": item.name, "category": item.category,
        "subcategory": item.subcategory, "colors": item.colors,
        "formality": item.formality, "warmth": item.warmth,
        "reuse_days": item.reuse_days, "state": item.state, "tags": item.tags,
        "photo_url": item.photo_url, "fungible_group_id": item.fungible_group_id,
        "last_used": item.last_used.isoformat() if item.last_used else None,
        "uses_14d": item.uses_14d, "active": True, "notes": None,
    }

def slot_to_dict(slot: Slot) -> dict:
    return {
        "top":       _item_to_dict(slot.top),
        "bottom":    _item_to_dict(slot.bottom),
        "shoes":     _item_to_dict(slot.shoes),
        "outerwear": _item_to_dict(slot.outerwear),
        "headwear":  _item_to_dict(slot.headwear),
        "accessories": [_item_to_dict(a) for a in slot.accessories],
        "socks":     _item_to_dict(slot.socks),
        "underwear": _item_to_dict(slot.underwear),
        "score":     slot.score,
    }

# ─── SQL SCHEMA ───────────────────────────────────────────────────────────────

SCHEMA = """
CREATE TABLE IF NOT EXISTS clothing_items (
    id               SERIAL PRIMARY KEY,
    user_id          INTEGER NOT NULL DEFAULT 1,
    name             TEXT NOT NULL,
    category         TEXT NOT NULL CHECK (category IN ('tops','bottoms','shoes','outerwear','headwear','accessories','socks','underwear')),
    subcategory      TEXT NOT NULL DEFAULT '',
    colors           JSONB NOT NULL DEFAULT '[]',
    formality        INTEGER NOT NULL DEFAULT 3 CHECK (formality BETWEEN 1 AND 5),
    warmth           INTEGER NOT NULL DEFAULT 3 CHECK (warmth BETWEEN 1 AND 5),
    reuse_days       INTEGER NOT NULL DEFAULT 1,
    state            TEXT NOT NULL DEFAULT 'limpia' CHECK (state IN ('limpia','sucia','lavadora')),
    active           BOOLEAN NOT NULL DEFAULT TRUE,
    tags             TEXT[] NOT NULL DEFAULT '{}',
    notes            TEXT,
    photo_url        TEXT,
    fungible_group_id TEXT,
    last_used        DATE,
    uses_14d         INTEGER NOT NULL DEFAULT 0,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS outfit_confirmations (
    id             SERIAL PRIMARY KEY,
    user_id        INTEGER NOT NULL DEFAULT 1,
    confirmed_date DATE NOT NULL,
    item_ids       INTEGER[] NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_outfit_conf_user_date
    ON outfit_confirmations (user_id, confirmed_date DESC);

CREATE TABLE IF NOT EXISTS fungible_groups (
    id       TEXT PRIMARY KEY,
    user_id  INTEGER NOT NULL DEFAULT 1,
    category TEXT NOT NULL,
    label    TEXT NOT NULL,
    total    INTEGER NOT NULL DEFAULT 0,
    clean    INTEGER NOT NULL DEFAULT 0
);
"""

# ─── FASTAPI ROUTER ───────────────────────────────────────────────────────────
# Integrate with your existing DB session dependency (db: AsyncSession).
# Replace `get_db` and `get_current_user` with your actual dependencies.

try:
    from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
    from fastapi.responses import JSONResponse
    import sqlalchemy as sa
    from sqlalchemy.ext.asyncio import AsyncSession
    from typing import Any

    router = APIRouter(tags=["wardrobe"])

    # ── Placeholder dependencies — replace with your actual ones ─────────────
    async def _get_db() -> AsyncSession: ...          # type: ignore
    async def _get_user_id() -> int: return 1         # type: ignore
    # ─────────────────────────────────────────────────────────────────────────

    def _row_to_item(row: Any) -> Item:
        return Item(
            id=row.id, name=row.name, category=row.category,
            subcategory=row.subcategory or "", colors=row.colors or [],
            formality=row.formality, warmth=row.warmth, reuse_days=row.reuse_days,
            state=row.state, tags=list(row.tags or []),
            photo_url=row.photo_url, fungible_group_id=row.fungible_group_id,
            last_used=row.last_used, uses_14d=row.uses_14d or 0,
        )

    @router.get("/wardrobe")
    async def list_wardrobe(db: AsyncSession = Depends(_get_db),
                            uid: int = Depends(_get_user_id)):
        rows = (await db.execute(
            sa.text("SELECT * FROM clothing_items WHERE user_id=:u AND active=TRUE ORDER BY category, name"),
            {"u": uid}
        )).fetchall()
        return [_row_to_item(r).__dict__ for r in rows]

    @router.post("/wardrobe")
    async def create_clothing(body: dict, db: AsyncSession = Depends(_get_db),
                               uid: int = Depends(_get_user_id)):
        import json
        row = (await db.execute(sa.text("""
            INSERT INTO clothing_items
              (user_id,name,category,subcategory,colors,formality,warmth,
               reuse_days,state,tags,notes,fungible_group_id)
            VALUES (:u,:name,:cat,:sub,:colors::jsonb,:form,:warm,:reuse,'limpia',:tags,:notes,:fg)
            RETURNING *
        """), {
            "u": uid, "name": body["name"], "cat": body["category"],
            "sub": body.get("subcategory",""), "colors": json.dumps(body.get("colors",[])),
            "form": body.get("formality",3), "warm": body.get("warmth",3),
            "reuse": body.get("reuse_days",1),
            "tags": body.get("tags",[]), "notes": body.get("notes"),
            "fg": body.get("fungible_group_id"),
        })).fetchone()
        await db.commit()
        return _item_to_dict(_row_to_item(row))

    @router.patch("/wardrobe/{item_id}")
    async def update_clothing(item_id: int, body: dict,
                               db: AsyncSession = Depends(_get_db),
                               uid: int = Depends(_get_user_id)):
        import json
        allowed = {"name","category","subcategory","colors","formality","warmth",
                   "reuse_days","state","active","tags","notes","fungible_group_id"}
        sets, params = [], {"id": item_id, "u": uid}
        for k, v in body.items():
            if k not in allowed: continue
            params[k] = json.dumps(v) if k == "colors" else v
            sets.append(f"{k} = :{k}{'::jsonb' if k=='colors' else ''}")
        if not sets: raise HTTPException(400, "Nothing to update")
        row = (await db.execute(sa.text(
            f"UPDATE clothing_items SET {','.join(sets)} WHERE id=:id AND user_id=:u RETURNING *"
        ), params)).fetchone()
        if not row: raise HTTPException(404)
        await db.commit()
        return _item_to_dict(_row_to_item(row))

    @router.delete("/wardrobe/{item_id}")
    async def delete_clothing(item_id: int, db: AsyncSession = Depends(_get_db),
                               uid: int = Depends(_get_user_id)):
        await db.execute(sa.text(
            "UPDATE clothing_items SET active=FALSE WHERE id=:id AND user_id=:u"
        ), {"id": item_id, "u": uid})
        await db.commit()
        return {"status": "ok"}

    @router.post("/wardrobe/{item_id}/photo")
    async def upload_clothing_photo(item_id: int, file: UploadFile = File(...),
                                     db: AsyncSession = Depends(_get_db),
                                     uid: int = Depends(_get_user_id)):
        # Delegate to your existing upload_to_storage utility
        from your_app.storage import upload_to_storage  # type: ignore
        data = await file.read()
        url = await upload_to_storage(f"clothing/{uid}/{item_id}.jpg", data)
        row = (await db.execute(sa.text(
            "UPDATE clothing_items SET photo_url=:url WHERE id=:id AND user_id=:u RETURNING *"
        ), {"url": url, "id": item_id, "u": uid})).fetchone()
        await db.commit()
        return _item_to_dict(_row_to_item(row))

    @router.post("/wardrobe/{item_id}/wear")
    async def wear_item(item_id: int, db: AsyncSession = Depends(_get_db),
                        uid: int = Depends(_get_user_id)):
        today_str = date.today().isoformat()
        row = (await db.execute(sa.text("""
            UPDATE clothing_items SET last_used = :d,
              uses_14d = (
                SELECT COUNT(*) FROM outfit_confirmations
                WHERE :id = ANY(item_ids) AND user_id=:u
                  AND confirmed_date >= (CURRENT_DATE - INTERVAL '13 days')
              ) + 1
            WHERE id=:id AND user_id=:u RETURNING *
        """), {"d": today_str, "id": item_id, "u": uid})).fetchone()
        if not row: raise HTTPException(404)
        await db.commit()
        return _item_to_dict(_row_to_item(row))

    @router.post("/wardrobe/{item_id}/dirty")
    async def dirty_item(item_id: int, db: AsyncSession = Depends(_get_db),
                         uid: int = Depends(_get_user_id)):
        row = (await db.execute(sa.text(
            "UPDATE clothing_items SET state='sucia' WHERE id=:id AND user_id=:u RETURNING *"
        ), {"id": item_id, "u": uid})).fetchone()
        if not row: raise HTTPException(404)
        await db.commit()
        return _item_to_dict(_row_to_item(row))

    @router.post("/wardrobe/{item_id}/washed")
    async def washed_item(item_id: int, db: AsyncSession = Depends(_get_db),
                          uid: int = Depends(_get_user_id)):
        row = (await db.execute(sa.text(
            "UPDATE clothing_items SET state='limpia' WHERE id=:id AND user_id=:u RETURNING *"
        ), {"id": item_id, "u": uid})).fetchone()
        if not row: raise HTTPException(404)
        await db.commit()
        return _item_to_dict(_row_to_item(row))

    @router.get("/wardrobe/outfit/today")
    async def outfit_today(db: AsyncSession = Depends(_get_db),
                           uid: int = Depends(_get_user_id)):
        today = date.today()
        # Load items
        rows = (await db.execute(sa.text(
            "SELECT * FROM clothing_items WHERE user_id=:u AND active=TRUE AND state='limpia'"
        ), {"u": uid})).fetchall()
        items = [_row_to_item(r) for r in rows]

        # Update uses_14d cache
        for item in items:
            count_row = (await db.execute(sa.text("""
                SELECT COUNT(DISTINCT confirmed_date) FROM outfit_confirmations
                WHERE :id = ANY(item_ids) AND user_id=:u
                  AND confirmed_date >= (CURRENT_DATE - INTERVAL '13 days')
            """), {"id": item.id, "u": uid})).scalar()
            item.uses_14d = count_row or 0

        # Recent outfit IDs (last 10 days for freshness)
        conf_rows = (await db.execute(sa.text("""
            SELECT item_ids FROM outfit_confirmations
            WHERE user_id=:u AND confirmed_date >= (CURRENT_DATE - INTERVAL '9 days')
            ORDER BY confirmed_date DESC
        """), {"u": uid})).fetchall()
        recent_outfit_ids = [frozenset(r.item_ids) for r in conf_rows]
        recent_pair_ids = [
            frozenset([a, b])
            for ids in recent_outfit_ids
            for i, a in enumerate(list(ids))
            for b in list(ids)[i+1:]
        ]

        # Load fungibles
        fg_rows = (await db.execute(sa.text(
            "SELECT id, label, total, clean FROM fungible_groups WHERE user_id=:u"
        ), {"u": uid})).fetchall()
        fungibles = {r.id: {"label": r.label, "total": r.total, "clean": r.clean}
                     for r in fg_rows}

        # Weather + events from context  (replace with your actual data fetchers)
        from your_app.weather import get_weather_today   # type: ignore
        from your_app.calendar import get_events_today   # type: ignore
        from your_app.user import get_user_settings      # type: ignore

        weather_data = await get_weather_today(uid)
        events_data  = await get_events_today(uid)
        settings     = await get_user_settings(uid)
        user_season  = settings.get("color_season", "winter")

        ctx = parse_context(events_data, weather_data, user_season, datetime.now())
        result = suggest_outfit(items, ctx, recent_outfit_ids, recent_pair_ids, fungibles)

        if result["main"] is None:
            return JSONResponse({"error": "No se puede componer un outfit válido", "stock_alerts": result["stock_alerts"]}, 503)

        response = {
            "main":             slot_to_dict(result["main"]),
            "alternatives":     [slot_to_dict(a) for a in result["alternatives"]],
            "ai_text":          None,
            "stock_alerts":     result["stock_alerts"],
            "formality_context":result["formality_context"],
            "target_formality": result["target_formality"],
        }
        if ctx.bimodal and ctx.afternoon_target:
            afternoon_ctx = Context(
                ctx.weather, ctx.afternoon_target,
                _FORMALITY_LABELS[ctx.afternoon_target],
                ctx.today, ctx.user_season,
            )
            aresult = suggest_outfit(items, afternoon_ctx, recent_outfit_ids, recent_pair_ids, fungibles)
            if aresult["main"]:
                response["afternoon"] = slot_to_dict(aresult["main"])
                response["afternoon_label"] = ctx.afternoon_label

        return response

    @router.get("/ai/outfit")
    async def ai_outfit(db: AsyncSession = Depends(_get_db),
                        uid: int = Depends(_get_user_id)):
        from your_app.ai import ask_claude  # type: ignore
        text = await ask_claude("outfit")
        return {"text": text}

except ImportError:
    router = None  # type: ignore  # FastAPI not available (unit test context)
