"""Plantillas de rutina para elegir al empezar.

Antes el seed creaba directamente un split concreto de 5 días. Ahora se
ofrecen varias plantillas y el usuario aplica la que le encaje (o ninguna, y
se crea las suyas a mano).

Cada plantilla: id, nombre, descripción, días por semana y una lista de
rutinas (nombre, weekday, ejercicios). weekday: lunes=0 ... domingo=6.
"""
from fastapi import APIRouter, HTTPException
from sqlmodel import Session, select

from .db import engine
from .models import Exercise, Routine, RoutineExercise

router = APIRouter(prefix="/api/routine-templates")


TEMPLATES: dict[str, dict] = {
    "full_body_3": {
        "name": "Cuerpo completo (3 días)",
        "description": "Lunes, miércoles y viernes. Lo más eficiente si empiezas.",
        "days_per_week": 3,
        "sets": 3,
        "routines": [
            ("Cuerpo completo A", 0, [
                "Sentadilla", "Press banca", "Remo con barra",
                "Press militar", "Curl con barra",
            ]),
            ("Cuerpo completo B", 2, [
                "Peso muerto", "Press inclinado con mancuernas", "Jalon al pecho",
                "Elevaciones laterales", "Press frances",
            ]),
            ("Cuerpo completo C", 4, [
                "Prensa de pierna", "Press con mancuernas", "Remo en polea baja",
                "Face pull", "Curl martillo",
            ]),
        ],
    },
    "upper_lower_4": {
        "name": "Torso / Pierna (4 días)",
        "description": "Lunes, martes, jueves y viernes. Buen equilibrio entre volumen y descanso.",
        "days_per_week": 4,
        "sets": 3,
        "routines": [
            ("Torso A", 0, [
                "Press banca", "Remo con barra", "Press militar",
                "Jalon al pecho", "Curl con barra", "Press frances",
            ]),
            ("Pierna A", 1, [
                "Sentadilla", "Peso muerto rumano", "Prensa de pierna",
                "Curl femoral", "Elevacion de gemelos",
            ]),
            ("Torso B", 3, [
                "Press inclinado con mancuernas", "Dominadas", "Elevaciones laterales",
                "Remo en polea baja", "Curl martillo", "Extension de triceps en polea",
            ]),
            ("Pierna B", 4, [
                "Peso muerto", "Extension de cuadriceps", "Zancadas",
                "Curl femoral", "Elevacion de gemelos",
            ]),
        ],
    },
    "ppl_6": {
        "name": "Push / Pull / Pierna (6 días)",
        "description": "Dos vueltas por semana. Para quien ya lleva tiempo entrenando.",
        "days_per_week": 6,
        "sets": 3,
        "routines": [
            ("Empuje A", 0, [
                "Press banca", "Press militar", "Press inclinado con mancuernas",
                "Elevaciones laterales", "Extension de triceps en polea",
            ]),
            ("Tiron A", 1, [
                "Dominadas", "Remo con barra", "Jalon al pecho",
                "Face pull", "Curl con barra",
            ]),
            ("Pierna A", 2, [
                "Sentadilla", "Peso muerto rumano", "Prensa de pierna",
                "Curl femoral", "Elevacion de gemelos",
            ]),
            ("Empuje B", 3, [
                "Press con mancuernas", "Press en maquina", "Elevaciones laterales",
                "Cruces en polea", "Press frances",
            ]),
            ("Tiron B", 4, [
                "Remo en polea baja", "Remo con mancuerna", "Jalon al pecho",
                "Pajaros (deltoide posterior)", "Curl martillo",
            ]),
            ("Pierna B", 5, [
                "Peso muerto", "Extension de cuadriceps", "Zancadas",
                "Curl femoral", "Elevacion de gemelos",
            ]),
        ],
    },
    "arnold_5": {
        "name": "Split de 5 días",
        "description": "Un grupo muscular por día. Mucho volumen por sesión.",
        "days_per_week": 5,
        "sets": 3,
        "routines": [
            ("Hombro y gemelo", 1, [
                "Press militar", "Press de hombro con mancuernas", "Elevaciones laterales",
                "Face pull", "Pajaros (deltoide posterior)", "Elevacion de gemelos",
            ]),
            ("Pecho", 2, [
                "Press banca", "Press inclinado con mancuernas", "Aperturas con mancuernas",
                "Cruces en polea", "Fondos en paralelas",
            ]),
            ("Hombro e isquios", 3, [
                "Press de hombro con mancuernas", "Elevaciones laterales", "Face pull",
                "Peso muerto rumano", "Curl femoral",
            ]),
            ("Espalda y cuadriceps", 4, [
                "Dominadas", "Jalon al pecho", "Remo con barra", "Sentadilla",
                "Prensa de pierna", "Extension de cuadriceps",
            ]),
            ("Brazo", 6, [
                "Curl con barra", "Curl martillo", "Curl predicador",
                "Press frances", "Extension de triceps en polea",
            ]),
        ],
    },
}


def weekday_map(template_id: str) -> dict[int, str]:
    """weekday -> nombre de rutina, para saber qué toca hoy."""
    template = TEMPLATES.get(template_id)
    if not template:
        return {}
    return {wd: name for name, wd, _ in template["routines"]}


@router.get("")
def list_templates() -> list[dict]:
    """Plantillas disponibles, sin la lista completa de ejercicios."""
    return [
        {
            "id": key,
            "name": tpl["name"],
            "description": tpl["description"],
            "days_per_week": tpl["days_per_week"],
            "routines": [name for name, _, _ in tpl["routines"]],
        }
        for key, tpl in TEMPLATES.items()
    ]


@router.get("/{template_id}")
def get_template(template_id: str) -> dict:
    tpl = TEMPLATES.get(template_id)
    if not tpl:
        raise HTTPException(404, "Plantilla desconocida")
    return {
        "id": template_id,
        "name": tpl["name"],
        "description": tpl["description"],
        "days_per_week": tpl["days_per_week"],
        "routines": [
            {"name": name, "weekday": wd, "exercises": exercises}
            for name, wd, exercises in tpl["routines"]
        ],
    }


@router.post("/{template_id}/apply")
def apply_template(template_id: str, sets: int | None = None) -> dict:
    """Crea las rutinas de la plantilla. Las que ya existan por nombre se
    respetan: aplicar dos veces no duplica ni pisa lo editado."""
    tpl = TEMPLATES.get(template_id)
    if not tpl:
        raise HTTPException(404, "Plantilla desconocida")

    n_sets = sets if sets and 1 <= sets <= 12 else tpl["sets"]
    created: list[str] = []

    with Session(engine) as session:
        existing = {r.name for r in session.exec(select(Routine)).all()}
        by_name = {e.name.strip().lower(): e for e in session.exec(select(Exercise)).all()}

        for name, _weekday, exercise_names in tpl["routines"]:
            if name in existing:
                continue
            routine = Routine(name=name)
            session.add(routine)
            session.commit()
            session.refresh(routine)

            position = 0
            for exercise_name in exercise_names:
                exercise = by_name.get(exercise_name.strip().lower())
                if exercise is None:
                    continue  # el catálogo no lo tiene: se salta
                session.add(RoutineExercise(
                    routine_id=routine.id,
                    exercise_id=exercise.id,
                    position=position,
                    sets=n_sets,
                    reps_min=6,
                    reps_max=8,
                ))
                position += 1
            session.commit()
            created.append(name)

    return {"status": "ok", "created": created, "skipped": len(tpl["routines"]) - len(created)}
