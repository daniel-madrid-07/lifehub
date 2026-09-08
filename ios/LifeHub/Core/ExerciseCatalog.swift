import Foundation

/// Catalogo base de ejercicios para el modo local.
///
/// Es el mismo que siembra el backend (backend/app/seed.py), para que la app
/// ofrezca lo mismo con servidor y sin el. El usuario puede anadir los suyos.
enum ExerciseCatalog {
    /// (nombre, musculo, material)
    static let all: [(String, String, String)] = [
        ("Press banca", "Pecho", "barra"),
        ("Press banca inclinado", "Pecho", "barra"),
        ("Press con mancuernas", "Pecho", "mancuernas"),
        ("Press inclinado con mancuernas", "Pecho", "mancuernas"),
        ("Aperturas con mancuernas", "Pecho", "mancuernas"),
        ("Cruces en polea", "Pecho", "polea"),
        ("Press en maquina", "Pecho", "maquina"),
        ("Fondos en paralelas", "Pecho", "peso corporal"),
        ("Flexiones", "Pecho", "peso corporal"),
        ("Dominadas", "Espalda", "peso corporal"),
        ("Jalon al pecho", "Espalda", "polea"),
        ("Remo con barra", "Espalda", "barra"),
        ("Remo con mancuerna", "Espalda", "mancuernas"),
        ("Remo en polea baja", "Espalda", "polea"),
        ("Remo en maquina", "Espalda", "maquina"),
        ("Peso muerto", "Espalda", "barra"),
        ("Pullover en polea", "Espalda", "polea"),
        ("Encogimientos (trapecio)", "Espalda", "mancuernas"),
        ("Press militar", "Hombros", "barra"),
        ("Press de hombro con mancuernas", "Hombros", "mancuernas"),
        ("Elevaciones laterales", "Hombros", "mancuernas"),
        ("Elevaciones frontales", "Hombros", "mancuernas"),
        ("Pajaros (deltoide posterior)", "Hombros", "mancuernas"),
        ("Face pull", "Hombros", "polea"),
        ("Curl con barra", "Biceps", "barra"),
        ("Curl con mancuernas", "Biceps", "mancuernas"),
        ("Curl martillo", "Biceps", "mancuernas"),
        ("Curl en polea", "Biceps", "polea"),
        ("Curl predicador", "Biceps", "maquina"),
        ("Press frances", "Triceps", "barra"),
        ("Extension de triceps en polea", "Triceps", "polea"),
        ("Extension sobre la cabeza", "Triceps", "mancuernas"),
        ("Fondos entre bancos", "Triceps", "peso corporal"),
        ("Sentadilla", "Pierna", "barra"),
        ("Prensa de pierna", "Pierna", "maquina"),
        ("Zancadas", "Pierna", "mancuernas"),
        ("Peso muerto rumano", "Pierna", "barra"),
        ("Extension de cuadriceps", "Pierna", "maquina"),
        ("Curl femoral", "Pierna", "maquina"),
        ("Hip thrust", "Pierna", "barra"),
        ("Elevacion de gemelos", "Pierna", "maquina"),
        ("Sentadilla bulgara", "Pierna", "mancuernas"),
        ("Plancha", "Core", "peso corporal"),
        ("Crunch abdominal", "Core", "peso corporal"),
        ("Elevaciones de piernas", "Core", "peso corporal"),
        ("Rueda abdominal", "Core", "peso corporal"),
        ("Russian twist", "Core", "peso corporal"),
        ("Cable Lateral Raise", "Hombros", "polea"),
        ("Smith Machine Shoulder Press", "Hombros", "maquina"),
        ("Smith Machine Incline Press", "Pecho", "maquina"),
        ("Machine Chest Press", "Pecho", "maquina"),
        ("Machine Pec Fly", "Pecho", "maquina"),
        ("Cable Hammer Curl", "Biceps", "polea"),
        ("Machine Biceps Curl", "Biceps", "maquina"),
        ("Leg Extension", "Pierna", "maquina"),
        ("Seated Cable Row", "Espalda", "polea"),
        ("Machine Lat Pulldown", "Espalda", "maquina"),
        ("Machine Front Delt Raise", "Hombros", "maquina"),
        ("Machine Leg Curl", "Pierna", "maquina"),
        ("Calf Raise on Leg Press", "Pierna", "maquina"),
    ]

    static let muscles = ["Pecho", "Espalda", "Hombros", "Biceps", "Triceps", "Pierna", "Core"]
    static let equipment = ["barra", "mancuernas", "maquina", "polea", "peso corporal"]
}
