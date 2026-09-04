"""Plan de comidas semanal + generador de lista de la compra.

El recetario (ingredientes, platos y qué se come cada día) vive en la base de
datos y se edita desde la app. Antes era una rotación fija en el código.

`seed_diet()` siembra un recetario de ejemplo la primera vez, solo para que la
pestaña no aparezca vacía: se puede borrar o cambiar entero.

Si cocinas de dos en dos (la cena de un día rinde también la comida del
siguiente), deja la comida sin asignar y el plan la deduce de la cena de ayer.
"""
import os

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from . import config
from .db import engine
from .models import Dish, DishIngredient, FoodLog, Ingredient, MealPlanDay, ShoppingItem

router = APIRouter(prefix="/api/diet")

WEEKDAYS = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]

SEED_MARKER = os.path.join(os.path.dirname(__file__), "..", ".diet_seeded")


# ── Recetario de ejemplo ───────────────────────────────────────────────────
# Solo se usa la primera vez. (kcal, proteína, unidad): "g" = por 100 g,
# "u" = por pieza.

EXAMPLE_INGREDIENTS: dict[str, tuple[float, float, str]] = {
    "Arroz": (130, 2.7, "g"),
    "Pollo": (165, 31, "g"),
    "Tomate frito": (80, 1.5, "g"),
    "Queso rallado": (350, 25, "g"),
    "Cebolla": (40, 1.1, "g"),
    "Pimiento": (30, 1.0, "g"),
    "Pasta": (158, 5.8, "g"),
    "Carne picada": (250, 18, "g"),
    "Atún": (116, 26, "g"),
    "Lentejas": (116, 9, "g"),
    "Garbanzos": (164, 9, "g"),
    "Patata": (77, 2, "g"),
    "Brócoli": (34, 2.8, "g"),
    "Aceite de oliva": (884, 0, "g"),
    "Yogur griego": (100, 9, "g"),
    "Fruta": (52, 0.6, "g"),
    "Avena": (389, 17, "g"),
    "Tortillas": (150, 4, "u"),
    "Huevos": (70, 6, "u"),
}

EXAMPLE_DISHES: dict[str, tuple[str, list[tuple[str, float, str]]]] = {
    "Arroz con pollo y tomate": ("main", [
        ("Arroz", 300, "g"), ("Pollo", 150, "g"), ("Tomate frito", 200, "g"),
        ("Queso rallado", 30, "g"),
    ]),
    "Pasta boloñesa": ("main", [
        ("Pasta", 200, "g"), ("Carne picada", 200, "g"), ("Tomate frito", 200, "g"),
    ]),
    "Fajitas de pollo": ("main", [
        ("Tortillas", 4, "u"), ("Pollo", 150, "g"), ("Pimiento", 50, "g"),
        ("Cebolla", 50, "g"),
    ]),
    "Lentejas con verduras": ("main", [
        ("Lentejas", 250, "g"), ("Patata", 100, "g"), ("Cebolla", 50, "g"),
        ("Aceite de oliva", 10, "g"),
    ]),
    "Pollo con patata y brócoli": ("main", [
        ("Pollo", 200, "g"), ("Patata", 250, "g"), ("Brócoli", 150, "g"),
        ("Aceite de oliva", 10, "g"),
    ]),
    "Garbanzos con atún": ("main", [
        ("Garbanzos", 250, "g"), ("Atún", 120, "g"), ("Tomate frito", 100, "g"),
    ]),
    "Tortilla de patata": ("main", [
        ("Huevos", 3, "u"), ("Patata", 250, "g"), ("Cebolla", 50, "g"),
        ("Aceite de oliva", 15, "g"),
    ]),
    "Yogur con fruta": ("side", [("Yogur griego", 300, "g"), ("Fruta", 200, "g")]),
    "Avena con fruta": ("side", [("Avena", 80, "g"), ("Fruta", 150, "g")]),
}

# Cena de cada día, lunes(0) a domingo(6).
EXAMPLE_ROTATION = [
    "Arroz con pollo y tomate",
    "Pasta boloñesa",
    "Fajitas de pollo",
    "Lentejas con verduras",
    "Pollo con patata y brócoli",
    "Garbanzos con atún",
    "Tortilla de patata",
]


