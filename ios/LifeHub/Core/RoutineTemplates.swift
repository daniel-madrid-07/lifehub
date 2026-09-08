import Foundation

/// Plantillas de rutina para el modo local.
///
/// Mismas que sirve el backend (backend/app/routine_templates.py), para que
/// la experiencia sea identica con servidor y sin el.
enum RoutineTemplates {
    struct Entry {
        let name: String
        let weekday: Int
        let exercises: [String]
    }

    struct Template {
        let id: String
        let name: String
        let description: String
        let daysPerWeek: Int
        let sets: Int
        let routines: [Entry]
    }

    static let all: [Template] = [
        Template(
            id: "full_body_3",
            name: "Cuerpo completo (3 días)",
            description: "Lunes, miércoles y viernes. Lo más eficiente si empiezas.",
            daysPerWeek: 3,
            sets: 3,
            routines: [
                Entry(name: "Cuerpo completo A", weekday: 0, exercises: ["Sentadilla", "Press banca", "Remo con barra", "Press militar", "Curl con barra"]),
                Entry(name: "Cuerpo completo B", weekday: 2, exercises: ["Peso muerto", "Press inclinado con mancuernas", "Jalon al pecho", "Elevaciones laterales", "Press frances"]),
                Entry(name: "Cuerpo completo C", weekday: 4, exercises: ["Prensa de pierna", "Press con mancuernas", "Remo en polea baja", "Face pull", "Curl martillo"]),
            ]),
        Template(
            id: "upper_lower_4",
            name: "Torso / Pierna (4 días)",
            description: "Lunes, martes, jueves y viernes. Buen equilibrio entre volumen y descanso.",
            daysPerWeek: 4,
            sets: 3,
            routines: [
                Entry(name: "Torso A", weekday: 0, exercises: ["Press banca", "Remo con barra", "Press militar", "Jalon al pecho", "Curl con barra", "Press frances"]),
                Entry(name: "Pierna A", weekday: 1, exercises: ["Sentadilla", "Peso muerto rumano", "Prensa de pierna", "Curl femoral", "Elevacion de gemelos"]),
                Entry(name: "Torso B", weekday: 3, exercises: ["Press inclinado con mancuernas", "Dominadas", "Elevaciones laterales", "Remo en polea baja", "Curl martillo", "Extension de triceps en polea"]),
                Entry(name: "Pierna B", weekday: 4, exercises: ["Peso muerto", "Extension de cuadriceps", "Zancadas", "Curl femoral", "Elevacion de gemelos"]),
            ]),
        Template(
            id: "ppl_6",
            name: "Push / Pull / Pierna (6 días)",
            description: "Dos vueltas por semana. Para quien ya lleva tiempo entrenando.",
            daysPerWeek: 6,
            sets: 3,
            routines: [
                Entry(name: "Empuje A", weekday: 0, exercises: ["Press banca", "Press militar", "Press inclinado con mancuernas", "Elevaciones laterales", "Extension de triceps en polea"]),
                Entry(name: "Tiron A", weekday: 1, exercises: ["Dominadas", "Remo con barra", "Jalon al pecho", "Face pull", "Curl con barra"]),
                Entry(name: "Pierna A", weekday: 2, exercises: ["Sentadilla", "Peso muerto rumano", "Prensa de pierna", "Curl femoral", "Elevacion de gemelos"]),
                Entry(name: "Empuje B", weekday: 3, exercises: ["Press con mancuernas", "Press en maquina", "Elevaciones laterales", "Cruces en polea", "Press frances"]),
                Entry(name: "Tiron B", weekday: 4, exercises: ["Remo en polea baja", "Remo con mancuerna", "Jalon al pecho", "Pajaros (deltoide posterior)", "Curl martillo"]),
                Entry(name: "Pierna B", weekday: 5, exercises: ["Peso muerto", "Extension de cuadriceps", "Zancadas", "Curl femoral", "Elevacion de gemelos"]),
            ]),
        Template(
            id: "arnold_5",
            name: "Split de 5 días",
            description: "Un grupo muscular por día. Mucho volumen por sesión.",
            daysPerWeek: 5,
            sets: 3,
            routines: [
                Entry(name: "Hombro y gemelo", weekday: 1, exercises: ["Press militar", "Press de hombro con mancuernas", "Elevaciones laterales", "Face pull", "Pajaros (deltoide posterior)", "Elevacion de gemelos"]),
                Entry(name: "Pecho", weekday: 2, exercises: ["Press banca", "Press inclinado con mancuernas", "Aperturas con mancuernas", "Cruces en polea", "Fondos en paralelas"]),
                Entry(name: "Hombro e isquios", weekday: 3, exercises: ["Press de hombro con mancuernas", "Elevaciones laterales", "Face pull", "Peso muerto rumano", "Curl femoral"]),
                Entry(name: "Espalda y cuadriceps", weekday: 4, exercises: ["Dominadas", "Jalon al pecho", "Remo con barra", "Sentadilla", "Prensa de pierna", "Extension de cuadriceps"]),
                Entry(name: "Brazo", weekday: 6, exercises: ["Curl con barra", "Curl martillo", "Curl predicador", "Press frances", "Extension de triceps en polea"]),
            ]),
    ]

    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Igual que responde GET /api/routine-templates.
    static var list: [[String: Any]] {
        all.map { tpl in
            [
                "id": tpl.id,
                "name": tpl.name,
                "description": tpl.description,
                "days_per_week": tpl.daysPerWeek,
                "routines": tpl.routines.map(\.name),
            ]
        }
    }
}
