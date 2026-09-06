# Rediseño del motor de recomendación de sueño — Apple Watch SE 2

> **Premisa honesta:** todo lo que sigue son *estimaciones construidas sobre estimaciones*. Apple estima las fases con actigrafía + PPG; tú vas a estimar presión de sueño y fase circadiana a partir de esas estimaciones. El error se compone. La ventaja competitiva real no está en fingir precisión clínica, sino en **modelar bien lo que sí es medible** (historial sueño/vigilia, HR nocturna, luz) y en **ser explícito con la incertidumbre**.

---

## 0. Veredictos previos

### 0.1 El panorama competitivo cambió

Desde **watchOS 26**, Apple tiene *Sleep Score* y llega al SE 2 (Series 6+ / SE 2+). Composición: duración (50 pts) + consistencia de hora de acostarse (30 pts) + interrupciones (20 pts).

Lo que Apple **sigue sin hacer** (tu hueco real):

| Apple | Tú puedes |
|---|---|
| No usa HRV ni FC en reposo | Readiness con HRV + HR mínima + respiración |
| No modela deuda de sueño | Modelo homeostático + alostático |
| No estima cronotipo | MSFsc + jet lag social |
| No estima fase circadiana | Estimador HR-nadir + MSFsc + luz |
| Horario fijo que tú fijas | Hora óptima derivada del modelo |
| Alarma a hora fija | Alarma en ventana con detección de arousal |
| No recomienda exposición a luz | PRC → la única palanca *causal* fuerte |
| Score opaco | Explicabilidad ("+25 min hoy porque…") |

### 0.2 Los tres cambios de mayor impacto/esfuerzo

1. **Sustituir tu cadena heurística por un modelo de dos procesos** que simula S sobre el historial completo (incluyendo siestas) y optimiza (B, W) con una función de coste. Coste: ~4 días. Impacto: transforma la app.
2. **Tirar el estimador de ciclo actual.** Depende de contar REMs, que es la señal menos fiable del SE 2.
3. **Explotar `timeInDaylight`** (iOS 17+). La luz matinal es la única intervención con un efecto causal grande y documentado sobre la fase circadiana. Nadie la usa.

### 0.3 Realidad del hardware

| Señal | SE 2 | Notas |
|---|---|---|
| Fases (Core/Deep/REM/Awake) | ✅ | Series 4+ y SE. Fiabilidad limitada (ver §6) |
| HR nocturna | ✅ | ~cada 5–10 min en background |
| HRV (SDNN) | ✅ | Muestreo oportunista, pocas lecturas/noche |
| Serie de latidos (intervalos RR) | ✅ | `HKHeartbeatSeriesSample` — **infrautilizado** |
| Frecuencia respiratoria | ✅ | Muy estable → excelente detector de desviación |
| Tiempo en luz diurna | ✅ | `timeInDaylight`, iOS 17 / watchOS 10 — **infrautilizado** |
| Acelerómetro crudo 50 Hz | ✅ | `CMSensorRecorder` (buffer ~12 h, bajo consumo) |
| Temperatura de muñeca | ❌ | SE 3 sí, SE 2 no |
| SpO₂ | ❌ | Ningún SE lo ha tenido |
| ECG | ❌ | — |
| Breathing Disturbances / apnea | ❌ | Requiere Series 9+, Ultra 2, o SE 3 |

---

## 1. Modelo formal: dos procesos (Borbély)

### 1.1 La ciencia

**Borbély (1982)** propone que la regulación del sueño surge de dos procesos independientes:

- **Proceso S** (homeostático): la presión de sueño sube durante la vigilia y se disipa durante el sueño. Su correlato electrofisiológico es la potencia delta (SWA) en NREM.
- **Proceso C** (circadiano): una oscilación de ~24 h, independiente del sueño previo, que modula los umbrales de inicio y fin.

**Daan, Beersma & Borbély (1984)** lo formalizan: el sueño se inicia cuando S alcanza un umbral superior H⁺(t) y termina cuando cae al umbral inferior H⁻(t); ambos umbrales oscilan con C.

**Dijk & Czeisler (1995)** demuestran experimentalmente (desincronización forzada) la interacción: la propensión al sueño es máxima cuando S es alta *y* C está en su fase permisiva. Esto explica por qué "acostarse antes" no funciona: existe una **zona de mantenimiento de la vigilia** (la "zona prohibida" de **Lavie, 1986**) ~2–4 h antes de la hora habitual de acostarse, en la que dormirse es fisiológicamente muy difícil por mucha deuda que arrastres.

> **Consecuencia de diseño, importante:** tu app **nunca** debe recomendar una hora de acostarse más de ~30–60 min antes de la habitual sin ejecutar antes un protocolo de adelanto de fase con luz. Es el error número uno de las apps de sueño.

### 1.2 El algoritmo

#### Proceso S — es la parte fácil, y es *totalmente* computable con tus datos

S está completamente determinado por el historial sueño/vigilia. Tú tienes ese historial en HealthKit. No necesitas medir nada más.

```
Vigilia:  S(t+Δ) = μ − (μ − S(t))·exp(−Δ/τ_r)     μ = 1, τ_r ≈ 18.2 h
Sueño:    S(t+Δ) = S(t)·exp(−Δ/τ_d)               τ_d ≈ 4.2 h
```

Δ = 5 min. Los τ son los valores clásicos de la literatura; trátalos como **priors** y ajústalos (§1.4).

**Ventaja enorme sobre tu lógica actual:** las siestas entran de forma nativa. Tu resta simple de "deuda" no puede modelar que una siesta de 25 min a las 15:00 reduce la presión de sueño y retrasa el momento en que te dormirás. El simulador de S sí.

#### Proceso C

```
C(t) = 0.97·sin(ωt') + 0.22·sin(2ωt') + 0.07·sin(3ωt') + 0.03·sin(4ωt')
       con ω = 2π/24,  t' = t − φ
```

(Expansión armónica de Daan et al.; la asimetría importa — la subida es más rápida que la bajada.)

```
H⁺(t) = H₀⁺ + a·C(t)      H₀⁺ ≈ 0.60
H⁻(t) = H₀⁻ + a·C(t)      H₀⁻ ≈ 0.17,   a ≈ 0.10
```

**φ (la fase) es la única incógnita difícil.** Ver §1.3.

#### De ahí a la recomendación: **no simules, optimiza**

En vez de simular hacia delante y esperar a que S cruce H⁺ (lo que asume que el usuario obedece a su biología, cosa que no hace: tiene examen a las 8), plantéalo como un **problema de optimización con restricciones**:

```
Dado:  S_now      (estado actual del simulador)
       φ̂          (fase circadiana estimada, §1.3)
       deadline   (primer evento de agenda − 45 min)
       B̄, W̄       (hora habitual de acostarse/levantarse, medianas circulares 14d)
       D          (deuda total, §2)
       Need       (necesidad personal de sueño, §6.4)

Busca (B, W) que minimicen:

J(B,W) = w_S    · (S(W) − S*)²                      // disipación homeostática objetivo
       + w_gate · softplus(B_gate − B)              // no antes de la puerta del sueño
       + w_cbt  · softplus((CBTmin + 1.5h) − W)     // no despertar antes de CBTmin+1.5h
       + w_reg  · [(B − B̄)² + (W − W̄)²]             // regularidad (§7.6)
       + w_sjl  · (midpoint(B,W) − MSFsc)²          // alineación con el cronotipo
       + w_debt · max(0, D − pagado(B,W))²          // repago de deuda

sujeto a:
       W ≤ deadline
       TIB ∈ [Need − 1h, Need + 1.5h]
       |B − B_ayer| ≤ 45 min,  |W − W_ayer| ≤ 45 min      // desplazamiento gradual
       B ≥ B_gate                                          // restricción DURA
```

donde:
- `B_gate` = fin de la zona de mantenimiento de vigilia ≈ `B̄ − 1h` (aproximación conservadora; en términos circadianos, ≈ DLMO + 1 h).
- `CBTmin` ≈ `MSFsc + 1.5h` como prior, refinado con el nadir de HR (§1.3).
- `S*` = tu nivel personal de S al despertar en tus **mejores** noches (mediana del S simulado al despertar en las 10 noches con mayor readiness). Es tu "punto de reset".

