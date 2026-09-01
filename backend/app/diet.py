"""Dieta semanal de Daniel + generador de lista de la compra.

Estructura: cada plato principal se cocina una vez y rinde DOS raciones: la
cena de un dia y la comida del dia siguiente. Por eso cada plato de la
rotacion se consume 2 veces por semana. El desayuno y la merienda son siempre
yogur con fruta.

La rotacion esta ordenada para no repetir estilos seguidos (los 2 platos sin
pollo —gnocchis e higado— cortan las rachas; los asiaticos van separados).
"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from . import config
from .db import engine
from .models import FoodLog, ShoppingItem

router = APIRouter(prefix="/api/diet")

# Valores nutricionales aproximados por ingrediente. Para unidad "g" son por
# 100 g; para unidad "u" son por pieza. Sirven para estimar las macros de cada
# plato y poder registrarlo en Macros con un toque.
#   (kcal, proteina_g)
NUTRITION: dict[str, tuple[float, float]] = {
    "Arroz": (130, 2.7),            # cocido
    "Pollo": (165, 31),
    "Tomate frito": (80, 1.5),
    "Queso rallado": (350, 25),
    "Cebolla": (40, 1.1),
    "Pimiento": (30, 1.0),
    "Salsa agridulce": (150, 0.5),
    "Gnocchis": (150, 3.5),         # cocidos
    "Carne picada": (250, 18),
    "Anacardos": (553, 18),
    "Salsa soja": (60, 8),
    "Vino de arroz": (130, 0),
    "Aceite de sésamo": (884, 0),
    "Miel": (304, 0.3),
    "Hígado de ternera": (135, 20),
    "Salsa hoisin": (220, 2),
    "Yogur griego": (100, 9),
    "Fruta": (52, 0.6),
    # por unidad:
    "Tortillas": (150, 4),          # cada wrap
    "Huevos": (70, 6),              # cada huevo
}

# Cada plato: lista de (ingrediente, cantidad, unidad). Nombres normalizados
# (arroz cocido -> Arroz, tomate frito hida -> Tomate frito) para sumar bien.
DISHES: dict[str, list[tuple[str, float, str]]] = {
    "Arroz pollo tomate frito": [
        ("Arroz", 300, "g"), ("Pollo", 150, "g"), ("Tomate frito", 200, "g"),
        ("Queso rallado", 30, "g"),
    ],
    "Pollo agridulce": [
        ("Arroz", 250, "g"), ("Pollo", 150, "g"), ("Cebolla", 50, "g"),
        ("Pimiento", 50, "g"), ("Salsa agridulce", 50, "g"),
    ],
    "Gnocchis ground beef": [
        ("Gnocchis", 200, "g"), ("Carne picada", 200, "g"), ("Tomate frito", 200, "g"),
    ],
    "Fajitas": [
        ("Tortillas", 4, "u"), ("Pollo", 150, "g"), ("Tomate frito", 200, "g"),
        ("Pimiento", 50, "g"), ("Cebolla", 50, "g"), ("Anacardos", 20, "g"),
    ],
    "Bulgogi chicken": [
        ("Arroz", 250, "g"), ("Pollo", 200, "g"), ("Cebolla", 50, "g"),
        ("Salsa soja", 10, "g"), ("Vino de arroz", 15, "g"),
        ("Aceite de sésamo", 5, "g"), ("Miel", 10, "g"),
    ],
    "Arroz con hígado": [
        ("Arroz", 300, "g"), ("Hígado de ternera", 200, "g"), ("Huevos", 2, "u"),
        ("Cebolla", 100, "g"),
    ],
    "Cashew chicken": [
        ("Arroz", 200, "g"), ("Pollo", 200, "g"), ("Anacardos", 50, "g"),
        ("Salsa hoisin", 20, "g"), ("Salsa soja", 10, "g"), ("Miel", 20, "g"),
    ],
    "Yogur con fruta": [("Yogur griego", 300, "g"), ("Fruta", 200, "g")],
}

# Orden optimo de cenas, lunes(0) a domingo(6). La cena de un dia es la comida
# del siguiente.
ROTATION = [
    "Arroz pollo tomate frito",  # Lunes
    "Pollo agridulce",           # Martes
    "Gnocchis ground beef",      # Miercoles
    "Fajitas",                   # Jueves
    "Bulgogi chicken",           # Viernes
    "Arroz con hígado",          # Sabado
    "Cashew chicken",            # Domingo
]
YOGUR = "Yogur con fruta"
WEEKDAYS = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]


def dish_macros(dish: str) -> tuple[int, float]:
    """Estima (kcal, proteina) de una racion de un plato desde sus ingredientes."""
    kcal = 0.0
    protein = 0.0
    for name, qty, unit in DISHES.get(dish, []):
        per = NUTRITION.get(name)
        if not per:
            continue
        factor = qty / 100 if unit == "g" else qty  # "g": por 100g; "u": por pieza
        kcal += per[0] * factor
        protein += per[1] * factor
    return round(kcal), round(protein, 1)


@router.get("/plan")
def plan():
    """Plan de la semana: cada dia con desayuno, comida, merienda y cena."""
    today = config.now_local().weekday()
    days = []
    for i, name in enumerate(WEEKDAYS):
        dinner = ROTATION[i]
        lunch = ROTATION[(i - 1) % 7]  # la cena de ayer
        days.append({
            "weekday": name,
            "is_today": i == today,
            "breakfast": YOGUR,
            "lunch": lunch,
            "snack": YOGUR,
            "dinner": dinner,
        })
    macros = {k: {"kcal": dish_macros(k)[0], "protein": dish_macros(k)[1]} for k in DISHES}
    return {
        "days": days,
        "dishes": {k: [list(x) for x in v] for k, v in DISHES.items()},
        "macros": macros,
    }


def _ingredients(scope: str) -> dict[str, tuple[float, str]]:
    """Suma de ingredientes. scope='week' = semana entera; scope='remaining' =
    solo de hoy al domingo (lo que aun falta por comprar)."""
    totals: dict[str, tuple[float, str]] = {}

    def add(items, times):
        for name, qty, unit in items:
            prev = totals.get(name, (0, unit))
            totals[name] = (prev[0] + qty * times, unit)

    if scope == "remaining":
        today = config.now_local().weekday()
        for i in range(today, 7):  # de hoy a domingo
            add(DISHES[ROTATION[i]], 1)           # cena de cada dia restante
            if i > today:                          # comida = cena de ayer
                add(DISHES[ROTATION[i - 1]], 1)
            add(DISHES[YOGUR], 2)                  # desayuno + merienda
    else:
        for dish in ROTATION:  # cada plato se come 2 veces (cena + comida)
            add(DISHES[dish], 2)
        add(DISHES[YOGUR], 14)  # desayuno + merienda, 7 dias
    return totals


@router.get("/shopping-preview")
def shopping_preview(scope: str = "remaining"):
    totals = _ingredients(scope)
    items = [
        {"text": _fmt(name, qty, unit)}
        for name, (qty, unit) in sorted(totals.items())
    ]
    return {"items": items}


@router.post("/shopping")
def add_week_to_shopping(scope: str = "remaining"):
    """Vuelca la compra en la lista (sin duplicar lo ya puesto). Por defecto
    solo lo que falta de hoy al domingo."""
    totals = _ingredients(scope)
    with Session(engine) as session:
        existing = {s.text.lower() for s in session.exec(select(ShoppingItem)).all()}
        added = 0
        for name, (qty, unit) in sorted(totals.items()):
            text = _fmt(name, qty, unit)
            if text.lower() not in existing:
                session.add(ShoppingItem(text=text))
                added += 1
        session.commit()
    return {"added": added}


class LogMealIn(BaseModel):
    dish: str = Field(min_length=1, max_length=120)


@router.post("/log-meal")
def log_meal(payload: LogMealIn):
    """Registra un plato del plan en Macros con sus kcal/proteina estimadas."""
    if payload.dish not in DISHES:
        raise HTTPException(404, "Plato desconocido")
    kcal, protein = dish_macros(payload.dish)
    with Session(engine) as session:
        row = FoodLog(name=payload.dish, kcal=kcal, protein=protein)
        session.add(row)
        session.commit()
        session.refresh(row)
        return {"id": row.id, "at": row.at, "name": row.name, "kcal": row.kcal, "protein": row.protein}


def _fmt(name: str, qty: float, unit: str) -> str:
    if unit == "g" and qty >= 1000:
        amount = f"{qty / 1000:g} kg"
    elif unit == "u":
        amount = f"{qty:g} ud"
    else:
        amount = f"{qty:g} g"
    return f"{name} — {amount}"