def seed_diet() -> None:
    """Siembra el recetario de ejemplo una sola vez."""
    if os.path.exists(SEED_MARKER):
        return
    with Session(engine) as session:
        if session.exec(select(Dish)).first():
            _mark_seeded()
            return

        ingredients: dict[str, Ingredient] = {}
        for name, (kcal, protein, unit) in EXAMPLE_INGREDIENTS.items():
            row = Ingredient(name=name, kcal=kcal, protein=protein, unit=unit)
            session.add(row)
            ingredients[name] = row
        session.commit()

        dishes: dict[str, Dish] = {}
        for name, (role, items) in EXAMPLE_DISHES.items():
            dish = Dish(name=name, role=role)
            session.add(dish)
            session.commit()
            session.refresh(dish)
            dishes[name] = dish
            for ing_name, qty, unit in items:
                ingredient = ingredients.get(ing_name)
                if ingredient is None:
                    continue
                session.add(DishIngredient(
                    dish_id=dish.id, ingredient_id=ingredient.id, qty=qty, unit=unit,
                ))
        session.commit()

        breakfast = dishes.get("Yogur con fruta")
        for weekday, dish_name in enumerate(EXAMPLE_ROTATION):
            dinner = dishes.get(dish_name)
            session.add(MealPlanDay(
                weekday=weekday,
                dinner_dish_id=dinner.id if dinner else None,
                breakfast_dish_id=breakfast.id if breakfast else None,
                snack_dish_id=breakfast.id if breakfast else None,
            ))
        session.commit()
    _mark_seeded()


def _mark_seeded() -> None:
    try:
        open(SEED_MARKER, "a").close()
    except OSError:
        pass


# ── Helpers ────────────────────────────────────────────────────────────────

def _dish_items(session: Session, dish_id: int) -> list[tuple[str, float, str]]:
    """(ingrediente, cantidad, unidad) de un plato."""
    rows = session.exec(
        select(DishIngredient, Ingredient)
        .where(DishIngredient.dish_id == dish_id)
        .where(Ingredient.id == DishIngredient.ingredient_id)
    ).all()
    return [(ing.name, di.qty, di.unit) for di, ing in rows]


def _macros(session: Session, dish_id: int) -> tuple[int, float]:
    """(kcal, proteína) de una ración, sumando sus ingredientes."""
    kcal = 0.0
    protein = 0.0
    rows = session.exec(
        select(DishIngredient, Ingredient)
        .where(DishIngredient.dish_id == dish_id)
        .where(Ingredient.id == DishIngredient.ingredient_id)
    ).all()
    for di, ing in rows:
        factor = di.qty / 100 if di.unit == "g" else di.qty
        kcal += ing.kcal * factor
        protein += ing.protein * factor
    return round(kcal), round(protein, 1)


def _plan_rows(session: Session) -> dict[int, MealPlanDay]:
    return {row.weekday: row for row in session.exec(select(MealPlanDay)).all()}


# ── Endpoints ──────────────────────────────────────────────────────────────

@router.get("/plan")
def plan():
    """Plan de la semana: cada día con desayuno, comida, merienda y cena."""
    today = config.now_local().weekday()
    with Session(engine) as session:
        rows = _plan_rows(session)
        names = {d.id: d.name for d in session.exec(select(Dish)).all()}

        days = []
        for i, label in enumerate(WEEKDAYS):
            row = rows.get(i)
            yesterday = rows.get((i - 1) % 7)
            # Sin comida asignada: se asume la cena de ayer (cocinar de dos en dos).
            lunch_id = (row.lunch_dish_id if row else None) or (
                yesterday.dinner_dish_id if yesterday else None
            )
            days.append({
                "weekday": label,
                "is_today": i == today,
                "breakfast": names.get(row.breakfast_dish_id) if row else None,
                "lunch": names.get(lunch_id),
                "snack": names.get(row.snack_dish_id) if row else None,
                "dinner": names.get(row.dinner_dish_id) if row else None,
            })

        dishes = {}
        macros = {}
        for dish in session.exec(select(Dish)).all():
            dishes[dish.name] = [list(x) for x in _dish_items(session, dish.id)]
            kcal, protein = _macros(session, dish.id)
            macros[dish.name] = {"kcal": kcal, "protein": protein}

        return {"days": days, "dishes": dishes, "macros": macros}


class MealPlanIn(BaseModel):
    weekday: int = Field(ge=0, le=6)
    breakfast_dish_id: int | None = None
    lunch_dish_id: int | None = None
    snack_dish_id: int | None = None
    dinner_dish_id: int | None = None


@router.post("/plan")
def set_plan_day(payload: MealPlanIn):
    """Cambia las comidas de un día del plan."""
    with Session(engine) as session:
        row = session.exec(
            select(MealPlanDay).where(MealPlanDay.weekday == payload.weekday)
        ).first()
        if row is None:
            row = MealPlanDay(weekday=payload.weekday)
        for field in ("breakfast_dish_id", "lunch_dish_id", "snack_dish_id", "dinner_dish_id"):
            setattr(row, field, getattr(payload, field))
        session.add(row)
        session.commit()
    return plan()


@router.get("/dishes")
def list_dishes():
    with Session(engine) as session:
        out = []
        for dish in session.exec(select(Dish).order_by(Dish.name)).all():
            kcal, protein = _macros(session, dish.id)
            out.append({
                "id": dish.id,
                "name": dish.name,
                "role": dish.role,
                "kcal": kcal,
                "protein": protein,
                "ingredients": [
                    {"name": n, "qty": q, "unit": u} for n, q, u in _dish_items(session, dish.id)
                ],
            })
        return out


class DishIngredientIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    qty: float = Field(gt=0, le=10000)
    unit: str = Field(default="g", pattern="^(g|u)$")
    kcal: float | None = Field(default=None, ge=0, le=1000)
    protein: float | None = Field(default=None, ge=0, le=100)


class DishIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    role: str = Field(default="main", pattern="^(main|side)$")
    ingredients: list[DishIngredientIn] = []


@router.post("/dishes")
def create_dish(payload: DishIn):
    """Crea un plato. Los ingredientes que no existan se dan de alta con los
    valores nutricionales que se pasen."""
    with Session(engine) as session:
        if session.exec(select(Dish).where(Dish.name == payload.name)).first():
            raise HTTPException(409, "Ya existe un plato con ese nombre")

        dish = Dish(name=payload.name, role=payload.role)
        session.add(dish)
        session.commit()
        session.refresh(dish)

        for item in payload.ingredients:
            ingredient = session.exec(
                select(Ingredient).where(Ingredient.name == item.name)
            ).first()
            if ingredient is None:
                ingredient = Ingredient(
                    name=item.name,
                    kcal=item.kcal or 0,
                    protein=item.protein or 0,
                    unit=item.unit,
                )
                session.add(ingredient)
                session.commit()
                session.refresh(ingredient)
            session.add(DishIngredient(
                dish_id=dish.id, ingredient_id=ingredient.id, qty=item.qty, unit=item.unit,
            ))
        session.commit()
        kcal, protein = _macros(session, dish.id)
        return {"id": dish.id, "name": dish.name, "role": dish.role,
                "kcal": kcal, "protein": protein}


@router.delete("/dishes/{dish_id}")
def delete_dish(dish_id: int):
    with Session(engine) as session:
        dish = session.get(Dish, dish_id)
        if dish is None:
            raise HTTPException(404, "Plato desconocido")
        for row in session.exec(
            select(DishIngredient).where(DishIngredient.dish_id == dish_id)
        ).all():
            session.delete(row)
        # Quitarlo del plan para no dejar referencias colgando
        for row in session.exec(select(MealPlanDay)).all():
            changed = False
            for field in ("breakfast_dish_id", "lunch_dish_id", "snack_dish_id", "dinner_dish_id"):
                if getattr(row, field) == dish_id:
                    setattr(row, field, None)
                    changed = True
            if changed:
                session.add(row)
        session.delete(dish)
        session.commit()
    return {"status": "ok"}


def _ingredients(scope: str) -> dict[str, tuple[float, str]]:
    """Suma de ingredientes del plan. scope='week' = semana entera;
    'remaining' = de hoy al domingo (lo que aún falta por comprar)."""
    totals: dict[str, tuple[float, str]] = {}

    def add(items: list[tuple[str, float, str]], times: float) -> None:
        for name, qty, unit in items:
            prev = totals.get(name, (0.0, unit))
            totals[name] = (prev[0] + qty * times, unit)

    with Session(engine) as session:
        rows = _plan_rows(session)
        cache: dict[int, list[tuple[str, float, str]]] = {}

        def items_of(dish_id: int | None) -> list[tuple[str, float, str]]:
            if dish_id is None:
                return []
            if dish_id not in cache:
                cache[dish_id] = _dish_items(session, dish_id)
            return cache[dish_id]

        start = config.now_local().weekday() if scope == "remaining" else 0
        for weekday in range(start, 7):
            row = rows.get(weekday)
            if row is None:
                continue
            add(items_of(row.dinner_dish_id), 1)
            add(items_of(row.breakfast_dish_id), 1)
            add(items_of(row.snack_dish_id), 1)

            lunch_id = row.lunch_dish_id
            if lunch_id is not None:
                add(items_of(lunch_id), 1)
            elif weekday > start:
                # La comida sale de la cena de ayer: hay que cocinar el doble.
                yesterday = rows.get((weekday - 1) % 7)
                if yesterday:
                    add(items_of(yesterday.dinner_dish_id), 1)

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
    """Registra un plato del plan en Macros con sus kcal/proteína estimadas."""
    with Session(engine) as session:
        dish = session.exec(select(Dish).where(Dish.name == payload.dish)).first()
        if dish is None:
            raise HTTPException(404, "Plato desconocido")
        kcal, protein = _macros(session, dish.id)
        row = FoodLog(name=dish.name, kcal=kcal, protein=protein)
        session.add(row)
        session.commit()
        session.refresh(row)
        return {"id": row.id, "at": row.at, "name": row.name,
                "kcal": row.kcal, "protein": row.protein}


def _fmt(name: str, qty: float, unit: str) -> str:
    if unit == "g" and qty >= 1000:
        amount = f"{qty / 1000:g} kg"
    elif unit == "u":
        amount = f"{qty:g} ud"
    else:
        amount = f"{qty:g} g"
    return f"{name} — {amount}"