**Búsqueda:** grid de 5 min sobre B ∈ [B̄−90 min, B̄+90 min] y W ∈ [W̄−90 min, deadline]. Son ~40×40 = 1600 evaluaciones. En Swift, microsegundos. No hace falta nada más sofisticado.

**Por qué esto es mejor que tu lógica secuencial:** tu cadena actual (ciclo → N → recuperación → cronotipo → resta) es una secuencia de heurísticas donde cada error se propaga sin posibilidad de compensación. Una función de coste deja que las restricciones negocien entre sí, y te permite **explicar** la recomendación ("hoy te acuestas 20 min antes porque la deuda pesa más que la regularidad").

### 1.3 Estimar φ (fase circadiana) sin temperatura ni luz de calidad

Aquí hay que ser honesto: **no puedes medir DLMO ni CBTmin.** Solo estimarlos, con error de **±1–1.5 h en el mejor caso** (comparativas de modelos frente a DLMO real: Huang et al. 2021).

Tres estimadores, con sus sesgos:

**(a) MSFsc (conductual)** — §3. Correlación con DLMO r ≈ 0.6–0.7 (Kantermann et al. 2015). Sesgo: refleja tu *conducta*, no tu reloj. Si tienes jet lag social, MSFsc está contaminado.

**(b) Nadir de HR nocturna** — el mínimo de FC durante el sueño se aproxima al nadir de temperatura corporal central. Bowman et al. (2021, *Cell Rep Med*) demostraron que se puede caracterizar la fisiología diaria (incluida la fase) desde wearables comunes usando HR + actividad.

```swift
/// Nadir de HR: mediana móvil de 60 min sobre las muestras nocturnas, argmin.
func hrNadir(samples: [(Date, Double)]) -> Date? {
    guard samples.count >= 20 else { return nil }
    let smoothed = samples.map { s -> (Date, Double) in
        let window = samples.filter { abs($0.0.timeIntervalSince(s.0)) <= 1800 }
        return (s.0, median(window.map(\.1)))
    }
    return smoothed.min(by: { $0.1 < $1.1 })?.0
}
```

> ⚠️ **Sesgo grande y conocido:** el nadir de HR está *enmascarado* por el propio sueño. Dormirse baja la FC; despertarse la sube. Eso empuja el argmin hacia el centro del episodio de sueño, independientemente del reloj biológico. **Por eso no lo uses como estimador absoluto.** Úsalo como **detector de deriva**: si el nadir se ha movido +40 min en 3 semanas *manteniendo el mismo horario*, tu reloj está retrasando. Eso sí es información nueva y accionable.

**(c) Modelo de luz** — con `timeInDaylight` podrías alimentar un modelo tipo Kronauer (Jewett, Forger & Kronauer 1999). Pero la señal es umbralizada, se confunde con mangas y con interiores luminosos, y no da lux. Es barata si solo la usas para **recomendar** (§7.1) y cara si intentas inferir fase con ella. **Recomendación: úsala para recomendar, no para inferir.**

**Ensamblado pragmático:**

```
φ̂_CBTmin = MSFsc + 1.5 h                    // estimador base
deriva    = mediana(nadir_HR, últimos 7 d) − mediana(nadir_HR, días [−28,−21])

si |deriva| > 30 min y el horario ha sido estable:
    → señalar deriva de fase y activar protocolo de luz

Intervalo de confianza mostrado: ±60 min. No lo escondas.
```

### 1.4 Calibración de los parámetros libres

No uses los τ y umbrales de la literatura a ciegas. **Ajústalos a él:**

1. Simula S sobre las últimas 60 noches con τ_r, τ_d, H₀ iniciales.
2. Calcula el TIB que el modelo *predice* (cruces de umbral) en noches libres sin alarma.
3. Minimiza el error frente al TST observado real ajustando `a` y `H₀⁺` (son 2–4 parámetros: un grid basta).
4. Si no converge con ≥20 noches libres: quédate con los valores de literatura y **díselo al usuario**.

### 1.5 Implementación Swift

```swift
struct TwoProcess {
    var tauRise: Double = 18.2 * 3600
    var tauFall: Double =  4.2 * 3600
    var mu:      Double = 1.00
    var h0Upper: Double = 0.60
    var h0Lower: Double = 0.17
    var amp:     Double = 0.10
    var phiHours: Double = 4.5          // fase estimada (h)

    func step(_ S: Double, dt: TimeInterval, asleep: Bool) -> Double {
        asleep ? S * exp(-dt / tauFall)
               : mu - (mu - S) * exp(-dt / tauRise)
    }

    func C(_ hours: Double) -> Double {
        let w = 2 * Double.pi / 24
        let t = hours - phiHours
        return 0.97*sin(w*t) + 0.22*sin(2*w*t) + 0.07*sin(3*w*t) + 0.03*sin(4*w*t)
    }

    func upper(_ h: Double) -> Double { h0Upper + amp * C(h) }
    func lower(_ h: Double) -> Double { h0Lower + amp * C(h) }

    /// Simula S sobre una serie de intervalos de sueño. Devuelve la traza completa.
    func simulate(intervals: [DateInterval], from: Date, to: Date,
                  S0: Double = 0.35, dt: TimeInterval = 300) -> [(Date, Double)] {
        var S = S0, t = from
        var trace: [(Date, Double)] = []
        while t < to {
            let asleep = intervals.contains { $0.contains(t) }
            S = step(S, dt: dt, asleep: asleep)
            trace.append((t, S))
            t = t.addingTimeInterval(dt)
        }
        return trace
    }
}
```

**Persistencia:** UserDefaults se te queda corto. 90 días de traza a 5 min ≈ 26.000 puntos. Usa un `Codable` en `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`.

---

## 2. Deuda de sueño rigurosa

### 2.1 La ciencia

**Van Dongen et al. (2003, *Sleep*)** — el experimento de referencia: 14 días de restricción crónica (4 h / 6 h / 8 h en cama) frente a privación total. Dos hallazgos que cambian tu diseño:

1. El déficit neuroconductual **se acumula de forma casi lineal** con la vigilia excesiva acumulada, sin saturarse.
2. **La somnolencia subjetiva se disocia del deterioro objetivo.** Los sujetos con 6 h/noche durante dos semanas rendían como si llevaran dos noches sin dormir, pero *se sentían solo levemente somnolientos*. → **Nunca preguntes al usuario cómo se siente y lo uses como verdad de referencia.**

**Belenky et al. (2003, *J Sleep Res*)** — la recuperación tras restricción crónica es **lenta e incompleta**: tres noches de 8 h no devuelven el rendimiento al basal. Esto rompe la idea de "pagar la deuda el fin de semana".

**McCauley et al. (2009, *J Theor Biol*)** — extienden el modelo de dos procesos con un **proceso alostático lento** (escala de semanas) que explica la asimetría entre privación aguda (recuperable) y restricción crónica (no).

### 2.2 El algoritmo: deuda de dos escalas

```
Need       = necesidad personal (§6.4). Default 8.0 h.
Deficit_n  = Need − TST_n                     (puede ser negativo)

D_fast(n) = clip( D_fast(n−1)·e^(−1/τ_f) + Deficit_n , 0, ∞ )        τ_f = 2 días

D_slow(n) = clip( D_slow(n−1)·e^(−1/τ_s)
                  + κ⁺·max(0, Deficit_n)
                  + κ⁻·min(0, Deficit_n) , 0, ∞ )                    τ_s = 21 días

    κ⁺ = 0.35   (acumula rápido)
    κ⁻ = 0.15   (paga MUCHO más lento)   ← asimetría de Belenky

D_total = D_fast + D_slow
```

La asimetría `κ⁻ < κ⁺` es el núcleo del modelo: **es fácil endeudarse y lento pagar.** Esto es lo que hace que tu app diga cosas verdaderas en lugar de "duerme una hora extra el sábado y estás al día".

### 2.3 Política de repago (evitar la "borrachera de sueño")

La inercia del sueño empeora al despertar de sueño de ondas lentas, tras privación, y al despertar cerca del nadir circadiano (Tassi & Muzet 2000; Hilditch & McHill 2019). Dormir *de más* no causa inercia por sí mismo, pero **retrasa la fase** (menos luz matinal → reloj más tardío → lunes peor). Ese es el mecanismo del jet lag social.

