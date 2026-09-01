"""Genera app/exercises_catalog.py con el catalogo completo de ejercicios
de wger.de (open source, CC-BY-SA). Se corre UNA vez en local; el resultado
queda commiteado y seed.add_gym_exercises() lo siembra.

Uso:  python scripts/fetch_exercises.py   (desde backend/)
"""
import json
import unicodedata
import urllib.request

API = "https://wger.de/api/v2/exerciseinfo/?limit=100&offset={offset}"
ES, EN = 4, 2

# musculo de wger (name_en o name) -> grupo de la app
MUSCLE_MAP = {
    "quads": "Pierna", "hamstrings": "Pierna", "glutes": "Pierna",
    "calves": "Pierna", "soleus": "Pierna", "adductors": "Pierna",
    "abductors": "Pierna",
    "chest": "Pecho",
    "lats": "Espalda", "trapezius": "Espalda", "back": "Espalda",
    "lower back": "Espalda", "erector spinae": "Espalda",
    "biceps": "Biceps", "brachialis": "Biceps", "brachioradialis": "Biceps",
    "triceps": "Triceps",
    "shoulders": "Hombros", "front delts": "Hombros", "rear delts": "Hombros",
    "side delts": "Hombros", "deltoid": "Hombros",
    "abs": "Core", "obliques": "Core", "serratus anterior": "Core",
}

CATEGORY_MAP = {
    "Abs": "Core", "Arms": "Biceps", "Back": "Espalda", "Calves": "Pierna",
    "Cardio": "Cardio", "Chest": "Pecho", "Legs": "Pierna", "Shoulders": "Hombros",
}

EQUIPMENT_MAP = {
    "Barbell": "barra", "SZ-Bar": "barra", "Dumbbell": "mancuernas",
    "Kettlebell": "mancuernas", "Gym mat": "peso corporal",
    "none (bodyweight exercise)": "peso corporal", "Pull-up bar": "peso corporal",
    "Swiss Ball": "peso corporal", "Resistance band": "polea",
    # OJO: no mapear "Bench"/"Incline bench" a barra — un banco no determina el
    # material y metia los press de mancuerna bajo barra. El material real se
    # infiere del nombre con seed.infer_equipment().
}


def fetch_all():
    items = []
    offset = 0
    while True:
        with urllib.request.urlopen(API.format(offset=offset), timeout=30) as r:
            data = json.load(r)
        items.extend(data["results"])
        if not data["next"]:
            return items
        offset += 100


def pick_name(ex):
    by_lang = {t["language"]: (t.get("name") or "").strip() for t in ex.get("translations", [])}
    return by_lang.get(ES) or by_lang.get(EN) or ""


def pick_muscle(ex):
    for m in ex.get("muscles", []) + ex.get("muscles_secondary", []):
        key = (m.get("name_en") or m.get("name") or "").strip().lower()
        if key in MUSCLE_MAP:
            return MUSCLE_MAP[key]
    cat = (ex.get("category") or {}).get("name", "")
    return CATEGORY_MAP.get(cat, "Core")


def pick_equipment_fallback(ex):
    for e in ex.get("equipment", []):
        name = (e.get("name") or "").strip()
        if name in EQUIPMENT_MAP:
            return EQUIPMENT_MAP[name]
    return "peso corporal"


def norm(s):
    s = unicodedata.normalize("NFKD", s.lower())
    return "".join(c for c in s if not unicodedata.combining(c)).strip()


def main():
    raw = fetch_all()
    print(f"descargados: {len(raw)}")
    seen = set()
    out = []
    for ex in raw:
        name = pick_name(ex)[:100]
        if len(name) < 3:
            continue
        key = norm(name)
        if key in seen:
            continue
        seen.add(key)
        # material: prioridad a la inferencia por nombre; si no, fallback wger
        from app.seed import infer_equipment
        out.append((name, pick_muscle(ex), infer_equipment(name, pick_equipment_fallback(ex))))
    out.sort(key=lambda x: (x[1], norm(x[0])))
    print(f"catalogo final: {len(out)}")

    with open("app/exercises_catalog.py", "w", encoding="utf-8") as f:
        f.write('"""Catalogo de ejercicios generado desde wger.de (CC-BY-SA).\n')
        f.write('Regenerar con: python scripts/fetch_exercises.py\n"""\n\n')
        f.write("WGER_EXERCISES = [\n")
        for name, muscle, equipment in out:
            f.write(f"    ({name!r}, {muscle!r}, {equipment!r}),\n")
        f.write("]\n")
    print("escrito app/exercises_catalog.py")


if __name__ == "__main__":
    main()
