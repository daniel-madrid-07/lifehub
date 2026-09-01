/**
 * Datos personales de Daniel — esta app es SOLO suya, nada configurable.
 * Si algo cambia (objetivo, % graso, etc.), se cambia aquí y listo.
 */
export const ME = {
  heightCm: 180,
  birthDate: new Date(2007, 2, 6), // 6 de marzo de 2007
  sex: "m" as const,
  /** Sedentario fuera del gym (estudio/PC) + 5 días de pesas M·X·J·V·D */
  activityFactor: 1.5,
  /** Objetivo actual: volumen (TDEE +300). Definición sería −400. */
  goal: "Volumen" as const,
  goalKcalDelta: +300,
  /** % graso (13-16% declarado -> punto medio) */
  bodyFatPct: 15 as number | null,
  /** Peso de respaldo hasta que haya registros en la báscula */
  fallbackWeight: 70,
  /** Su gym: barra olímpica de 20 kg y discos por lado (kg) */
  barWeight: 20,
  plates: [20, 10, 5, 2.5, 1.25],
}

/**
 * Calculadora de discos: qué poner por lado para un peso total con barra.
 * Devuelve la lista de discos por lado (mayor a menor) y lo que sobra si no
 * se llega exacto.
 */
export function platesPerSide(total: number): { plates: number[]; leftover: number } {
  let perSide = (total - ME.barWeight) / 2
  if (perSide <= 0) return { plates: [], leftover: 0 }
  const out: number[] = []
  for (const plate of ME.plates) {
    while (perSide >= plate - 1e-9) {
      out.push(plate)
      perSide -= plate
    }
  }
  return { plates: out, leftover: Math.round(perSide * 100) / 100 }
}

export function myAge(): number {
  const now = new Date()
  let age = now.getFullYear() - ME.birthDate.getFullYear()
  const beforeBirthday =
    now.getMonth() < ME.birthDate.getMonth() ||
    (now.getMonth() === ME.birthDate.getMonth() && now.getDate() < ME.birthDate.getDate())
  return beforeBirthday ? age - 1 : age
}

/** Mifflin-St Jeor (hombre) */
export function myBmr(weight: number): number {
  return 10 * weight + 6.25 * ME.heightCm - 5 * myAge() + 5
}

export function myTdee(weight: number): number {
  return myBmr(weight) * ME.activityFactor
}

/** Kcal diarias según su objetivo actual */
export function myKcalTarget(weight: number): number {
  return Math.round(myTdee(weight) + ME.goalKcalDelta)
}

/** Proteína diaria: 2 g/kg (entrena al fallo, construyendo músculo) */
export function myProteinTarget(weight: number): number {
  return Math.round(weight * 2)
}