```
extra_n = clip( 0.35 · D_total , 0 , 60 min )        // NUNCA más de +60 min/noche

Distribución:  2/3 adelantando la hora de acostarse
               1/3 retrasando el despertar
    → protege la fase y la exposición a luz matinal

Topes duros:
    TIB ≤ Need + 90 min
    W  ≤ W̄ + 60 min       (fin de semana incluido; esta regla sola mata el jet lag social)

Guarda de Spielman (restricción de tiempo en cama, 1987):
    si eficiencia_media(últimas 5 noches) < 85%  →  extra_n = 0
    → extender el TIB con eficiencia baja empeora el insomnio.
      Recomienda consolidación (misma hora, menos cama), no más cama.

Siesta estratégica (si D_total > 5 h y hay hueco):
    10–20 min entre 13:00 y 15:00   ← recuperativa, sin inercia (Brooks & Lack 2006)
    o 90 min (ciclo completo)
    NUNCA 30–60 min  →  despiertas de SWS  →  inercia máxima
    Y: descuenta el S disipado por la siesta antes de recalcular B.
```

---

## 3. Cronotipo robusto (MSFsc) y jet lag social

### 3.1 La ciencia

**Roenneberg, Wirz-Justice & Merrow (2003)** — el MCTQ. El marcador de cronotipo es el **punto medio de sueño en días libres (MSF)**, corregido por la recuperación de deuda que ocurre esos días:

```
MSF     = punto medio de sueño en días libres
SD_f    = duración de sueño en días libres
SD_w    = duración de sueño en días laborables
SD_week = (n_w·SD_w + n_f·SD_f) / (n_w + n_f)

MSFsc = MSF − (SD_f − SD_week)/2      si SD_f > SD_w
MSFsc = MSF                           en caso contrario
```

**Jet lag social** (Wittmann et al. 2006): `SJL = |MSF − MSW|`. La discrepancia entre tu reloj biológico y tu reloj social.

**Dato relevante:** Roenneberg et al. (2004, *Curr Biol*, "A marker for the end of adolescence") muestran que la lateralidad del cronotipo **alcanza su máximo poblacional alrededor de los 20 años** y luego se adelanta progresivamente. En un usuario joven con horario académico, el MSFsc suele ser tardío y el SJL alto. **El modelo no debe pelearse con eso — debe gestionarlo con luz** (§7.1).

### 3.2 Tu ventaja: detección de días libres desde la agenda

Casi todas las apps asumen "fin de semana = día libre". Es falso y ruidoso. Tú tienes la agenda en tu backend FastAPI. Úsala:

```
día_libre(n) := la mañana siguiente NO tiene evento antes de las 09:00
                Y no había alarma programada
```

Refuerzo por señal: un despertar **forzado por alarma** es distinguible — despertar abrupto seguido de un pico de pasos en menos de 5 min. Un despertar espontáneo tiene una salida más gradual. Úsalo como validación cruzada de la clasificación de la agenda.

### 3.3 Estadística circular — no lo hagas mal

Las horas de reloj son **variables circulares**. La media aritmética de [23:50, 00:10] da 12:00, no 00:00.

```swift
/// Media circular de horas de reloj (0–24)
func circularMean(_ hours: [Double]) -> Double {
    let w = 2 * Double.pi / 24
    let s = hours.reduce(0) { $0 + sin($1 * w) }
    let c = hours.reduce(0) { $0 + cos($1 * w) }
    var m = atan2(s, c) / w
    if m < 0 { m += 24 }
    return m
}

/// Longitud del vector resultante R ∈ [0,1]: 1 = perfectamente regular.
/// Úsalo como medida de dispersión / confianza.
func circularConcentration(_ hours: [Double]) -> Double {
    let w = 2 * Double.pi / 24
    let n = Double(hours.count)
    let s = hours.reduce(0) { $0 + sin($1 * w) } / n
    let c = hours.reduce(0) { $0 + cos($1 * w) } / n
    return sqrt(s*s + c*c)
}
```

Tu truco actual de "horas tras mediodía" funciona para la mayoría de la gente pero se rompe con cronotipos extremos. Usa la versión circular.

### 3.4 Uso: no fuerces la biología

```
si SJL > 1 h y quiere adelantar:
    objetivo   = adelantar MSFsc hacia el horario social
    protocolo  = −15 min/día en B y W  (máx. −30 min/día CON luz matinal)
               + luz exterior ≥20 min en los 60 min tras despertar
               + reducir luz en las 2 h previas a B
    restricción: NUNCA recomendar B más de 60 min antes de B̄. Zona prohibida (Lavie).

si SJL < 30 min:
    estás alineado. La recomendación es simplemente mantener regularidad.
```

---

## 4. Ciclos de sueño y alarma inteligente

### 4.1 Por qué tu estimador de ciclo está roto

`ciclo = TST / nº_episodios_REM` falla porque el conteo de episodios REM es la señal *menos fiable* del dispositivo:

| Estudio | Métrica | Apple Watch |
|---|---|---|
| Miller, Sargent & Roach 2022 (*Sensors*) | Acuerdo multiclase (4 estados) | 53%, κ = 0.20 |
| *SLEEP Advances* 2025 (6 wearables) | κ multiclase (Series 8) | 0.53 |
| Estudio Brigham / Oura 2024 | κ 4 estados | 0.60 |
| Varios | Sensibilidad sueño profundo | ~50–62% |
| Varios | **Especificidad de vigilia** | **29–52%** |

**Impacto directo:** si el reloj se pierde 1 de 5 episodios REM, tu ciclo estimado salta de 90 a 112 min (+24%). Con 5 ciclos, eso mueve tu hora de dormir **1 h 50 min**. Es el error dominante de tu sistema actual.

### 4.2 Estimador correcto

**Regresión sobre los inicios de REM, no división.** Si el i-ésimo episodio REM empieza en `t_i`:

```
t_i ≈ a + c·i        →  pendiente c = duración del ciclo
```

Usa **Theil–Sen** (mediana de las pendientes entre todos los pares) en lugar de OLS: es robusto a episodios perdidos y espurios.

**Y luego encógelo hacia el prior poblacional.** La duración del ciclo NREM–REM en adultos es notablemente estable (~90 min; Feinberg & Floyd 1979), y la varianza *entre* individuos es modesta comparada con el ruido de tu medición.

```
ĉ = (n / (n + k)) · c̄_personal  +  (k / (n + k)) · 90 min       con k ≈ 12

Descarta noches con <3 episodios REM detectados.
Acota ĉ ∈ [80, 110] min (mantén tu cota, es razonable).
```

Con n = 5 noches: ĉ = 0.29·c̄ + 0.71·90. Con n = 40: ĉ = 0.77·c̄ + 0.23·90. Es decir: **al principio confías en la población, no en el ruido.**

### 4.3 La verdad incómoda sobre anclar la alarma al final de un ciclo

Aunque estimes ĉ perfectamente, **predecir en qué fase estará el usuario dentro de 8 horas no es defendible.** El error se acumula: ±8 min por ciclo × 5 ciclos ≈ ±40 min. Eso es media fase de ciclo. La predicción no contiene información.

**Separa limpiamente los dos problemas:**

| Problema | Herramienta | Horizonte |
|---|---|---|
| **Cuánto** dormir | N × ĉ + modelo de S / deuda | 8 h vista — válido |
| **En qué momento exacto** despertar | Detección en tiempo real en la ventana | 30 min vista — válido |

Esto es honesto *y* técnicamente superior. Deja de fingir que puedes hacer lo segundo con lo primero.

### 4.4 Alarma inteligente: **sí es viable**

watchOS soporta un tipo de sesión de runtime extendido específicamente para esto desde watchOS 6. Apple lo diseñó exactamente para el caso "despertar al usuario, monitorizando FC o movimiento para elegir el mejor momento".

**Info.plist de la app watchOS:**

```xml
<key>WKBackgroundModes</key>
<array>
    <string>alarm</string>
</array>
```

El sistema deduce el **tipo** de sesión desde el background mode declarado; no lo eliges en código.

```swift
import WatchKit
import HealthKit
import CoreMotion

final class SmartAlarm: NSObject, WKExtendedRuntimeSessionDelegate {
    private var session: WKExtendedRuntimeSession?
    private let motion = CMMotionManager()

    private var deadline: Date!                  // hora dura de la alarma
    private var epochs: [(Date, Double)] = []    // activity counts, épocas de 30 s
    private var fired = false

    /// Programa la sesión para que arranque en (alarma − 30 min).
    /// ⚠️ Debe llamarse con la app en PRIMER PLANO. Solo una sesión activa a la vez.
    func schedule(alarmAt date: Date) {
        deadline = date
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start(at: date.addingTimeInterval(-30 * 60))
        session = s
    }

    func extendedRuntimeSessionDidStart(_ s: WKExtendedRuntimeSession) {
        startActigraphy()
        startHeartRateStream()
        // Reprogramar la de mañana AQUÍ: la app está viva.
        // (Verifícalo en dispositivo; es el workaround al límite de "solo en foreground".)
    }

    // MARK: - Actigrafía

    private func startActigraphy() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 1.0 / 25.0   // 25 Hz basta y ahorra batería
        var buffer: [Double] = []
        var epochStart = Date()

        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            // Magnitud sin gravedad: | ‖a‖ − 1g |
            let mag = abs(sqrt(a.x*a.x + a.y*a.y + a.z*a.z) - 1.0)
            buffer.append(mag)

            if Date().timeIntervalSince(epochStart) >= 30 {
                // "Activity count" ≈ suma rectificada tras filtrar 0.25–3 Hz.
                // Aproximación barata: high-pass restando la media de la época.
                let mean  = buffer.reduce(0, +) / Double(buffer.count)
                let count = buffer.reduce(0) { $0 + abs($1 - mean) }
                self.epochs.append((epochStart, count))
                self.evaluate()
                buffer.removeAll(keepingCapacity: true)
                epochStart = Date()
            }
        }
    }

    // MARK: - Regla de disparo (umbral decreciente)

    private func evaluate() {
        guard !fired, let last = epochs.last else { return }
        let now = last.0
        let remaining = deadline.timeIntervalSince(now)

        if remaining <= 30 { return fire(reason: .deadline) }   // deadline duro

        // Baselines de la noche precomputados en iOS y enviados por WatchConnectivity.
        let zAct = robustZ(last.1,    median: nightMedianAct,   mad: nightMADAct)
        let zHR  = robustZ(currentHR, median: hrMedianLast20min, mad: hrMADLast20min)
        let score = 0.7 * zAct + 0.3 * zHR

        // Umbral que decae linealmente: exigente al principio, permisivo al final.
        let theta = 2.0 * (remaining / (30 * 60))
        if score > theta { fire(reason: .arousal) }
    }

    private func fire(reason: FireReason) {
        fired = true
        motion.stopAccelerometerUpdates()
        session?.notifyUser(hapticType: .notification) { type in
            type.pointee = .notification
            return 2.0                       // repetir cada 2 s
        }
    }
}
```

**Detalles críticos que te van a morder:**

1. **Solo una sesión, y hay que programarla con la app en primer plano.** No puedes programarla desde el iPhone en background. UX: la notificación de *wind-down* abre la app del reloj y el usuario toca "programar". O reprogramas desde `extendedRuntimeSessionDidStart` (el proceso está vivo) — **verifícalo en dispositivo real, no en simulador.**
2. **Si no llamas a `notifyUser` durante una sesión de alarma, el sistema avisa al usuario y le ofrece revocarte el permiso** de programar sesiones. Dispara siempre, aunque sea en el deadline.
3. **Red de seguridad obligatoria:** mantén tu alarma nativa vía Atajos en la hora dura. Si la sesión no arranca (reloj fuera de la muñeca, batería baja, sesión invalidada), el háptico no llega y el usuario pierde el examen. Cinturón y tirantes.

### 4.5 Coste de batería — números

| Enfoque | Consumo estimado | Veredicto |
|---|---|---|
| `HKWorkoutSession` toda la noche (8 h) | **40–70%** | ❌ Inaceptable. Además ensucia los anillos y Salud. |
| Sesión de alarma (30 min, CoreMotion 25 Hz + HR) | **~2–5%** | ✅ Viable |
| Tracking nativo de sueño de Apple (referencia) | 5–10% | — |

**Protocolo de medición (hazlo, no me creas):**

```swift
WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
let level = WKInterfaceDevice.current().batteryLevel   // 0.0–1.0
```

Loguea el nivel en `extendedRuntimeSessionDidStart` y justo antes de invalidar. Siete noches con sesión frente a siete sin. Reporta la diferencia real en la app.

### 4.6 Beneficio real esperado: sé honesto

La inercia del sueño es peor al despertar de SWS y **se resuelve en 15–30 min** si despiertas de N1/N2, pero puede persistir 1–2 h desde SWS. El detector de arousal por movimiento sesga *hacia afuera* tanto de SWS (movimiento mínimo) como de REM medio (atonía muscular). Bien.

**Pero:** el SWS se concentra en la **primera mitad** de la noche. En los últimos 30 min de una noche de 7–8 h, el SWS es raro (<10 % de las épocas). **La alarma inteligente te ayuda quizá 1 de cada 10 mañanas.**

Es *más* útil cuando duermes corto (<6 h, el SWS se comprime y llega más tarde), cuando vienes de deuda (rebote de SWS) o cuando tu ciclo está desfasado.

Comunícalo así: *"En las últimas 30 noches, la alarma inteligente te despertó antes en 4 ocasiones (media −11 min)."* Es honesto y más interesante que fingir magia.

---

## 5. Score de preparación / recuperación

### 5.1 La ciencia

- **HRV:** RMSSD es el índice vagal preferido en ventanas ultracortas; SDNN a 60 s está dominado por la arritmia sinusal respiratoria y es más ruidoso (Shaffer & Ginsberg 2017). **La HRV es log-normal** → transforma con `ln` antes de hacer estadística.
- **Baselines:** Plews et al. (2013, *Sports Med*) — usa medias móviles de ln(rMSSD) y el *smallest worthwhile change* (≈ 0.5 × SD del baseline) para separar señal de ruido diario.
- **HR mínima nocturna** > FC en reposo diurna como marcador de carga/recuperación.
- **Frecuencia respiratoria:** extremadamente estable noche a noche (SD ~0.5–1 rpm). Una desviación de +1 rpm es una señal fuerte de enfermedad o carga (Smarr et al. 2020, *Sci Rep*).

### 5.2 Baselines robustos

**No uses media y desviación típica.** Una noche con el reloj mal puesto te destroza el baseline. Mediana y MAD:

```
z_robusto(x) = 0.6745 · (x − mediana) / MAD
```

(el 0.6745 hace el MAD comparable a σ bajo normalidad)

| Métrica | Ventana | Mín. noches |
|---|---|---|
| ln(HRV) | 60 noches (deslizante) | 14 |
| HR mínima nocturna | 60 noches | 14 |
| Frecuencia respiratoria | 28 noches | 7 |

### 5.3 La fórmula

```
Componentes (cada uno mapeado a [0,1]):

C_deuda   = clip(1 − D_total / (2·Need), 0, 1)                        peso 0.30
C_durac   = clip(TST / Need, 0, 1.05)                                 peso 0.15
C_hrv     = σ( clip(z_lnHRV, −3, +1.5) / 1.5 )                        peso 0.20
C_fc      = σ( −clip(z_HRmin, −1.5, +3) / 1.5 )                       peso 0.12
C_contin  = 0.5·clip((SE − 0.75)/0.15, 0, 1) + 0.5·exp(−WASO/45min)   peso 0.10
C_alinea  = exp( −(SJL_noche / 1.5h)² )                               peso 0.08
C_resp    = σ( −clip(z_RR, −1.5, +3) / 1.5 )                          peso 0.05

Readiness = 100 · Σ wᵢ·Cᵢ
```

**Decisiones de diseño defendibles:**

- **Asimetría en HRV.** El tope superior en +1.5σ es deliberado. Una HRV *muy* alta no es "muy bueno": puede ser saturación parasimpática, artefacto, o simplemente ruido. Recompensas lo normal, penalizas lo bajo.
- **La deuda pesa más que la HRV** (0.30 vs 0.20). La duración del sueño tiene evidencia causal mucho más fuerte que cualquier índice de HRV de consumo.
- **Renormaliza los pesos** si falta un componente (p. ej. <3 muestras de HRV esa noche → descarta C_hrv y reparte su peso).

### 5.4 Calibración y honestidad

```
n < 14 noches:   NO muestres un número. Muestra los componentes crudos
                 y "Calibrando (n/14)".
14 ≤ n < 28:     Score con etiqueta "Confianza media".
n ≥ 28:          "Confianza alta".
```

> ⚠️ **No existe validación publicada de que ningún readiness score de consumo prediga rendimiento.** Whoop, Oura, Garmin: ninguno. Preséntalo como **indicador relativo de tendencia**, nunca como verdad absoluta ni como consejo médico.

> ⚠️ **Ortosomnia** (Baron et al. 2017, *J Clin Sleep Med*): la obsesión por optimizar métricas de sueño puede *causar* insomnio. Implicaciones concretas de diseño:
> - Nada de rojo/alarma para un score bajo.
> - Opción de ocultar el score.
> - Lenguaje neutro: "menos recuperado de lo habitual", no "recuperación pobre".
> - Nunca sugieras patología. Si algo raro persiste, sugiere consultar a un profesional y punto.

---

## 6. Fiabilidad, calibración e incertidumbre

### 6.1 Cuántas noches para cada cosa

| Parámetro | Mínimo | Bueno | Estimador |
|---|---|---|---|
| Duración de ciclo | 10 noches (≥3 REM c/u) | 25 | Theil–Sen + shrinkage a 90 min |
| MSFsc | 7 días (≥2 libres) | 28 días (≥8 libres) | Mediana circular |
| Baseline ln(HRV) | 14 | 60 | Mediana + MAD |
| Baseline HR mín. | 14 | 60 | Mediana + MAD |
| Baseline respiración | 7 | 28 | Mediana + MAD |
| SRI (regularidad) | 7 | 28 | Ventana deslizante |
| **Necesidad de sueño** | 5 noches libres sin alarma | 10 | Mediana del TST |
| Parámetros del modelo (τ, H₀) | 20 noches libres | 60 | Grid search |

### 6.2 Siestas

```
siesta := episodio de sueño que
          (a) empieza entre 10:00 y 20:00, Y
          (b) dura < 3 h, Y
          (c) está separado ≥2 h del episodio principal

→ INCLUIR en el simulador de S      (disipa presión — ese es justo el punto)
→ EXCLUIR de: baselines HRV/HR/RR, cálculo de MSFsc, estimación de ciclo
→ INCLUIR en el TST diario para la deuda, con un factor de eficiencia ~0.8
  (una siesta de 60 min no equivale a 60 min de sueño nocturno)
```

### 6.3 Noches sin reloj, outliers, duplicados

**Detección de noche sin datos:**

```
Si no hay muestras de sleepAnalysis NI de heartRate durante >4 h
dentro de la ventana habitual [B̄−2h, W̄+2h]  →  noche "sin datos"
```

**Qué hacer:** NO adivines. Imputa el S usando el horario habitual, marca la noche con `confidence: .imputed`, y **ensancha el intervalo de la recomendación del día siguiente** (±45 min en lugar de ±15). Díselo: *"Falta el dato de anoche — la recomendación de hoy es menos precisa."*

**Rechazo de outliers:**

```
Descarta la noche de los BASELINES (no del simulador de S) si:
    TST < 3 h
    ó  eficiencia < 50%
    ó  >30% de la ventana de sueño sin muestras de HR
    ó  |z_robusto| > 4 en cualquier métrica
```

**Duplicados en HealthKit — la trampa clásica.** HealthKit acumula muestras de sueño de **múltiples fuentes solapadas**: el iPhone escribe `inBed` desde el horario de Sleep Focus, el Watch escribe las fases, y cualquier app de terceros escribe lo suyo. Si sumas ingenuamente, obtienes 14 h de sueño.

```swift
func sleepMetrics(from samples: [HKCategorySample])
        -> (periodo: TimeInterval, tst: TimeInterval, waso: TimeInterval) {

    // 1) Filtra a la fuente del Apple Watch
    let watch = samples.filter {
        $0.sourceRevision.productType?.hasPrefix("Watch") == true
    }

    // 2) Une intervalos solapados
    func merge(_ ivs: [DateInterval]) -> [DateInterval] {
        let sorted = ivs.sorted { $0.start < $1.start }
        var out: [DateInterval] = []
        for iv in sorted {
            if let last = out.last, iv.start <= last.end {
                out[out.count - 1] = DateInterval(start: last.start,
                                                  end: max(last.end, iv.end))
            } else {
                out.append(iv)
            }
        }
        return out
    }

    let asleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
    ]

    let asleep = merge(watch.filter { asleepValues.contains($0.value) }
                            .map { DateInterval(start: $0.startDate, end: $0.endDate) })
    let awake  = merge(watch.filter { $0.value == HKCategoryValueSleepAnalysis.awake.rawValue }
                            .map { DateInterval(start: $0.startDate, end: $0.endDate) })

    let tst = asleep.reduce(0) { $0 + $1.duration }
    guard let first = asleep.first?.start, let last = asleep.last?.end else {
        return (0, 0, 0)
    }
    let span = DateInterval(start: first, end: last)
    let waso = awake.filter { span.intersects($0) }.reduce(0) { $0 + $1.duration }
    return (span.duration, tst, waso)      // eficiencia = tst / span.duration
}
```

> **Nota:** `inBed` en el SE 2 casi siempre viene del *horario* de Sleep Focus (iPhone), no de detección real. No lo uses como TIB si quieres una eficiencia significativa — usa el periodo de sueño (primer a último `asleep*`).

### 6.4 Necesidad de sueño personal

No asumas 8 h. Estímala:

```
Need = mediana(TST) sobre noches que cumplan TODAS:
       - día libre (agenda, §3.2)
       - sin alarma
       - despertar espontáneo
       - deuda D_total < 1 h la noche previa
         (si no, estás midiendo recuperación, no necesidad)

Mínimo 5 noches así. Antes de eso: Need = 8.0 h (default poblacional).
Acota Need ∈ [6.5, 9.5] h.
```

### 6.5 Cómo mostrar la incertidumbre

Aquí es donde le ganas a Apple, que no muestra ninguna:

```
❌  "Acuéstate a las 23:20"

✅  "Acuéstate entre 23:05 y 23:35"
    [Confianza: alta · 34 noches]
    ▸ Hoy +25 min de sueño: deuda acumulada 3.2 h, HRV −1.4σ
    ▸ Tu cronotipo natural: punto medio 04:10 (±40 min)
    ▸ Jet lag social: 1 h 15 min  ← esto es lo que te está costando los lunes
```

La **explicabilidad** es a la vez un diferenciador de producto y una obligación epistémica: si el usuario no puede auditar la recomendación, no puede detectar cuándo te equivocas.

---

## 7. Señales del SE 2 que estás infrautilizando

### 7.1 `timeInDaylight` — la más importante, con diferencia

Disponible desde **iOS 17 / watchOS 10**: `HKQuantityTypeIdentifier.timeInDaylight`. Es la única señal de luz que tienes, y la luz es **el único zeitgeber con efecto causal grande** sobre la fase circadiana.

**La curva de respuesta de fase (PRC)** — Khalsa et al. (2003, *J Physiol*), St Hilaire et al. (2012):

```
Luz DESPUÉS del CBTmin  →  ADELANTA la fase (te haces más matutino)
Luz ANTES del CBTmin    →  RETRASA la fase (te haces más vespertino)
Cruce ≈ en el CBTmin

Magnitud realista con luz exterior matinal: 15–30 min de adelanto/día
```

**Producto:** en vez de decirle solo *cuándo* dormir, dile **cuándo buscar luz**. Es lo único que puede mover su biología en lugar de pelearse con ella.

```swift
let type = HKQuantityType(.timeInDaylight)
// Las muestras tienen startDate/endDate → puedes binear por hora del día,
// no solo obtener el total diario.
let q = HKStatisticsCollectionQuery(
    quantityType: type,
    quantitySamplePredicate: predicate,
    options: .cumulativeSum,
    anchorDate: startOfDay,
    intervalComponents: DateComponents(hour: 1)   // perfil horario de exposición
)
```

**Recomendación generada:**

```
si SJL > 1 h y el objetivo es adelantar:
    "Sal a la calle 20 min entre las 08:00 y las 09:30.
     Ayer solo registraste 3 min de luz exterior antes del mediodía."
    + "Baja las luces a partir de las 22:30."
```

> ⚠️ **Limitaciones honestas:** `timeInDaylight` es una señal umbralizada (no da lux), se confunde con mangas largas, y no distingue una oficina muy iluminada de la calle. Útil como *proxy grueso* y para *nudges*; no para inferencia cuantitativa de fase.

### 7.2 `HKHeartbeatSeriesSample` → RMSSD real

HealthKit expone las **series de latidos** (intervalos RR) asociadas a las lecturas de HRV. Te estás quedando con el SDNN que calcula Apple; puedes calcular tú el **RMSSD**, más fiable en ventanas ultracortas.

```swift
let seriesType = HKSeriesType.heartbeat()
// 1) HKSampleQuery → HKHeartbeatSeriesSample de la noche
// 2) Por cada uno, HKHeartbeatSeriesQuery para enumerar los latidos

let q = HKHeartbeatSeriesQuery(heartbeatSeries: series) {
    _, timeSinceSeriesStart, precededByGap, done, error in
    // Acumula timeSinceSeriesStart → RR = diff(timestamps)
    // Descarta los latidos con precededByGap == true
    if done {
        // RMSSD = sqrt( mean( (RR[i+1] − RR[i])² ) )
        // Filtra artefactos: descarta |RR[i+1] − RR[i]| > 0.2 · RR[i]
    }
}
```

**Válido a 60 s:** RMSSD, pNN50.
**NO válido a 60 s:** cualquier métrica de dominio frecuencial. LF necesita ≥2 min. No calcules LF/HF con esto por muy tentador que sea.

### 7.3 La forma de la curva de HR nocturna

No te quedes en "pulso medio / mínimo". Extrae:

| Feature | Qué significa | Cómo |
|---|---|---|
| **Hora del nadir** | Proxy (sesgado) de fase circadiana | argmin de la mediana móvil 60 min |
| **Profundidad del dip** | `(RHR_diurna − HR_min) / RHR_diurna`. Un dip pobre (<15%) sugiere mala recuperación | Directo |
| **Tiempo hasta el nadir** | Cuánto tarda en bajar. Lento = estrés / alcohol / cena tardía | Desde el inicio del sueño |
| **Pendiente de subida matinal** | Anticipación circadiana del despertar | Regresión sobre las últimas 2 h |
| **Firma de alcohol** | HR elevada + HRV suprimida en la **primera mitad** de la noche, normalizándose en la segunda | Compara mitades |

La firma de alcohol es especialmente detectable y accionable. Un estudiante de 18 años en España tiene fines de semana. Detectarla y cuantificar el coste (*"las noches con esta firma, tu readiness del día siguiente cae 18 puntos de media"*) es **más valioso que cualquier score**.

### 7.4 Frecuencia respiratoria

Muy estable (SD ~0.5–1 rpm noche a noche). Por eso una desviación pequeña es significativa:

```
si z_RR > +2   (≈ +1–2 rpm sobre tu mediana de 28 noches):
    bandera de "carga fisiológica"
    → posible enfermedad incipiente, alcohol, o entrenamiento muy duro
    → penaliza el readiness Y sugiere priorizar duración esta noche
```

### 7.5 `CMSensorRecorder` — acelerómetro crudo a 50 Hz, coste ~cero

La joya escondida, y **tú ya dominas CoreMotion** por tu contador de repeticiones.

`CMSensorRecorder.recordAccelerometer(forDuration:)` graba a 50 Hz en un buffer de bajo consumo (~12 h) que recuperas después con `accelerometerData(from:to:)`. Es decir: **acelerómetro crudo de toda la noche sin sesión activa y sin coste apreciable de batería.**

Qué desbloquea:

1. **Tu propia actigrafía** — Cole–Kripke (1992), o mejor el método del *z-angle* de van Hees et al. (2018), que detecta la ventana de sueño sin diario y es más robusto.
2. **Tu propio staging.** **Walch, Huang, Forger & Goldstein (2019, *Sleep* 42(12):zsz180)** publicaron exactamente esto: predicción de fases desde aceleración cruda + HR de PPG de un Apple Watch, **con código abierto**. Es tu línea base y tu punto de partida si quieres batir a Apple en staging.
3. **Microestructura que Apple no expone:** índice de fragmentación, densidad de movimientos, periodicidad (proxy de piernas inquietas).

> ⚠️ `CMSensorRecorder` tiene fama de caprichoso (reportes de devolver `nil` sin razón aparente; requiere autorización de `CMMotionActivityManager`). **Verifícalo empíricamente antes de construir sobre él.** Prueba de humo: graba 1 h, intenta recuperar, cuenta las muestras.

### 7.6 Índice de Regularidad del Sueño (SRI) — barato y potentísimo

Lo puedes calcular **hoy**, con los datos que ya tienes, y es de lo mejor validado que existe.

```
SRI = 2 · P(mismo estado sueño/vigilia en el minuto m del día d y del día d+1) − 1
      × 100

Rango: −100 (aleatorio) a +100 (idéntico cada día). Adultos típicos: 60–80.
```

- **Phillips et al. (2017, *Sci Rep*):** en estudiantes universitarios, el SRI predijo el rendimiento académico **mejor que la duración del sueño**. (Sí: estudiantes. Tú.)
- **Windred et al. (2024, *Sleep*):** en UK Biobank (~60.000 personas), **la regularidad del sueño predijo la mortalidad mejor que la duración**.

```swift
/// SRI sobre una rejilla binaria de 1440 min/día × N días
func sleepRegularityIndex(_ grid: [[Bool]]) -> Double {
    guard grid.count >= 2 else { return .nan }
    var matches = 0, total = 0
    for d in 0..<(grid.count - 1) {
        for m in 0..<1440 {
            if grid[d][m] == grid[d + 1][m] { matches += 1 }
            total += 1
        }
    }
    return 200.0 * Double(matches) / Double(total) - 100.0
}
```

Apple mide "consistencia de la hora de acostarse" (30 pts del Sleep Score). El SRI es estrictamente superior: captura la arquitectura de todo el día, no un solo punto.

### 7.7 Tu agenda (backend FastAPI)

Ya la tienes. Úsala más:

- **Clasificar días libres** para MSFsc (§3.2). Nadie más puede hacer esto.
- **Planificar hacia delante:** *"Tienes examen el jueves a las 8:00. Empieza a adelantar tu horario 20 min/día desde hoy y busca luz por la mañana."*
- **Detectar sobrecarga:** semanas con muchos eventos → sube el peso de la deuda en la función de coste.

### 7.8 Tu app de gym

Cruza los datos:

- **Carga de entrenamiento** → componente del readiness.
- **Entrenamiento tardío:** si acaba <1 h antes de B, la FC nocturna sube y la latencia se alarga. Detéctalo y avísale. (Metaanálisis de Stutz et al. 2019: el ejercicio vespertino *no* daña el sueño salvo cuando es intenso y termina muy cerca de la hora de dormir.)
- El puente natural: *"Anoche dormiste 5.8 h con readiness 48. Baja el volumen hoy un 20%."*

---

## 8. Lo que NO es posible (léelo dos veces)

| # | Límite | Detalle |
|---|---|---|
| 1 | ❌ **Medir fases con precisión clínica** | κ multiclase del Apple Watch: 0.20–0.60 según el estudio. Especificidad de vigilia: 29–52%. Sensibilidad de sueño profundo: ~50–62%. Todo lo que construyas encima hereda ese error. |
| 2 | ❌ **Fase circadiana absoluta (DLMO / CBTmin)** | Sin temperatura ni melatonina. ±1–1.5 h en el mejor caso. Estima *deriva*, no valor absoluto. |
| 3 | ❌ **Predecir la fase del ciclo 8 h vista** | El error se acumula a ±40 min. Es astrología. Separa "cuánto" (predecible) de "cuándo exactamente" (solo en tiempo real). |
| 4 | ❌ **Temperatura, SpO₂, ECG** | El SE 2 no los tiene. El SE 3 sí tiene temperatura. |
| 5 | ❌ **Breathing Disturbances / apnea** | Requiere Series 9+, Ultra 2, o SE 3. No tendrás `appleSleepingBreathingDisturbances` en tu reloj. |
| 6 | ❌ **Fase del ciclo menstrual** | Requiere temperatura. Relevante para la mitad de tus usuarias potenciales; dilo abiertamente. |
| 7 | ❌ **Crear alarmas del sistema desde la app** | Solo háptico vía sesión de runtime extendido, o Atajos → alarma nativa. |
| 8 | ❌ **`HKWorkoutSession` toda la noche** | 40–70% de batería. No. |
| 9 | ⚠️ **La sesión de alarma se programa en primer plano** | Una sesión a la vez. Necesita fricción de UX o el workaround de reprogramar desde el callback. |
| 10 | ⚠️ **El SDNN de Apple es ruidoso** | Muestreo oportunista, pocas lecturas/noche, ventanas de ~60 s. No interpretes una sola noche. Medianas móviles siempre. |
| 11 | ⚠️ **`timeInDaylight` es grueso** | Binario, sin lux, se confunde con la ropa. Útil para nudges, no para inferencia. |
| 12 | ❌ **Validar nada de esto** | Sin PSG no tienes verdad de referencia. Lo mejor posible: validación n-of-1 (§9.5). Comunícalo. |

---

## 9. Plan de implementación por fases

Ordenado por relación impacto / esfuerzo.

### Fase 0 — Higiene de datos · 1–2 días · **impacto ALTO, esfuerzo BAJO**

Esto solo ya arregla la mayor fuente de error de tu app actual.

- [ ] Deduplicación de HealthKit por `HKSource` + unión de intervalos solapados
- [ ] Estadística robusta: mediana + MAD en todos los baselines
- [ ] **Estadística circular** para el punto medio de sueño y las horas de reloj
- [ ] Clasificador siesta / noche
- [ ] Rechazo de outliers + detección de noches sin reloj
- [ ] **Sustituir el estimador de ciclo:** Theil–Sen sobre inicios de REM + shrinkage hacia 90 min (k = 12)
- [ ] Mostrar intervalos, no puntos

### Fase 1 — Motor de dos procesos · 3–5 días · **impacto MUY ALTO, esfuerzo MEDIO**

Aquí es donde te vuelves genuinamente más científico que Apple. Y es barato.

- [ ] Simulador de Proceso S sobre el historial completo (siestas incluidas)
- [ ] Proceso C con la expansión armónica de Daan
- [ ] Deuda de dos escalas (τ_f = 2 d, τ_s = 21 d, asimetría κ⁺/κ⁻)
- [ ] Estimación de `Need` personal desde noches libres sin alarma
- [ ] MSFsc + SJL, con **días libres detectados desde tu agenda**
- [ ] Optimizador (B, W) con función de coste + restricciones (grid de 5 min)
- [ ] Política de repago: tope +60 min/noche, 2/3 adelantando B, guarda de Spielman
- [ ] Restricción dura: **nunca recomendar B más de 60 min antes de B̄** (zona prohibida)
- [ ] Explicabilidad: desglose textual de por qué la recomendación es la que es

### Fase 2 — Recuperación + luz · 3–5 días · **impacto ALTO, esfuerzo MEDIO**

- [ ] RMSSD desde `HKHeartbeatSeriesSample` (mejor que SDNN)
- [ ] Readiness score con z robustos, ln(HRV), calibración explícita (14/28 noches)
- [ ] **SRI** (índice de regularidad) — barato, validadísimo, Apple no lo tiene
- [ ] Features de la curva de HR nocturna (nadir, dip, firma de alcohol)
- [ ] `timeInDaylight` → **recomendaciones de exposición a luz basadas en la PRC**
- [ ] Detector de deriva de fase (nadir de HR con horario estable)
- [ ] Guardas anti-ortosomnia (lenguaje neutro, opción de ocultar el score)

### Fase 3 — Alarma inteligente · 1–2 semanas · **impacto MEDIO, esfuerzo ALTO**

Vistoso, pero el beneficio real es modesto (~1 de cada 10 mañanas). **Hazlo después.**

- [ ] `WKExtendedRuntimeSession` con `WKBackgroundModes = ["alarm"]`
- [ ] Actigrafía en tiempo real (CoreMotion 25 Hz, épocas de 30 s)
- [ ] Stream de HR durante la sesión
- [ ] Regla de umbral decreciente + disparo garantizado en el deadline
- [ ] **Alarma nativa vía Atajos como red de seguridad** (obligatorio)
- [ ] Reprogramación automática desde el callback de sesión (verificar en dispositivo)
- [ ] Medición de batería: 7 noches con vs. 7 sin. Reportar el dato real en la app.

### Fase 4 — Investigación · semanas · **impacto INCIERTO, esfuerzo MUY ALTO**

Solo si las fases anteriores están cerradas.

- [ ] Prueba de humo de `CMSensorRecorder` (¿devuelve datos de verdad?)
- [ ] Pipeline de staging propio: Walch et al. 2019 (accel crudo + HR). Código abierto.
- [ ] Modelo de Kronauer con `timeInDaylight` como entrada de luz
- [ ] Ajuste de τ_r, τ_d, H₀, a a sus datos personales

### 9.5 Validación honesta (n-of-1)

No puedes hacer PSG. Pero **sí puedes hacer ciencia de verdad sobre ti mismo:**

```
Diseño:
  Cada noche registra:  B_recomendada, W_recomendada, adherencia (Δ real),
                        readiness_día_siguiente, TST, SE
  Durante 60+ noches.

Análisis:
  readiness_{n+1} ~ β₀ + β₁·|B_real − B_recomendada| + β₂·TST + β₃·SRI + ε

  Si β₁ < 0 y es significativo → seguir tu recomendación se asocia con mejor
  readiness. Es correlacional, no causal, pero es infinitamente más de lo que
  hace cualquier app del mercado.

Mejor aún: ALEATORIZA. Un día sí, un día no, recomienda B óptima vs. B habitual.
Eso sí es causal: es un ensayo cruzado n-of-1.
```

Esto sería, literalmente, el mejor argumento de tu app: *"aquí está la evidencia de que funciona para ti."*

---

## 10. Referencias

**Modelo de dos procesos**
- Borbély AA (1982). A two process model of sleep regulation. *Hum Neurobiol* 1(3):195–204.
- Daan S, Beersma DGM, Borbély AA (1984). Timing of human sleep: recovery process gated by a circadian pacemaker. *Am J Physiol* 246:R161–R183.
- Achermann P, Borbély AA (2003). Mathematical models of sleep regulation. *Front Biosci* 8:s683–93.
- Dijk DJ, Czeisler CA (1995). Contribution of the circadian pacemaker and the sleep homeostat to sleep propensity, sleep structure, EEG slow waves, and sleep spindle activity in humans. *J Neurosci* 15(5):3526–38.
- Lavie P (1986). Ultrashort sleep-waking schedule III: "Gates" and "forbidden zones" for sleep. *Electroencephalogr Clin Neurophysiol* 63(5):414–25.
- Skeldon AC, Dijk DJ, Derks G (2014). Mathematical models for sleep-wake dynamics: comparison of the two-process model and a mutual inhibition neuronal model. *PLoS ONE* 9(8):e103877.
- Phillips AJK, Robinson PA (2007). A quantitative model of sleep-wake dynamics based on the physiology of the brainstem ascending arousal system. *J Biol Rhythms* 22(2):167–79.

**Deuda de sueño**
- Van Dongen HPA, Maislin G, Mullington JM, Dinges DF (2003). The cumulative cost of additional wakefulness: dose-response effects on neurobehavioral functions and sleep physiology from chronic sleep restriction and total sleep deprivation. *Sleep* 26(2):117–26.
- Belenky G, Wesensten NJ, Thorne DR, et al. (2003). Patterns of performance degradation and restoration during sleep restriction and subsequent recovery: a sleep dose-response study. *J Sleep Res* 12(1):1–12.
- McCauley P, Kalachev LV, Smith AD, Belenky G, Dinges DF, Van Dongen HPA (2009). A new mathematical model for the homeostatic effects of sleep loss on neurobehavioral performance. *J Theor Biol* 256(2):227–39.
- Spielman AJ, Saskin P, Thorpy MJ (1987). Treatment of chronic insomnia by restriction of time in bed. *Sleep* 10(1):45–56.

**Cronotipo y jet lag social**
- Roenneberg T, Wirz-Justice A, Merrow M (2003). Life between clocks: daily temporal patterns of human chronotypes. *J Biol Rhythms* 18(1):80–90.
- Roenneberg T, Kuehnle T, Pramstaller PP, et al. (2004). A marker for the end of adolescence. *Curr Biol* 14(24):R1038–9.
- Wittmann M, Dinich J, Merrow M, Roenneberg T (2006). Social jetlag: misalignment of biological and social time. *Chronobiol Int* 23(1–2):497–509.
- Kantermann T, Sung H, Burgess HJ (2015). Comparing the Morningness-Eveningness Questionnaire and Munich ChronoType Questionnaire to the Dim Light Melatonin Onset. *J Biol Rhythms* 30(5):449–53.

**Luz y fase circadiana**
- Khalsa SBS, Jewett ME, Cajochen C, Czeisler CA (2003). A phase response curve to single bright light pulses in human subjects. *J Physiol* 549(3):945–52.
- St Hilaire MA, Gooley JJ, Khalsa SBS, Kronauer RE, Czeisler CA, Lockley SW (2012). Human phase response curve to a 1 h pulse of bright white light. *J Physiol* 590(13):3035–45.
- Jewett ME, Forger DB, Kronauer RE (1999). Revised limit cycle oscillator model of human circadian pacemaker. *J Biol Rhythms* 14(6):493–99.

**Inercia y siestas**
- Tassi P, Muzet A (2000). Sleep inertia. *Sleep Med Rev* 4(4):341–53.
- Hilditch CJ, McHill AW (2019). Sleep inertia: current insights. *Nat Sci Sleep* 11:155–65.
- Brooks A, Lack L (2006). A brief afternoon nap following nocturnal sleep restriction: which nap duration is most recuperative? *Sleep* 29(6):831–40.

**Ciclos y arquitectura del sueño**
- Feinberg I, Floyd TC (1979). Systematic trends across the night in human sleep cycles. *Psychophysiology* 16(3):283–91.
- Carskadon MA, Dement WC. Normal human sleep: an overview. En: *Principles and Practice of Sleep Medicine*, 6ª ed. Elsevier. — referencia estándar para la arquitectura de ciclos (~90 min, alargamiento a lo largo de la noche, SWS concentrado en la primera mitad).

**Actigrafía y staging con wearables**
- Cole RJ, Kripke DF, Gruen W, Mullaney DJ, Gillin JC (1992). Automatic sleep/wake identification from wrist activity. *Sleep* 15(5):461–69.
- Sadeh A, Sharkey KM, Carskadon MA (1994). Activity-based sleep-wake identification: an empirical test of methodological issues. *Sleep* 17(3):201–07.
- van Hees VT, Sabia S, Jones SE, et al. (2018). Estimating sleep parameters using an accelerometer without sleep diary. *Sci Rep* 8:12975.
- **Walch O, Huang Y, Forger D, Goldstein C (2019). Sleep stage prediction with raw acceleration and photoplethysmography heart rate data derived from a consumer wearable device. *Sleep* 42(12):zsz180.** ← tu punto de partida si haces staging propio; código abierto.
- Marino M, Li Y, Rueschman MN, et al. (2013). Measuring sleep: accuracy, sensitivity, and specificity of wrist actigraphy compared to polysomnography. *Sleep* 36(11):1747–55.

**Validación de wearables frente a PSG**
- Chinoy ED, Cuellar JA, Huwa KE, et al. (2021). Performance of seven consumer sleep-tracking devices compared with polysomnography. *Sleep* 44(5):zsaa291.
- Miller DJ, Sargent C, Roach GD (2022). A validation of six wearable devices for estimating sleep, heart rate and heart rate variability in healthy adults. *Sensors* 22(16):6317. — *Apple Watch: acuerdo multiclase 53%, κ = 0.20.*
- (2025). A performance validation of six commercial wrist-worn wearable sleep-tracking devices for sleep stage scoring compared to polysomnography. *SLEEP Advances* 6(2):zpaf021. — *Apple Watch Series 8: κ = 0.53.*

**HRV**
- Shaffer F, Ginsberg JP (2017). An overview of heart rate variability metrics and norms. *Front Public Health* 5:258.
- Plews DJ, Laursen PB, Stanley J, Kilding AE, Buchheit M (2013). Training adaptation and heart rate variability in elite endurance athletes: opening the door to effective monitoring. *Sports Med* 43(9):773–81.
- Task Force of the ESC and NASPE (1996). Heart rate variability: standards of measurement, physiological interpretation, and clinical use. *Circulation* 93(5):1043–65.

**Fase circadiana desde wearables**
- Bowman C, Huang Y, Walch OJ, et al. (2021). A method for characterizing daily physiology from widely used wearables. *Cell Rep Med* 2(4):100240.
- Huang Y, Mayer C, Cheng P, et al. (2021). Predicting circadian phase across populations: a comparison of mathematical models and wearable devices. *Sleep* 44(10):zsab126.

**Regularidad del sueño**
- Phillips AJK, Clerx WM, O'Brien CS, et al. (2017). Irregular sleep/wake patterns are associated with poorer academic performance and delayed circadian and sleep/wake timing. *Sci Rep* 7:3216.
- Windred DP, Burns AC, Lane JM, Saxena R, Rutter MK, Cain SW, Phillips AJK (2024). Sleep regularity is a stronger predictor of mortality risk than sleep duration: a prospective cohort study. *Sleep* 47(1):zsad253.

**Riesgos de producto**
- Baron KG, Abbott S, Jao N, Manalo N, Mullen R (2017). Orthosomnia: are some patients taking the quantified self too far? *J Clin Sleep Med* 13(2):351–54.

**Ejercicio, enfermedad, respiración**
- Stutz J, Eiholzer R, Spengler CM (2019). Effects of evening exercise on sleep in healthy participants: a systematic review and meta-analysis. *Sports Med* 49(2):269–87.
- Smarr BL, Aschbacher K, Fisher SM, et al. (2020). Feasibility of continuous fever monitoring using wearable devices. *Sci Rep* 10:21640.

**APIs de Apple relevantes**
- `HKQuantityTypeIdentifier.timeInDaylight` — iOS 17.0+ / watchOS 10.0+
- `HKHeartbeatSeriesSample` / `HKHeartbeatSeriesQuery` — iOS 13.0+ / watchOS 6.0+
- `WKExtendedRuntimeSession` + `WKBackgroundModes = ["alarm"]` — watchOS 6.0+
- `CMSensorRecorder` — watchOS 2.0+ (fiabilidad irregular; verificar en dispositivo)
- `HKCategoryValueSleepAnalysis` (`asleepCore` / `asleepDeep` / `asleepREM` / `awake` / `inBed`) — watchOS 9.0+ para las fases
- **Sleep Score** (watchOS 26) — **no expuesto a terceros vía HealthKit.** Es exclusivo de la app Sleep / Salud de Apple. No cuentes con leerlo.
- `appleSleepingWristTemperature`, `oxygenSaturation`, `appleSleepingBreathingDisturbances` — **no disponibles en el SE 2.**

---

## Apéndice: una nota sobre el enfoque

La tentación con este tipo de proyecto es añadir features. Resiste.

El diferencial real frente a Apple no está en tener más números, sino en tres cosas que ellos no hacen y que son baratas para ti:

1. **Modelar la fisiología** (dos procesos + deuda alostática) en vez de contar horas.
2. **Explicar** cada recomendación y mostrar su incertidumbre.
3. **Recomendar la única intervención con efecto causal grande:** luz matinal.

Todo lo demás — la alarma inteligente, el staging propio, el score bonito — es secundario. Haz todas las fases, 1 por 1.
