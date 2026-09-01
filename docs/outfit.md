# Sistema de Selección Automática de Outfit Diario
## Documento técnico de diseño — v1.0

**Destinatario:** ingeniería (backend Python + app Swift/iOS).
**Alcance:** especificación completa de datos, fórmulas, tablas y reglas. Sin código. Toda constante numérica de este documento aparece consolidada en el **Apéndice A (constantes de calibración)** para poder ajustarla sin releer el texto.

**Honestidad epistémica:** este sistema mezcla tres niveles de evidencia, y se marca cada uno donde corresponde: **[T]** teoría formal establecida (colorimetría, confort térmico ISO/ASHRAE), **[P]** práctica profesional codificada del estilismo (regla 60-30-10, combinaciones clásicas), y **[H]** heurística razonable sin validación empírica fuerte (análisis de color estacional, normas sociales de repetición). Un buen sistema de recomendación cotidiano puede construirse sobre los tres, pero el ingeniero debe saber qué constantes son física y cuáles son criterio de estilo calibrable.

### Convenciones y notación

- `clamp(x, a, b)` = min(max(x, a), b).
- Todos los scores parciales viven en [0.0, 1.0]; 1.0 = ideal.
- `Δh(a,b)` = distancia angular circular entre dos tonos en la rueda de color: `min(|h_a − h_b| mod 360, 360 − |h_a − h_b| mod 360)`.
- Clases de luminosidad `L ∈ {1..5}`: 1 = muy oscuro, 5 = muy claro.
- Clases de saturación `S ∈ {0..3}`: 0 = acromático, 1 = apagado (muted), 2 = medio, 3 = vivo.
- Temperatura de color `T ∈ {W, C, N}`: cálido, frío, neutro.
- Una prenda (`ClothingItem`) aporta: `categoria`, `subcategoria`, `colores: [(color, pct)]` ordenada por superficie descendente con Σpct = 1.0, `formalidad ∈ [1,5]`, `calor ∈ [1,5]`, `etiquetas` (p. ej. `impermeable`, `cortavientos`, `lona`, `ante`, `lino`), `estado ∈ {limpia, sucia, lavadora}`, `historial_usos: [fecha]`, y opcionalmente `fungible_group_id` (§6.5).

---

# BLOQUE 1 — Paleta de colores

## 1.1 Paleta estándar de 20 colores

Criterio de selección **[P]**: cobertura completa del vestuario cotidiano occidental con el mínimo de colores; 5 neutrales absolutos (base de cualquier armario), 5 neutrales suaves (los "casi neutrales" de la sastrería: marino, oliva, chocolate, camel, crema) y 10 acentos que barren la rueda de color en versiones vestibles (nada de fucsia eléctrico ni verde lima). El denim se mapea a marino/royal/celeste según lavado.

| # | Código | Nombre | Hex | Familia | Hue (°) | S | L | Neutralidad |
|---|---|---|---|---|---|---|---|---|
| 1 | NE | Negro | `#1A1A1A` | neutral | — | 0 | 1 | Neutral absoluto |
| 2 | BL | Blanco | `#FAFAFA` | neutral | — | 0 | 5 | Neutral absoluto |
| 3 | GC | Gris claro | `#C8C8C8` | neutral | — | 0 | 4 | Neutral absoluto |
| 4 | GA | Gris antracita | `#4B4B4B` | neutral | — | 0 | 2 | Neutral absoluto |
| 5 | BE | Beige | `#D8C7A5` | neutral (cálido) | — | 0 | 4 | Neutral absoluto |
| 6 | CR | Crema / marfil | `#F2EAD3` | warm | 40 | 1 | 5 | Neutral suave |
| 7 | MA | Azul marino | `#20304F` | cool | 220 | 1 | 1 | Neutral suave |
| 8 | RY | Azul royal | `#2B5DAB` | cool | 218 | 3 | 3 | Acento |
| 9 | CE | Azul celeste | `#9DBFDD` | cool | 210 | 1 | 4 | Acento |
| 10 | OL | Verde oliva | `#6B7239` | warm | 70 | 1 | 2 | Neutral suave |
| 11 | VB | Verde bosque | `#2F5D3A` | cool | 135 | 1 | 2 | Acento |
| 12 | VM | Verde menta | `#A8D5BA` | cool | 145 | 1 | 4 | Acento |
| 13 | CH | Marrón chocolate | `#5A3E2B` | warm | 25 | 1 | 2 | Neutral suave |
| 14 | CA | Camel | `#B98C50` | warm | 35 | 1 | 3 | Neutral suave |
| 15 | BU | Burdeos | `#6E1F2E` | warm | 350 | 1 | 2 | Acento |
| 16 | RO | Rojo | `#C03A2B` | warm | 8 | 3 | 3 | Acento |
| 17 | RP | Rosa palo | `#E8B4B8` | cool | 355 | 1 | 4 | Acento |
| 18 | MO | Mostaza | `#D2A72C` | warm | 45 | 2 | 3 | Acento |
| 19 | TE | Terracota | `#C96F4A` | warm | 18 | 2 | 3 | Acento |
| 20 | LA | Lavanda | `#9E8FC2` | cool | 265 | 1 | 3 | Acento |

Temporadas compatibles según análisis de color estacional (umbral: score ≥ 0.7 en la tabla completa de §3.2):

| Código | Spring | Summer | Autumn | Winter |
|---|---|---|---|---|
| NE | — | — | — | ✔ |
| BL | — | — | — | ✔ |
| GC | — | ✔ | — | ✔ |
| GA | — | — | — | ✔ |
| BE | ✔ | — | ✔ | — |
| CR | ✔ | — | ✔ | — |
| MA | — | ✔ | — | ✔ |
| RY | ✔ | — | — | ✔ |
| CE | ✔ | ✔ | — | — |
| OL | — | — | ✔ | — |
| VB | — | — | ✔ | ✔ |
| VM | ✔ | ✔ | — | — |
| CH | — | — | ✔ | — |
| CA | ✔ | — | ✔ | — |
| BU | — | — | ✔ | ✔ |
| RO | ✔ | — | — | ✔ |
| RP | ✔ | ✔ | — | — |
| MO | ✔ | — | ✔ | — |
| TE | ✔ | — | ✔ | — |
| LA | — | ✔ | — | ✔ |

## 1.2 Asignación automática de roles cromáticos (dominante 60 / secundario 30 / acento 10)

La regla 60-30-10 procede del diseño de interiores y del estilismo profesional **[P]**: un color ancla la composición, otro la apoya, un tercero la remata. En ropa el "peso" de un color no es su intensidad sino la **superficie visible** que ocupa. El sistema asigna roles calculando la superficie relativa de cada color en el outfit.

**Tabla de superficie relativa por categoría** (unidades normalizadas, aproximación del área visible frontal de un adulto):

| Categoría / subcategoría | Superficie `A` |
|---|---|
| Abrigo largo | 1.00 |
| Chaqueta / bomber / sudadera con cremallera (outerwear) | 0.85 |
| Pantalón largo / jogger | 0.80 |
| Jersey / sudadera sin cremallera | 0.80 |
| Camiseta / camisa / polo | 0.70 |
| Falda | 0.60 |
| Shorts | 0.50 |
| Mochila | 0.30 |
| Zapatos / zapatillas / botas | 0.25 |
| Bufanda | 0.15 |
| Gorra / sombrero / gorro | 0.12 |
| Cinturón | 0.06 |
| Gafas de sol | 0.04 |
| Reloj | 0.03 |
| Collar / pulsera | 0.03 |
| Calcetines visibles (con shorts) | 0.08 |

Nota: cuando hay outerwear presente, la superficie efectiva del top se reduce a `0.4 × A_top` (queda parcialmente cubierto).

**Algoritmo de asignación de roles:**

1. Para cada color `c` del outfit: `superficie(c) = Σ_prendas A_prenda × pct_color_en_prenda` (con la corrección de cobertura del top).
2. Normalizar: `share(c) = superficie(c) / Σ superficie`.
3. Ordenar descendente: el primero es **dominante**, el segundo **secundario**, el resto **acentos**.
4. **Regla de guardia por saturación [P]:** un color con `S = 3` (vivo) y `share < 0.15` es siempre **acento**, ocupe el puesto que ocupe tras un empate; y un color con `S = 3` nunca puede ser dominante si existe un neutral con `share ≥ 0.30` (el ojo ancla en el neutral y lee el vivo como protagonista puntual).
5. Los neutrales absolutos pueden ser dominante, secundario o acento sin restricción.

Consecuencia práctica que confirma la intuición del enunciado: gorras (A=0.12), cinturones (A=0.06) y zapatillas (A=0.25) casi nunca alcanzan share suficiente para ser dominante o secundario → actúan estructuralmente como acento. Una zapatilla solo asciende a secundario en outfits de muy poca superficie (shorts + camiseta), lo cual es visualmente correcto: en verano el calzado pesa más en la composición.

---
# BLOQUE 2 — Matriz de compatibilidad cromática

## 2.1 Base teórica

La armonía de pares se apoya en tres fuentes **[T]**: la rueda de contrastes de Itten (*Kunst der Farbe*, 1961: complementarios, análogos, tríadas, contraste claro-oscuro), el sistema Munsell (hue/value/chroma como dimensiones independientes de la armonía) y, como validación empírica moderna, los modelos cuantitativos de armonía de pares de Ou & Luo (2006), cuyos experimentos con observadores muestran que la armonía percibida de dos colores crece con (a) la similitud de tono o su complementariedad, (b) la **diferencia de luminosidad** entre ambos, y (c) decrece cuando ambos son muy cromáticos a la vez. Esas tres regularidades son exactamente las que codifican las reglas siguientes, adaptadas a moda **[P]**: en ropa, a diferencia de en pintura, los neutrales son mayoría y la tolerancia al clash es menor (la prenda se lleva puesta en contextos sociales, no se contempla).

## 2.2 Reglas formales de puntuación de un par (c₁, c₂)

Orden de evaluación (la primera regla que aplica, gana; luego se aplican los modificadores):

| # | Regla | Condición | Score base |
|---|---|---|---|
| R1 | Excepción editorial | el par está en la tabla 2.3 | valor de la tabla |
| R2 | Neutral abs. + neutral abs. | ambos clase ABS | 0.90; **−0.15 si ΔL < 2** (dos neutrales sin contraste de valor se leen planos: negro+antracita, gris claro+beige) |
| R3 | Neutral abs. + cromático | uno clase ABS | 0.85; **+0.05 → 0.90** si el ABS es negro o blanco y el cromático es vivo (S=3): el máximo contraste acromático ancla un acento **[T, Itten: contraste claro-oscuro]**; **−0.05** si el ABS es beige y el cromático es frío (el beige tira a cálido); **−0.10 si ΔL < 1** (contraste de valor casi nulo) |
| R4 | Monocromía | ambos cromáticos, Δh ≤ 20° | 0.82 si ΔL ≥ 2 (degradado tonal elegante); **0.58 si ΔL < 2** (efecto "quise combinar y fallé": dos versiones casi iguales del mismo color compiten) |
| R5 | Análogos | 20° < Δh ≤ 75° | 0.78 (armonía de vecindad, bajo riesgo) |
| R6 | Discordantes | 75° < Δh ≤ 150° | 0.45; **+0.15 → 0.60** si al menos uno es apagado (S ≤ 1) **y** ΔL ≥ 1 (el mute rebaja la tensión) |
| R7 | Complementarios | 150° < Δh ≤ 210° | 0.68 si al menos uno es apagado (S ≤ 1) **o** muy oscuro (L ≤ 2); **0.52 si ambos vivos** (complementarios saturados vibran: correcto en diseño gráfico, agresivo en ropa) |

**Modificadores posteriores (acumulables):**

| Mod | Condición | Efecto |
|---|---|---|
| M1 | Cruce de temperatura W↔C (ninguno neutro) | −0.04 |
| M2 | Ambos vivos (S=3 los dos) | −0.10 (dos protagonistas compiten; responde a "¿cuándo funcionan dos acentos vivos juntos?": **casi nunca sin un neutral entre medias**; funcionan si son complementarios y al menos uno se apaga — eso ya lo captura R7) |
| M3 | Concordancia pastel: ambos S ≤ 1 y L ≥ 4 | score = max(score, 0.62) (dos pasteles apagados conviven aunque sus tonos choquen) |
| M4 | Suelo de neutral suave: uno de los dos ∈ {CR, MA, OL, CH, CA} | score = max(score, 0.70) (los "casi neutrales" de sastrería toleran casi cualquier acompañante **[P]**) |
| — | Clamp final | [0.30, 0.95] |

**Diagonal (mismo color en dos prendas):** neutrales absolutos 0.80 (total look negro/blanco/gris es deliberado y funciona); cromáticos 0.60 (monocromía exacta de un color con tinte es arriesgada: cualquier diferencia de tejido/desgaste se lee como error).

## 2.3 Excepciones editoriales

Quince pares donde la geometría de la rueda infravalora combinaciones consagradas por la práctica **[P]** (la rueda no sabe que camel+marino es el uniforme de la sastrería europea) o penaliza de más/menos un caso perceptivo concreto:

| Par | Score | Justificación |
|---|---|---|
| BL + CR | 0.60 | "Falso blanco": crema junto a blanco puro se lee como blanco sucio, no como color distinto |
| MA + CA | 0.85 | Camel + marino, clásico absoluto de sastrería |
| CR + MA | 0.85 | Crema + marino, náutico clásico |
| MA + RO | 0.80 | Marino + rojo, código preppy/náutico |
| MA + MO | 0.78 | Marino + mostaza, complementario azul/dorado amortiguado |
| CA + CE | 0.78 | Camel + celeste, contraste cálido/frío de baja tensión |
| MA + BU | 0.75 | Marino + burdeos, clásico de invierno |
| MA + RP | 0.75 | Marino + rosa palo, contraste suave consolidado |
| OL + BU | 0.75 | Oliva + burdeos, dupla otoñal |
| CH + CE | 0.75 | Chocolate + celeste, tierra + cielo |
| CH + CA | 0.82 | Monocromía marrón con salto de valor real (la clase L los separa solo 1 pero perceptivamente hay degradado) |
| CR + CE | 0.80 | Crema + celeste |
| VB + BU | 0.72 | Bosque + burdeos, riqueza otoñal |
| VB + MO | 0.72 | Bosque + mostaza |
| RY + MO | 0.68 | Royal + mostaza, complementario azul/oro (más tenso que con marino) |

## 2.4 Tabla completa de compatibilidad 20×20

Matriz simétrica generada aplicando R1–R7 + M1–M4 a los 190 pares únicos (se muestra el triángulo superior; la diagonal es el caso "mismo color repetido"). Media de la matriz: 0.76 — coherente con una paleta dominada por neutrales.

| | NE | BL | GC | GA | BE | CR | MA | RY | CE | OL | VB | VM | CH | CA | BU | RO | RP | MO | TE | LA |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **NE** | 0.80 | 0.90 | 0.90 | 0.75 | 0.90 | 0.85 | 0.75 | 0.90 | 0.85 | 0.85 | 0.85 | 0.85 | 0.85 | 0.85 | 0.85 | 0.90 | 0.85 | 0.85 | 0.85 | 0.85 |
| **BL** | · | 0.80 | 0.75 | 0.90 | 0.75 | 0.60 | 0.85 | 0.90 | 0.85 | 0.85 | 0.85 | 0.85 | 0.85 | 0.85 | 0.85 | 0.90 | 0.85 | 0.85 | 0.85 | 0.85 |
| **GC** | · | · | 0.80 | 0.90 | 0.75 | 0.85 | 0.85 | 0.85 | 0.75 | 0.85 | 0.85 | 0.75 | 0.85 | 0.85 | 0.85 | 0.85 | 0.75 | 0.85 | 0.85 | 0.85 |
| **GA** | · | · | · | 0.80 | 0.90 | 0.85 | 0.85 | 0.85 | 0.85 | 0.75 | 0.75 | 0.85 | 0.75 | 0.85 | 0.75 | 0.85 | 0.85 | 0.85 | 0.85 | 0.85 |
| **BE** | · | · | · | · | 0.80 | 0.85 | 0.80 | 0.80 | 0.70 | 0.85 | 0.80 | 0.70 | 0.85 | 0.85 | 0.85 | 0.85 | 0.70 | 0.85 | 0.85 | 0.80 |
| **CR** | · | · | · | · | · | 0.60 | 0.85 | 0.70 | 0.80 | 0.78 | 0.70 | 0.70 | 0.82 | 0.82 | 0.78 | 0.78 | 0.74 | 0.82 | 0.78 | 0.70 |
| **MA** | · | · | · | · | · | · | 0.60 | 0.82 | 0.82 | 0.70 | 0.70 | 0.78 | 0.70 | 0.85 | 0.75 | 0.80 | 0.75 | 0.78 | 0.70 | 0.78 |
| **RY** | · | · | · | · | · | · | · | 0.60 | 0.58 | 0.70 | 0.60 | 0.78 | 0.70 | 0.70 | 0.56 | 0.31 | 0.60 | 0.68 | 0.48 | 0.78 |
| **CE** | · | · | · | · | · | · | · | · | 0.60 | 0.70 | 0.78 | 0.78 | 0.75 | 0.78 | 0.56 | 0.64 | 0.62 | 0.64 | 0.64 | 0.78 |
| **OL** | · | · | · | · | · | · | · | · | · | 0.60 | 0.74 | 0.74 | 0.78 | 0.78 | 0.75 | 0.78 | 0.74 | 0.78 | 0.78 | 0.70 |
| **VB** | · | · | · | · | · | · | · | · | · | · | 0.60 | 0.82 | 0.70 | 0.70 | 0.72 | 0.56 | 0.60 | 0.72 | 0.56 | 0.60 |
| **VM** | · | · | · | · | · | · | · | · | · | · | · | 0.60 | 0.70 | 0.70 | 0.64 | 0.56 | 0.62 | 0.56 | 0.56 | 0.60 |
| **CH** | · | · | · | · | · | · | · | · | · | · | · | · | 0.60 | 0.82 | 0.78 | 0.70 | 0.74 | 0.70 | 0.70 | 0.70 |
| **CA** | · | · | · | · | · | · | · | · | · | · | · | · | · | 0.60 | 0.78 | 0.78 | 0.74 | 0.70 | 0.70 | 0.70 |
| **BU** | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 0.60 | 0.58 | 0.78 | 0.78 | 0.78 | 0.56 |
| **RO** | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 0.60 | 0.54 | 0.78 | 0.58 | 0.41 |
| **RP** | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 0.60 | 0.74 | 0.74 | 0.60 |
| **MO** | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 0.60 | 0.78 | 0.41 |
| **TE** | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 0.60 | 0.41 |
| **LA** | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | 0.60 |

## 2.5 Compatibilidad cromática de un outfit completo

Ni la media simple ni el mínimo puro son correctos. La media simple diluye un clash grave entre muchos pares buenos (un outfit con 9 pares a 0.85 y un par top-bottom a 0.31 saldría ≈0.80: falso). El mínimo puro es demasiado frágil: un accesorio pequeño mal combinado hundiría todo el outfit. Solución **[P]**: combinación lineal de media ponderada por importancia visual + mínimo, donde el peso de cada par refleja cuánta atención recibe esa frontera de colores.

**Pesos de pares por importancia visual** (el ojo evalúa sobre todo la unión top-bottom y la relación del outerwear con lo que cubre):

| Par | Peso `w` |
|---|---|
| top – bottom | 0.28 |
| outerwear – top | 0.16 |
| top – shoes | 0.14 |
| bottom – shoes | 0.14 |
| outerwear – bottom | 0.10 |
| accesorios – prenda dominante (repartido entre los accesorios presentes, máx. 3) | 0.06 |
| headwear – top | 0.05 |
| outerwear – shoes | 0.04 |
| headwear – outerwear | 0.03 |

Si una capa opcional no está presente, sus pares desaparecen y **los pesos restantes se renormalizan** para sumar 1.0.

**Fórmula:**

```
media_w  = Σ_pares w_par · comp(par)  /  Σ_pares w_par
S_color  = clamp( 0.70 · media_w + 0.30 · min_par(comp) − P_6030 , 0, 1 )
```

El término `0.30 · min` garantiza que un solo clash fuerte arrastre el score (un par a 0.31 resta ~0.15 aunque el resto sea perfecto), sin darle poder de veto absoluto.

## 2.6 Penalización 60-30-10 (`P_6030`)

Se penalizan dos violaciones de estructura, usando los roles y shares de §1.2:

```
n_prot  = nº de colores con S = 3 (vivos) y share ≥ 0.25     (protagonistas vivos)
P_prot  = min(0.25, 0.12 · max(0, n_prot − 1))
P_ancla = 0.08  si share(dominante) < 0.45, si no 0.00       (composición sin color ancla)
P_6030  = P_prot + P_ancla
```

Tres colores vivos de igual protagonismo (el caso del enunciado): `n_prot = 3 → P_prot = 0.24`, más probablemente `P_ancla = 0.08` → el outfit pierde ~0.32 de S_color: descartado en la práctica. Dos neutrales + un acento (estructura ideal): `P_6030 = 0`.

## 2.7 Prendas multicolor

**Representación:** lista ordenada por porcentaje de superficie, `colores = [(color, pct)]`, Σpct = 1.0; se ignoran colores con presencia < 10% (ruido de estampado). Camisa de cuadros azul y blanco: `[(MA, 0.55), (BL, 0.45)]`. El color en posición 0 es el "color de suelo" del estampado y representa a la prenda en reglas que exigen un único color.

**Compatibilidad entre dos prendas G₁, G₂ con listas (pᵢ, cᵢ) y (qⱼ, dⱼ):**

```
comp(G₁, G₂) = Σᵢ Σⱼ  pᵢ · qⱼ · M[cᵢ, dⱼ]
```

Es la esperanza de compatibilidad de la frontera visual entre ambas prendas: cada micro-contacto de color pondera según su superficie. Contra prenda lisa, la fórmula degenera en la media ponderada de una columna de la matriz.

**Principio de eco [P]** (desarrollado en §8.5): si un color con `pct ≥ 0.20` de una prenda multicolor coincide con el color dominante de otra prenda del outfit, ese par recibe **+0.05** (cap 0.95): repetir un color del estampado en otra prenda cohesiona.

---
# BLOQUE 3 — Análisis de color personal (Seasonal Color Analysis)

## 3.1 Elección de sistema y advertencia de rigor

Los tres candidatos: **4 estaciones** (Caygill 1980, popularizado por Jackson en *Color Me Beautiful*, 1980), **12 estaciones** (subdivide cada estación en 3 según la dimensión dominante) y **Sci\ART / True Colour** (12 tonos definidos por drapeado calibrado bajo iluminación controlada, base Munsell).

**Ninguno tiene validación empírica sólida [H]:** no hay estudios revisados por pares que demuestren consistencia inter-analista en la clasificación de personas, y la literatura crítica de los 80-90 señala baja concordancia. Lo que sí es ciencia **[T]** son las tres dimensiones subyacentes, que vienen directamente de Munsell: **temperatura** (subtono cálido/frío de la piel), **valor** (contraste natural piel-pelo-ojos) e **intensidad** (croma que la persona sostiene sin que el color la apague o la grite).

**Decisión: sistema de 4 estaciones.** Justificación de ingeniería: (a) el input es autoreportado en la app y la fiabilidad del autodiagnóstico cae en picado con 12 categorías; (b) 12 estaciones y Sci\ART requieren drapeado presencial calibrado, imposible aquí; (c) 4 categorías bastan porque el componente actúa como **bonus suave** (§3.3), no como veto; (d) es el dato que el sistema ya recibe. Sci\ART es el más riguroso *metodológicamente* (control de iluminación, neutralización del entorno), pero su rigor está en el protocolo de medida, no en evidencia superior de resultado — y sin el protocolo no aporta nada sobre 4 estaciones.

## 3.2 Los cuatro tipos y la tabla de 80 valores

| Tipo | Subtono piel | Contraste natural | Le potencia | Le daña y por qué |
|---|---|---|---|---|
| **Spring** (cálido·claro·brillante) | cálido, dorado/melocotón | medio-bajo, luminoso | cálidos claros y limpios: camel, crema, celeste, terracota clara, menta | negro y antracita (valor oscuro extremo que su rostro no tiene: proyecta sombra dura); apagados polvorientos (matan su luminosidad) |
| **Summer** (frío·claro·apagado) | frío, rosado/azulado | bajo-medio, suave | fríos empolvados: gris claro, celeste, lavanda, rosa palo, marino suave | mostaza/terracota/naranja (temperatura cálida contra subtono frío: amarillea la piel); negros y vivos saturados (aplastan su bajo contraste) |
| **Autumn** (cálido·oscuro·apagado) | cálido, dorado/oliváceo | medio, terroso | tierras profundas: oliva, mostaza, terracota, chocolate, camel, burdeos, bosque | blanco puro y negro (fríos y duros contra colorido cálido-apagado); pasteles fríos (lo lavan) |
| **Winter** (frío·oscuro·brillante) | frío, azulado | alto | máximo contraste y croma frío: negro, blanco puro, rojo verdadero, royal, burdeos | beige, crema, mostaza, terracota (cálidos apagados que ensucian su nitidez); pasteles empolvados (intensidad insuficiente para su contraste) |

**Tabla completa: score (0–1) de cada color por estación — 80 valores:**

| Código | Spring | Summer | Autumn | Winter |
|---|---|---|---|---|
| NE | 0.30 | 0.40 | 0.40 | 1.00 |
| BL | 0.50 | 0.60 | 0.40 | 1.00 |
| GC | 0.50 | 0.90 | 0.40 | 0.70 |
| GA | 0.40 | 0.60 | 0.50 | 0.90 |
| BE | 0.80 | 0.60 | 0.90 | 0.40 |
| CR | 0.90 | 0.50 | 0.90 | 0.30 |
| MA | 0.60 | 0.80 | 0.50 | 0.90 |
| RY | 0.70 | 0.60 | 0.40 | 0.90 |
| CE | 0.90 | 0.90 | 0.40 | 0.60 |
| OL | 0.50 | 0.30 | 1.00 | 0.30 |
| VB | 0.40 | 0.40 | 0.90 | 0.70 |
| VM | 0.90 | 0.70 | 0.30 | 0.50 |
| CH | 0.50 | 0.30 | 1.00 | 0.40 |
| CA | 0.80 | 0.40 | 1.00 | 0.30 |
| BU | 0.40 | 0.50 | 0.80 | 0.80 |
| RO | 0.70 | 0.40 | 0.60 | 0.90 |
| RP | 0.70 | 0.90 | 0.30 | 0.50 |
| MO | 0.70 | 0.20 | 1.00 | 0.30 |
| TE | 0.80 | 0.30 | 1.00 | 0.30 |
| LA | 0.50 | 0.90 | 0.20 | 0.70 |

**Justificación de los extremos.** `NE-Winter = 1.00` / `NE-Spring = 0.30`: el negro es el color-firma del alto contraste frío y el peor enemigo del rostro cálido-luminoso. `MO-Autumn = 1.00` / `MO-Summer = 0.20`: la mostaza concentra las tres propiedades Autumn (cálida, apagada, dorada) y las tres anti-Summer. `LA-Autumn = 0.20`: fría-empolvada, exactamente lo que ensucia una paleta terrosa. `OL/CH/CA/TE-Autumn = 1.00`: la definición de la paleta tierra. Ningún valor baja de 0.20 porque un color "malo" lejos de la cara es casi inocuo — y eso lo gestiona la ponderación de §3.3.

## 3.3 Integración en el scoring: bonus, no castigo

**Decisión: componente con peso 0.10 del score total, ponderado por cercanía a la cara.** Justificación: (a) el fundamento empírico del SCA es débil **[H]**; darle poder de veto expulsaría del armario prendas válidas por una teoría no validada; (b) el mecanismo óptico plausible del SCA es el reflejo de luz coloreada sobre la piel del rostro — un pantalón no refleja sobre la cara; (c) la armonía **entre prendas** (Bloque 2, peso 0.22) la percibe cualquier observador, mientras que la armonía prenda-persona es sutil: la relación 0.22 vs 0.10 codifica esa asimetría.

```
S_season = Σ_prendas_visibles  v_prenda · ( Σᵢ pctᵢ · seasonScore(cᵢ, estación_usuario) )
```

con pesos de cercanía a la cara `v` (renormalizados a las capas presentes): headwear 0.20, top 0.35, outerwear 0.25, bufanda 0.10, bottom 0.07, shoes 0.03. Un jersey mostaza en un Summer castiga; unos zapatos mostaza, casi nada. **Nunca hay descalificación por color season.**

---
# BLOQUE 4 — Formalidad y lectura de contexto

## 4.1 Los cinco niveles con ejemplos por categoría

| Nivel | Nombre | Top | Bottom | Shoes | Outerwear | Headwear | Accessories |
|---|---|---|---|---|---|---|---|
| 1 | Deportivo | camiseta técnica, tank top | pantalón de chándal, shorts running | zapatillas running, botas de fútbol | cortavientos técnico, sudadera cremallera deportiva | gorra deportiva, buff | reloj deportivo, mochila gym, muñequeras |
| 2 | Casual | camiseta algodón, sudadera gráfica | jeans lavados, shorts vaqueros, jogger urbano | zapatillas lifestyle, sandalias | bomber, denim jacket, hoodie | gorra plana, gorro lana | mochila urbana, pulsera tela, gafas deportivas |
| 3 | Smart casual | polo, camisa oxford informal, jersey fino | chino, jeans oscuros sin rotos | zapatillas blancas minimalistas, botas chelsea casual, mocasín informal | chaqueta de punto, overshirt, parka limpia | boina, gorra de lana estructurada | cinturón lona/cuero casual, reloj de correa, tote |
| 4 | Semiformal | camisa lisa planchada, jersey cuello alto fino | pantalón de vestir, chino planchado con raya | derbies, mocasines de cuero, chelsea pulidas | blazer, gabardina, abrigo de paño | sombrero panamá, fedora informal | cinturón de cuero liso, reloj de vestir, maletín |
| 5 | Formal | camisa de vestir blanca/celeste | pantalón de traje | oxford de cuero, zapato de cordones pulido | americana de traje, abrigo formal | (idealmente ninguno; fedora clásico tolerado) | cinturón cuero fino a juego con zapato, reloj clásico, gemelos |

## 4.2 Formalidad percibida del outfit: fórmula base + deltas

**Paso 1 — media ponderada de las capas grandes** (pesos por impacto visual en la lectura de formalidad; renormalizar a presentes):

```
con outerwear:  F_base = 0.25·F_outer + 0.30·F_top + 0.25·F_bottom + 0.20·F_shoes
sin outerwear:  F_base = 0.40·F_top + 0.33·F_bottom + 0.27·F_shoes
```

**Paso 2 — deltas de headwear y accesorios** (no entran en la media: modulan). `F_outfit = clamp(F_base + Σδ, 1, 5)`, con Σδ de accesorios limitado a ±0.5:

| Elemento | δ | Regla adicional |
|---|---|---|
| Gorra deportiva | −0.75 | además, **techo duro**: `F_outfit = min(F_outfit, 2.75)`. Respuesta directa al enunciado: una gorra deportiva en un outfit de formalidad 3 lo baja efectivamente a ~2.5: sí, lo degrada, y ningún resto del outfit lo compensa |
| Gorra plana / de moda | −0.50 | techo `min(F_outfit, 3.25)` |
| Gorro de lana | −0.25 | techo `min(F_outfit, 3.5)` |
| Fedora / panamá | +0.50 | **solo si** `F_base ≥ 3` (un fedora sobre chándal no sube nada: se lee como disfraz → δ = 0); techo 4.5 |
| Cinturón de cuero liso | +0.30 | |
| Cinturón de lona / trenzado casual | −0.10 | |
| Reloj de vestir (correa cuero/metal fino) | +0.30 | |
| Reloj deportivo (silicona, smartwatch con correa sport) | −0.10 | |
| Gafas de sol clásicas (aviador, wayfarer) | +0.00 | neutras |
| Collar / pulsera visible informal | −0.05 | |
| Mochila | −0.30 | solo aplica si `target ≥ 4` (en targets ≤3 la mochila es norma y δ = 0) |
| Maletín / bolso estructurado | +0.30 | |

**Regla de zapatillas ("normcore") — respuesta directa:** unas zapatillas blancas minimalistas (F_shoes = 3) con outfit smart casual (target 3) son **plenamente válidas**, y con target 4 son válidas con coste leve. La regla exacta se codifica como penalización por hueco de calzado, no como prohibición:

```
gap_shoes = target − F_shoes
si gap_shoes ≥ 2:            S_formalidad ×= 0.85    (zapatilla lifestyle con target 4)
si target = 5 y F_shoes ≤ 2: DESCALIFICACIÓN          (running con traje: fuera)
```

**Calcetines:** solo afectan si son visibles. Calcetín deportivo blanco visible con pantalón de vestir y target ≥ 4 → δ = −0.25. Calcetín deportivo con shorts y target ≤ 2 → δ = 0 (es su hábitat). Calcetín de vestir a tono con pantalón en target ≥ 4 → δ = +0.10. Invisible → δ = 0 siempre.

**Underwear:** δ = 0 sin excepción; no es observable. Único edge case real: prenda exterior blanca semitransparente → el sistema emite una **nota de recomendación** ("con esta camiseta, ropa interior blanca o nude"), sin efecto en el scoring.

## 4.3 Keywords de detección de formalidad en eventos (ES + EN)

Normalización previa: minúsculas, sin tildes, tokenización por palabras; se busca coincidencia de subcadena por token. Si un evento matchea varios grupos, gana el **máximo**. Sin match: default 3 en día laborable 08:00–18:00, default 2 el resto.

| Target | Keywords |
|---|---|
| **1 — Deportivo** | gym, gimnasio, entreno, entrenamiento, workout, training, deporte, sport, run, running, correr, futbol, football, soccer, basket, baloncesto, padel, tenis, tennis, crossfit, natacion, swim, yoga, pilates, senderismo, hike, ruta, bici, ciclismo, cycling, escalada, climbing, partido, match, caminata |
| **2 — Casual** | amigos, friends, cine, movie, pelicula, compras, shopping, paseo, walk, parque, park, quedada, hangout, plan, videojuegos, gaming, mercado, market, recados, errands, barbacoa, bbq, concierto, concert, festival, playa, beach, piscina, pool, brunch, cumple, cumpleaños, birthday |
| **3 — Smart casual** | clase, class, universidad, university, uni, facultad, campus, instituto, cafeteria, coffee, coworking, biblioteca, library, estudio, study, oficina, office, trabajo, work, taller, workshop, seminario, seminar, laboratorio, lab, tutoria, mentoring, hackathon, charla, talk, meetup, practicas, internship |
| **4 — Semiformal** | cita, date, reunion, meeting, cliente, client, cena, dinner, restaurante, restaurant, demo, networking, evento, event, teatro, theater, theatre, aniversario, anniversary, exposicion, exhibition, conferencia, conference, iglesia, church, misa, visita, kickoff, junta |
| **5 — Formal** | entrevista, interview, boda, wedding, funeral, tanatorio, presentacion, presentation, defensa, defense, tribunal, gala, ceremonia, ceremony, premios, awards, opera, banquete, banquet, comunion, bautizo, baptism, graduacion, graduation, juicio, court, notario, notary, firma, signing |

Ambigüedades resueltas por convención: `presentacion/presentation` → 5 solo si coocurre con {final, tfg, tesis, thesis, defensa, tribunal, cliente}; si no, 4. `graduacion` → 5 (propia) por defecto. `cena/dinner` → 4 por defecto, pero si coocurre con {amigos, casa, pizza, familia} → 2.

## 4.4 Múltiples eventos en el día: elección del target único

**Decisión: `target = max(formalidad de los eventos entre 07:00 y 22:00)`**, combinada con el disparador de doble outfit de §8.2.

Justificación frente a las alternativas: *el del evento más cercano* falla catastróficamente (vistes casual por el desayuno y llegas en chándal a la entrevista de las 17h); *el máximo sin ventana horaria* deja que una fiesta a la 1:00 dicte el día entero. El máximo dentro de la ventana de vigilia funciona porque el coste social es **asimétrico**: ir ligeramente sobrevestido a un plan casual es una anécdota, ir infravestido a una entrevista es un fallo de señalización costoso (la investigación en cognición del vestir — Adam & Galinsky 2012 — y en percepción de estatus por inconformidad — Bellezza, Gino & Keinan 2014 — muestra que vestir por encima del código es señal tolerada, mientras que por debajo solo funciona desde estatus ya establecido). El corte a las 22:00 refleja que el sistema recomienda **el outfit de la mañana**; eventos posteriores implican re-vestirse y salen del alcance de la sugerencia única.

## 4.5 Penalización por desajuste de formalidad

Gaussiana asimétrica sobre `Δ = F_outfit − target` (misma asimetría del §4.4: infravestir castiga más):

```
S_formalidad_base = exp( − Δ² / (2σ²) )      σ = 0.9 si Δ < 0 (infravestido)
                                             σ = 1.4 si Δ ≥ 0 (sobrevestido)
S_formalidad = S_formalidad_base × factor_gap_shoes (§4.2)
```

Valores de referencia: Δ = −1 → 0.54; Δ = +1 → 0.77; Δ = −2 → 0.08; Δ = +2 → 0.36; Δ = ±0.5 → 0.86 / 0.94. Un nivel entero de infravestido ya duele; dos niveles es prácticamente eliminatorio sin necesidad de regla dura.

---

# BLOQUE 5 — Clima y temperatura

## 5.1 De temperatura a warmth objetivo

Base fisiológica **[T]**: la zona termoneutral de un humano vestido con ~1 clo en reposo/actividad ligera está en torno a 20–24 °C (Fanger 1970; ISO 7730; ASHRAE 55). Cada unidad clo de aislamiento compensa aproximadamente 6–8 °C de descenso de temperatura operativa (ISO 9920). Nuestra escala `calor 1–5` mapea aproximadamente a 0.3 / 0.6 / 0.9 / 1.3 / 1.8 clo, de donde sale una pendiente de ≈5.5 °C por nivel de warmth.

**Paso 1 — temperatura de sensación `T_feel`:**

```
T_feel = tempC
viento:  si tempC ≤ 12 y windSpeedKmh > 10:   T_feel −= min(5, 0.10 · (windSpeedKmh − 10))
         (aproximación lineal del índice wind-chill de Osczevski & Bluestein 2005)
calor:   si tempC ≥ 26 y condición = sunny:    T_feel += 1   (carga radiante solar)
```

**Paso 2 — tabla T_feel → warmth objetivo `W*`** (fórmula continua equivalente: `W* = clamp(1 + (26 − T_feel)/5.5, 1, 5)`):

| T_feel (°C) | W* objetivo | Lectura |
|---|---|---|
| ≥ 28 | 1.0 | mínima ropa decente |
| 24 – 27.9 | 1.0 – 1.4 | verano estándar |
| 21 – 23.9 | 1.4 – 1.9 | entretiempo cálido |
| 18 – 20.9 | 1.9 – 2.5 | entretiempo |
| 15 – 17.9 | 2.5 – 3.0 | entretiempo fresco |
| 11 – 14.9 | 3.0 – 3.7 | fresco, primera capa de abrigo |
| 8 – 10.9 | 3.7 – 4.3 | frío moderado |
| 4 – 7.9 | 4.3 – 5.0 | frío |
| < 4 | 5.0 | frío intenso, todas las capas |

**Warmth del outfit** (media ponderada; el outerwear es el mayor contribuyente de aislamiento cuando existe):

```
con outerwear:  W_outfit = 0.45·w_outer + 0.25·w_top + 0.20·w_bottom + 0.10·w_shoes
sin outerwear:  W_outfit = 0.45·w_top + 0.35·w_bottom + 0.20·w_shoes
```

## 5.2 Condiciones especiales

**Lluvia** (condición `rainy` o `precipitationPct ≥ 50`). Quedan **excluidas** (descalificación, §7.2) las prendas cuya subcategoría o etiqueta de material pertenezca a: `sandalias`, `alpargatas`, `zapatillas de lona/tela` (etiqueta `lona`), calzado o chaqueta de `ante/gamuza`, y (exclusión blanda, −0.10 a S_meteo en vez de descalificar) pantalones de `lino`. Una prenda es válida bajo lluvia si su material no está en la lista negra o si porta etiqueta `impermeable` / `water_resistant` / `cuero_tratado` / `goma` / `membrana` (la etiqueta blanquea la subcategoría: una zapatilla de lona con membrana Gore-Tex es válida). Con `precipitationPct ≥ 70`, el outerwear con etiqueta `impermeable` o `capucha` recibe +0.15 en S_meteo.

**Viento > 30 km/h.** Si además `T_feel < 18 °C` → **outerwear obligatorio** (su ausencia descalifica) y las prendas con etiqueta `cortavientos` reciben +0.10 en S_meteo. Con T_feel ≥ 18 el viento solo aporta el descuento de T_feel del §5.1 (el cortavientos con 25 °C sobra).

**Sol intenso de verano** (`sunny` y tempC ≥ 27). Más allá del +1 °C en T_feel: la ropa oscura absorbe significativamente más radiación de onda corta que la clara — es física básica de albedo **[T]**; el estudio clásico de Shkolnik et al. (1980, *Nature*) matiza que con tejido holgado el efecto en carga térmica corporal se mitiga, así que la penalización es moderada y no un veto:

```
share_oscuro = fracción de superficie visible de torso (top+outer) con colores L ≤ 2
si share_oscuro ≥ 0.5:  S_meteo −= 0.30
headwear presente:       S_meteo += 0.20   (protección solar)
```

**Mañana fría + tarde calurosa (T_max − T_min > 10 °C).** Estrategia de doble restricción con capa removible: el outfit debe funcionar completo a T_min y sin outerwear a T_max.

```
W*_min = W*(T_feel(T_min))          W*_max = W*(T_feel(T_max))
S_térmico = min( S_térmico(W_outfit_completo, W*_min),
                 S_térmico(W_outfit_sin_outer, W*_max) )
```

Esto obliga al buscador a resolver con outerwear quitable (bomber, sudadera con cremallera, overshirt) en lugar de con un top muy caliente que no se puede quitar. Si ninguna combinación satisface ambas (p. ej. 4 °C → 18 °C), se prioriza la franja con eventos en agenda y se avisa: "por la tarde te sobrará la chaqueta".

## 5.3 Penalización por desajuste térmico

Gaussiana sobre `Δw = W_outfit − W*`, con asimetría estacional: pasar calor en verano es peor que el equivalente en frío (no puedes quitarte lo que no llevas, pero en invierno los interiores están climatizados):

```
S_térmico = exp( − Δw² / (2σ²) )     σ = 0.70 por defecto
                                     σ = 0.55 si tempC ≥ 26 y Δw > 0 (sobreabrigo en calor)
```

Valores de referencia (σ = 0.7): Δw = 0.5 → 0.77; Δw = 1.0 → 0.36; Δw = 1.5 → 0.10; |Δw| ≥ 2.5 → descalificación directa (§7.2) — ese outfit es objetivamente peligroso o absurdo para el día.

---
# BLOQUE 6 — Variedad, fatiga y stock

Advertencia de nivel de evidencia: la higiene textil tiene guías razonables **[P]** (frecuencia de lavado por contacto con piel y sudor) pero las "normas sociales de repetición" son heurística cultural **[H]**: no hay un umbral científico de cuántos días tarda alguien en notar que repites camiseta. Los valores siguientes son defaults sensatos y calibrables; el mecanismo (la fórmula de frescura) es lo importante.

## 6.1 Intervalos de repetición por categoría (`reuse_days = R`)

`R` = mínimo de días entre dos usos del mismo ítem **estando limpio**. La higiene (cuándo pasa a `sucia`) es un contador aparte: `usos_max_antes_de_lavar`.

| Categoría | R (días) | usos antes de lavar | Justificación |
|---|---|---|---|
| Camisetas, camisas, polos | 3 | 1 (camiseta) / 2 (camisa) | contacto directo con piel; socialmente es la prenda más "recordable" del outfit |
| Jerseys, sudaderas | 2 | 4–5 | van sobre otra capa; menor carga de higiene, repetición socialmente tolerada |
| Bottoms (pantalón, jeans, shorts) | 2 | 4–6 (jeans hasta 10) | los jeans son la prenda con mayor tolerancia cultural a la repetición |
| Outerwear | 1 | 15–20 | los abrigos son "uniforme": nadie espera que cambies de chaqueta a diario |
| Shoes | 1 | — | el motivo no es social sino material e higiénico: el calzado necesita ~24 h para secar la humedad interna (recomendación podológica estándar); rotar alarga su vida |
| Headwear moda | 1 | 10–15 | las gorras funcionan como "prenda firma": la repetición se lee como estilo, no como descuido |
| Headwear deportivo | 1 | 6 usos | absorbe sudor directo → contador de higiene agresivo (§6.6) |
| Accessories | 0 | — | relojes, cinturones y gafas se esperan repetidos |
| Socks | 0* | 1 | *cambio diario obligatorio: tras 1 uso pasan a `sucia` automáticamente |
| Underwear | 0* | 1 | *ídem |

## 6.2 Repetición del outfit completo

**Mismo conjunto exacto de prendas visibles: mínimo 10 días.** Racional **[H]**: la unidad que la memoria social registra no es la prenda sino la *combinación* ("el look de la camisa azul con los chinos"); dentro de una misma semana laboral la repetición exacta se nota, dos semanas después no. Implementación: si el conjunto de IDs visibles coincide con un outfit de `recentOutfits` con `days_ago < 10` → `S_frescura` se satura a 0.10 (no descalifica: si es lo único limpio, mejor repetir que nada, ver §8.1).

## 6.3 Función de frescura por prenda

```
freshness(N, R) = 0                              si N < R      (no disponible → descalifica)
                = 1 − e^( −(N − R + 1) / 3 )     si N ≥ R
freshness(nunca usada) = 1.0
```

donde N = días desde el último uso. Curva: en el primer día legal tras cumplir R la prenda vale 0.28 (usable pero castigada frente a alternativas), a los 3 días de margen 0.74, a los 7 días 0.93, asíntota 1.0. La constante de tiempo τ = 3 días controla cuánto premia el sistema "airear" el armario.

**Agregación en el componente del outfit** (pesos por visibilidad, renormalizados a presentes):

```
S_frescura_base = 0.30·f_top + 0.25·f_bottom + 0.20·f_shoes + 0.15·f_outer + 0.05·f_head + 0.05·f_acc
```

## 6.4 Penalización por combinación repetida (pares)

Para cada **par de prendas visibles** del outfit candidato que ya apareció junto en algún outfit de los últimos `X = 6` días: **−0.10** sobre S_frescura, acumulable hasta −0.30. Repite la lógica del §6.2 a escala de par: puedes reusar los chinos pronto, pero con otro top. Fórmula:

```
S_frescura = clamp( S_frescura_base − 0.10 · min(3, n_pares_repetidos_6d) , 0, 1 )
```

y con la saturación del §6.2 si el outfit entero es idéntico a uno de < 10 días.

## 6.5 Stock de prendas fungibles (underwear y socks)

**Modelo de datos:** los ítems individualmente indistinguibles comparten un `fungible_group_id` (mismo `categoria + subcategoria + etiqueta_equivalencia`, p. ej. "calcetín deportivo blanco", "bóxer básico"). El grupo expone: `total = nº ítems`, `limpias = nº con estado limpia`. Alternativa soportada: un único registro con campo `cantidad` y `cantidad_limpia` para multipacks idénticos — el sistema opera sobre el agregado del grupo en ambos casos.

**Reglas de umbral** (idénticas para underwear y socks):

| Estado del grupo | Acción |
|---|---|
| `limpias ≥ 3` | normal |
| `limpias = 2` | **alerta preventiva**: "quedan 2 bóxers limpios: pon lavadora hoy o mañana". La prenda se sigue incluyendo en la sugerencia (excluirla sería absurdo: hay stock) |
| `limpias = 1` | alerta urgente + se incluye en la sugerencia |
| `limpias = 0` | **bloqueo**: el sistema no puede componer sugerencia válida (el cambio diario es obligatorio) → mensaje crítico "sin ropa interior limpia; lavadora necesaria", y ofrece el resto del outfit marcando la capa faltante |

El día de alerta **no** se excluye la prenda de la sugerencia: la alerta es informativa; la exclusión solo ocurre en `limpias = 0` porque físicamente no hay unidad que sugerir.

## 6.6 Gorras: regla específica

R = 1 en ambos tipos (la gorra tolera repetición diaria como "prenda firma"), pero difieren en higiene: la **gorra deportiva** suma un contador de sudor — cada uso en contexto deportivo (target del día = 1) incrementa `usos_sudor`; a los 6 pasa automáticamente a `sucia` y se sugiere lavado. La **gorra de moda** usa el contador estándar (10–15 usos). Si la misma gorra física se usa en ambos contextos, manda el contador deportivo. Socialmente no se penaliza la repetición de gorra más allá de `freshness`: los accesorios de cabeza, como los relojes, están culturalmente exentos del estigma de repetición **[H]**.

---

# BLOQUE 7 — Función de scoring final

## 7.1 Composición del score

```
score(outfit, context) = D · Σᵢ wᵢ · Sᵢ
```

donde `D ∈ {0, 1}` es el producto de las condiciones de descalificación (§7.2) y los componentes son:

| Componente | Fórmula | Rango | Peso `w` |
|---|---|---|---|
| S_térmico | §5.3 (con doble restricción §5.2 si ΔT_día > 10) | [0,1] | **0.25** |
| S_formalidad | §4.5 sobre F_outfit de §4.2 | [0,1] | **0.25** |
| S_color | §2.5–2.6 (media ponderada + mínimo − P_6030) | [0,1] | **0.22** |
| S_frescura | §6.3–6.4 (con factor de saturación §8.3) | [0,1] | **0.13** |
| S_season | §3.3 | [0,1] | **0.10** |
| S_meteo | 1.0 base ± ajustes de §5.2 (sol/lluvia blanda/cortavientos), clamp [0,1] | [0,1] | **0.05** |
| | | **Σ** | **1.00** |

Racional de la jerarquía: térmico y formalidad empatan arriba porque son los dos fallos *objetivos* (pasar frío; desentonar en la entrevista); color es el corazón estético pero un outfit neutro "aburrido" bien abrigado es mejor sugerencia que uno espectacular con el que sudas; frescura es importante pero ya tiene descalificadores duros protegiendo la higiene; season y meteo-fino son refinamientos.

## 7.2 Descalificación directa (score = 0.0)

1. Outfit incompleto: falta bottom, top o shoes.
2. Cualquier prenda con `estado ∈ {sucia, lavadora}`.
3. Cualquier prenda con `freshness = 0` (N < R).
4. Lluvia activa (`rainy` o precip ≥ 50) con prenda de la lista negra de §5.2 sin etiqueta impermeabilizante.
5. `|W_outfit − W*| ≥ 2.5` (desajuste térmico absurdo).
6. Viento > 30 km/h con T_feel < 18 °C y sin outerwear (§5.2).
7. `target = 5` con `F_shoes ≤ 2` (§4.2).
8. Condición `snowy` con subcategoría `sandalias` o `alpargatas`.
9. Grupo fungible de socks o underwear con `limpias = 0` → no existe sugerencia completa válida (se degrada al flujo del §6.5).

## 7.3 Espacio de búsqueda y estrategia

**Tamaño realista.** Armario tipo de 78 prendas activas: 25 tops, 15 bottoms, 8 shoes, 8 outerwear, 5 headwear, 12 accesorios (+ fungibles). Núcleo obligatorio: 25×15×8 = **3 000** combinaciones. Con opcionales: ×(8+1) outerwear ×(5+1) headwear = 162 000; con accesorios C(12,0)+C(12,1)+C(12,2)+C(12,3) = 299 subconjuntos → **≈ 48.4 millones** de outfits totales. Fuerza bruta sobre el espacio completo: inviable en móvil con presupuesto de latencia < 1 s (y absurda: el 99% comparte núcleo malo).

**Estrategia elegida: filtrado duro → fuerza bruta del núcleo → beam search de capas → greedy de accesorios.** Justificación: el núcleo filtrado es tan pequeño que la búsqueda exacta es gratis; solo las capas opcionales necesitan poda.

```
Fase 0 — Filtrado duro por prenda (elimina antes de combinar):
         estado = limpia, freshness > 0, |calor − W*| ≤ 1.5,
         |formalidad − target| ≤ 1.5, válida para lluvia/nieve si aplica.
         Supervivencia típica ~40-50% → p.ej. 12 tops, 7 bottoms, 4 shoes.

Fase 1 — Núcleo exacto: score parcial de todas las ternas top×bottom×shoes
         supervivientes (≈ 12·7·4 = 336 evaluaciones; techo real < 5 000).

Fase 2 — Beam search: para las K = 25 mejores ternas, expandir con cada
         outerwear (+opción "sin") y headwear (+"sin") re-puntuando completo:
         25 · 9 · 6 = 1 350 evaluaciones. Mantener top-K global.

Fase 3 — Accesorios greedy: sobre cada finalista, añadir de uno en uno el
         accesorio con mayor ganancia marginal de score; parar cuando la
         ganancia ≤ 0 o al llegar a 3 accesorios. (Los accesorios son
         casi-independientes entre sí: el greedy es prácticamente óptimo aquí.)
```

Coste total: **~3 000–7 000 evaluaciones** de una función aritmética trivial → milisegundos en Swift, sin problema en un iPhone e incluso viable en watchOS.

## 7.4 Generación de 3 alternativas genuinamente distintas

Selección secuencial tipo *Maximal Marginal Relevance* con restricción estructural dura:

```
outfit₁ = argmax score
outfitₖ = argmax [ 0.70 · score(o) − 0.30 · max_{j<k} Jaccard_visible(o, outfitⱼ) ]
          sujeto a:  (a) Jaccard_visible(o, outfitⱼ) ≤ 0.5  ∀j < k
                     (b) o difiere de cada outfitⱼ en ≥ 2 slots de {top, bottom, shoes}
```

`Jaccard_visible` se calcula sobre los conjuntos de IDs de prendas visibles (los fungibles no cuentan). La restricción (b) es la que impide el caso "solo cambian los calcetines" o "misma base con otra gorra": las alternativas deben cambiar al menos dos de las tres prendas estructurales. λ = 0.70 mantiene la calidad: la alternativa 3 sigue siendo un buen outfit, no un outfit raro por ser distinto.

---

# BLOQUE 8 — CASOS ESPECIALES Y EDGE CASES

## 8.1 Armario casi vacío: score mínimo viable y relajación escalonada

**Score mínimo viable: 0.55.** Por debajo de ese valor el outfit "ganador" es objetivamente malo (típicamente implica dos componentes principales muy penalizados a la vez, p. ej. desajuste térmico Δw ≈ 1.5 **y** desajuste de formalidad Δf ≈ 1.5). Antes de mostrar un outfit < 0.55, el sistema ejecuta una **relajación escalonada de restricciones**, en este orden fijo:

| Paso | Restricción que se relaja | Cómo se relaja | Qué NO se toca nunca |
|---|---|---|---|
| 0 | — (estado normal) | — | — |
| 1 | **Frescura de variedad** | Se ignora `freshness < 1` para tops/bottoms/shoes/outer: una prenda usada ayer vuelve a ser candidata con freshness forzada a 0.60. La penalización de pares repetidos se reduce a la mitad. | La higiene: socks/underwear usados y cualquier prenda `sucia`/`en lavadora` siguen excluidos. |
| 2 | **Color season** | `S_season` se fija a 0.50 neutro para todos los candidatos (deja de discriminar). | — |
| 3 | **Tolerancia de formalidad** | El filtro duro de Fase 0 pasa de ±1.5 a ±2.5 respecto al target; la penalización gaussiana se mantiene (el desajuste sigue costando score, pero ya no elimina candidatos). | El descalificador *target 5 + zapatillas F ≤ 2* se mantiene. |
| 4 | **Rendición informativa** | Se muestra el mejor outfit disponible marcado como "bajo mínimos" + mensaje accionable: cuántas prendas hay en `sucia`/`en lavadora` y qué categoría es el cuello de botella ("Tienes 0 pantalones limpios compatibles con lluvia. Pon una lavadora o el sistema no puede ayudarte."). | — |

**Restricciones inviolables en cualquier paso** (son de seguridad/física, no de estética):
1. Higiene: nada sucio, en lavadora, ni socks/underwear reutilizados.
2. Lluvia dura: la lista negra de calzado/tejido del §5.2 no se relaja jamás con `precipitationPct ≥ 70`.
3. Térmico extremo: `|Δw| ≥ 2.5` sigue descalificando (salir a −2 °C en camiseta no es una opción estética, es un riesgo).

El orden 1→2→3 no es arbitrario: se relaja primero lo que solo afecta a la *percepción social leve* (repetir ropa [H]), después lo *puramente estético personal* (season), y solo al final lo que tiene *coste social real* (formalidad, cf. §4.6). Lo fisiológico no se negocia.

## 8.2 Eventos de contextos muy distintos el mismo día (gym 08:00 + cena 20:00)

La política de "máximo del día" del §4.5 tiene una excepción cuando el día es **bimodal**. Regla de activación del **doble outfit**:

```
Sea E = lista de eventos del día con (target_i, hora_i), 07:00–22:00.
Activar sugerencia doble si y solo si:
  (a) max(target) − min(target) ≥ 2        (brecha de formalidad real)
  (b) existe hueco ≥ 90 min entre el fin estimado del evento de menor
      formalidad y el inicio del de mayor formalidad (tiempo de volver
      a casa y cambiarse; si el calendario no da duración, asumir 60 min
      de duración por defecto)
  (c) ambos eventos son "vestibles": target ≥ 1 (siempre cierto)
```

- Si (a) y (b) se cumplen → **dos outfits con etiqueta horaria**: `Outfit A (hasta ~18:30): target = formalidad del bloque matinal` y `Outfit B (desde 19:00): target = formalidad del bloque vespertino`. Cada uno se optimiza de forma independiente con su propio target; las prendas del outfit A quedan marcadas como usadas para el B (no se puede repetir la camiseta sudada del gym en la cena — el contador de higiene del §6.1 se aplica entre outfits del mismo día).
- Si (a) se cumple pero (b) **no** (no hay hueco para cambiarse) → outfit único de **transición al máximo**: target = max(targets), y se añade una nota: "No hay tiempo de cambio entre eventos; vas con el nivel del evento más exigente".
- Si (a) no se cumple (brecha ≤ 1) → política normal del §4.5 (máximo del día), la gaussiana asimétrica ya absorbe bien una diferencia de 1 nivel.

El umbral de brecha = 2 es deliberado: una brecha de 1 (clase → cita informal) se cubre con un solo outfit de nivel 3 sin que nadie lo note; una brecha de 2+ (gym → cena semiformal) no la cubre ninguna prenda existente — no hay ropa que sea a la vez 1 y 4.

## 8.3 Prenda favorita dominante: saturación de uso sin destruir la calidad

Problema: una prenda objetivamente buena (p. ej. una chaqueta MA de formalidad 3, calor 3) gana el scoring casi todos los días, el usuario la ve siempre y el sistema parece "roto". La frescura del §6.3 ya ayuda (reuse_days), pero con R=1 en outerwear una chaqueta puede aparecer día sí, día no, indefinidamente.

**Mecanismo: factor de saturación de uso a 14 días**, aplicado multiplicativamente a la freshness **individual** de la prenda (no al outfit):

```
saturación(item) = max( 0.70 , 1 − 0.08 · max(0, usos_14d(item) − 3) )

freshness_efectiva(item) = freshness(N, R) · saturación(item)
```

donde `usos_14d` = número de días distintos en que la prenda apareció en el outfit confirmado durante los últimos 14 días.

Comportamiento: los 3 primeros usos en 14 días son gratis (uso normal de una prenda querida); a partir del 4.º uso, cada aparición extra cuesta −8 % de frescura efectiva, con suelo en 0.70. La prenda favorita **nunca queda excluida** (esto es clave: el usuario la ama por algo), solo pierde ventaja competitiva gradualmente, dándole a la segunda mejor chaqueta la oportunidad de ganar 2–3 días por quincena. Combinado con el MMR del §7.4 (que ya diversifica las 3 alternativas mostradas), el efecto percibido es "rotación natural", no "me han escondido mi chaqueta".

Se elige suelo 0.70 y no menor porque el peso de S_frescura es 0.13: el castigo máximo total sobre el score final es ≈ 0.13 · 0.15 · 0.30 ≈ 0.006 por la vía del outfit — suficiente para desempatar, imposible que fuerce un outfit peor en térmico/formalidad. La diversidad forzada **desempata, no manda**.

## 8.4 Armario monocromático (todo negro/blanco/gris): ¿colapsa el scoring cromático?

No colapsa, y la razón está en la propia matriz del Bloque 2:

- Todos los pares entre {NE, BL, GC, GA} valen **0.75–0.90** (regla R1): el subespacio acromático es una zona de score cromático *alto y estable*.
- El driver de calidad pasa a ser automáticamente el **contraste de valor** vía el ajuste −0.15 cuando ΔL < 2: `NE+GA` (ΔL=1) puntúa 0.75 mientras `NE+BL` (ΔL=4) puntúa 0.90 y `NE+GC` (ΔL=3) 0.90. El sistema, sin ninguna regla especial, prefiere *negro con blanco/gris claro* a *negro con gris marengo* — exactamente lo que haría un estilista con un armario monocromo [P].
- `S_season` tampoco degenera: NE y BL discriminan fuerte por season (Winter 1.00 vs Spring 0.30), GC/GA son planos (~0.60–0.75). Un Winter con armario monocromo puntúa alto; un Autumn recibirá S_season mediocre — señal honesta de que ese armario no le favorece, no un bug.
- La penalización 60-30-10 rara vez se activa (los ABS no cuentan como "protagonistas vivos"), y el suelo global 0.30 de la matriz garantiza que ningún par acromático descalifique nada.

Único ajuste necesario: **ninguno**. Es una propiedad emergente deseable del diseño; se documenta como caso de test de regresión para el ingeniero (outfit NE/NE/NE debe puntuar S_color ≈ 0.60–0.66 por la diagonal 0.80 con ΔL=0 → señal de "válido pero plano", no de error).

## 8.5 Prenda multicolor como puente cromático

Una camisa de cuadros MA+BL (60/40) contiene *internamente* un par de alta compatibilidad, y además **legitima terceros colores** que combinan con cualquiera de sus componentes. El mecanismo formal es el **principio de eco** ya definido en §2.6, que aquí se completa:

```
Para cada color c del outfit que NO pertenece a la prenda multicolor P:
  comp_puente(c, P) = Σ_d  pct_d · M[c, d]        (d recorre los colores de P, pct ≥ 10 %)

Bonus de eco: si algún color d de P (pct_d ≥ 20 %) aparece también en OTRA
prenda del outfit → S_color += 0.05 (una sola vez, cap global 0.95).
```

Ejemplo completo: camisa cuadros MA(0.6)+BL(0.4), pantalón CA (camel), zapatillas BL.
- Par camisa–pantalón: 0.6·M[MA,CA] + 0.4·M[BL,CA] = 0.6·0.85 + 0.4·0.85 = **0.85** — el camel entra "justificado" por el marino (excepción editorial navy+camel) *a través* de la prenda puente.
- Las zapatillas BL **ecoan** el blanco de los cuadros (pct 40 % ≥ 20 %) → +0.05.
- Resultado: un tercer color (CA) que junto a BL solo daría 0.85 y junto a un outfit MA liso daría lo mismo, aquí produce un conjunto cohesionado con score cromático ≈ 0.88–0.90. La prenda multicolor **sí actúa de puente**, y lo hace sin ninguna regla ad-hoc: emerge de la representación por porcentajes (§2.6) + eco.

Límite anti-abuso: una prenda con 4+ colores ≥ 10 % (estampado muy loud) no da eco múltiple — el bonus es +0.05 total, no por color ecoado. Y sigue contando como "protagonista vivo" en la regla 60-30-10 si alguno de sus colores es S=3, así que un estampado multicolor + otro color vivo activa P_6030 normalmente.

## 8.6 Socks y underwear sin foto ni color definido

Tratamiento en tres planos, coherente con todo lo anterior:

| Plano | Regla |
|---|---|
| **Scoring visual** (S_color, S_season, S_formalidad, S_meteo) | **Excluidos por completo.** No aparecen en ningún par cromático, no reciben peso de formalidad (§4.2: δ=0 salvo calcetín visible), no computan en W_outfit (su aporte térmico es ~0.03 clo, despreciable [T]). |
| **Sugerencia final** | **Incluidos siempre.** El outfit mostrado lista "+ calcetines (7 limpios) + ropa interior (4 limpias)" tomando cualquier unidad limpia del grupo fungible (§6.5). Si un calcetín tiene color definido Y será visible (shorts / pantalón tobillero), se promociona a acento con peso 0.05 en S_color y aplica el δ de formalidad del §4.2. |
| **Stock e higiene** | **Rastreados al 100 %:** contador de fungibles, umbrales 3/2/1/0 del §6.5, paso automático a `sucia` tras 1 uso, y participación en el descalificador de bloqueo (limpias = 0). |

Regla de datos para el ingeniero: `color: null` es un valor válido en el modelo de prenda **solo** para las categorías socks/underwear; en cualquier otra categoría, una prenda sin color no puede entrar al catálogo activo (el scoring cromático la necesita).

---

# APÉNDICE A — TABLA CONSOLIDADA DE CONSTANTES DE CALIBRACIÓN

Todas las constantes ajustables del sistema en un solo lugar. El ingeniero debe implementarlas como configuración central (un único fichero/struct), nunca como literales dispersos. La columna "Sensibilidad" indica cuánto cuidado exige recalibrarla: ★ = cosmética, ★★ = afecta al ranking, ★★★ = afecta a descalificaciones (tocar con tests).

## A.1 Matriz cromática (Bloque 2)

| Constante | Valor | Sensibilidad |
|---|---|---|
| Score ABS+ABS (R1) | 0.90 | ★★ |
| Ajuste bajo contraste ΔL<2 entre ABS | −0.15 | ★★ |
| Score ABS+cromático base (R2) | 0.85 | ★★ |
| Monocromía misma familia, ΔL≥2 / ΔL<2 | 0.82 / 0.58 | ★★ |
| Análogos (Δh ≤ 75°) | 0.78 | ★★ |
| Discordantes (75° < Δh < 150°) base / con neutral suave | 0.45 / +0.15 | ★★ |
| Complementarios (Δh ≥ 150°) ΔS≥2 / ambos S=3 | 0.68 / 0.52 | ★★ |
| M1: cruce temperatura W↔C | −0.04 | ★ |
| M2: dos vivos S=3 juntos | −0.10 | ★★ |
| M3: suelo par con pastel (L≥4, S≤2) | 0.62 | ★ |
| M4: suelo neutral suave + cromático | 0.70 | ★ |
| Diagonal ABS / diagonal cromáticos | 0.80 / 0.60 | ★ |
| Clamp global de la matriz | [0.30, 0.95] | ★★★ |
| Excepciones editoriales | 15 pares, tabla §2.4 | ★ |

## A.2 Score cromático de outfit (Bloque 2)

| Constante | Valor | Sensibilidad |
|---|---|---|
| Mezcla media ponderada / mínimo | 0.70 / 0.30 | ★★ |
| Peso par top–bottom | 0.28 | ★★ |
| Peso par outer–top | 0.16 | ★★ |
| Peso par top–shoes | 0.14 | ★★ |
| Peso par bottom–shoes | 0.14 | ★★ |
| Peso par outer–bottom | 0.10 | ★ |
| Peso par accesorio–dominante | 0.06 | ★ |
| Peso par head–top | 0.05 | ★ |
| Peso par outer–shoes | 0.04 | ★ |
| Peso par head–outer | 0.03 | ★ |
| P_6030: coste por protagonista vivo extra | 0.12·max(0, n_prot−1), cap 0.25 | ★★ |
| P_6030: recargo dominante débil (share < 0.45) | +0.08 | ★ |
| Umbral de color relevante en prenda multicolor | pct ≥ 10 % | ★★ |
| Bonus de eco (color repetido, pct ≥ 20 %) | +0.05, cap S_color 0.95 | ★ |

## A.3 Color season (Bloque 3)

| Constante | Valor | Sensibilidad |
|---|---|---|
| Peso de cercanía a la cara: top | 0.35 | ★★ |
| outer / head / bufanda | 0.25 / 0.20 / 0.10 | ★★ |
| bottom / shoes | 0.07 / 0.03 | ★ |
| S_season neutro en relajación (paso 2 de §8.1) | 0.50 | ★ |
| Tabla 20×4 season | §3.3 | ★★ |

## A.4 Formalidad (Bloque 4)

| Constante | Valor | Sensibilidad |
|---|---|---|
| Pesos F_base con outer (top/bottom/shoes/outer) | 0.25/0.30/0.25/0.20 | ★★ |
| Pesos F_base sin outer (top/bottom/shoes) | 0.40/0.33/0.27 | ★★ |
| δ gorra deportiva / techo | −0.75 / techo 2.75 | ★★ |
| δ gorra de moda / techo | −0.50 / techo 3.25 | ★★ |
| δ gorro de lana | −0.25 | ★ |
| δ fedora (solo si F_base ≥ 3) / techo | +0.50 / techo 4.5 | ★ |
| δ cinturón cuero / reloj vestir / maletín | +0.30 c/u | ★ |
| δ reloj deportivo / mochila (si target ≥ 4) | −0.10 / −0.30 | ★ |
| Cap suma δ accesorios | ±0.50 | ★★ |
| δ calcetines visibles (traje con short / deportivo blanco con chino) | +0.10 / −0.25 | ★ |
| Multiplicador zapatillas con gap ≥ 2 | ×0.85 | ★★ |
| σ_under (infravestido) / σ_over (sobrevestido) | 0.9 / 1.4 | ★★ |
| Política multi-evento | max(targets 07–22 h) | ★★ |

## A.5 Clima (Bloque 5)

| Constante | Valor | Sensibilidad |
|---|---|---|
| Amplitud térmica por nivel de warmth | 5.5 °C | ★★★ |
| Fórmula W* | clamp(1 + (26 − T_feel)/5.5, 1, 5) | ★★★ |
| Wind chill: umbral / fórmula | T ≤ 12 °C y v > 10 km/h → −min(5, 0.10·(v−10)) | ★★ |
| Recargo sol | +1 °C si sunny y T ≥ 26 | ★ |
| Pesos W_outfit con outer (outer/top/bottom/shoes) | 0.45/0.25/0.20/0.10 | ★★ |
| Pesos W_outfit sin outer (top/bottom/shoes) | 0.45/0.35/0.20 | ★★ |
| Bonus impermeable con precip ≥ 70 % | +0.15 en S_meteo | ★ |
| Penalización lino en lluvia blanda | −0.10 | ★ |
| Viento fuerte: umbral outer obligatorio | v > 30 km/h y T_feel < 18 °C | ★★★ |
| Bonus cortavientos en viento fuerte | +0.10 | ★ |
| Sol intenso: umbral share torso oscuro (L ≤ 2) | ≥ 0.50 → S_meteo −0.30 | ★★ |
| Bonus headwear con sol intenso | +0.20 en S_meteo | ★ |
| σ térmico general / en calor con Δw>0 | 0.70 / 0.55 | ★★ |
| Descalificador térmico | \|Δw\| ≥ 2.5 | ★★★ |
| Amplitud diaria para doble restricción | ΔT > 10 °C → min(dos escenarios §5.5) | ★★ |

## A.6 Frescura y stock (Bloque 6)

| Constante | Valor | Sensibilidad |
|---|---|---|
| reuse_days: tops / jerseys / bottoms | 3 / 2 / 2 | ★★ |
| reuse_days: outer / shoes / gorra (ambas) | 1 / 1 / 1 | ★★ |
| reuse_days: accesorios / socks / underwear | 0 / 0* / 0* (paso a sucia tras 1 uso) | ★★★ |
| Contador de sudor gorra deportiva | lavado sugerido cada 6 usos | ★ |
| Repetición outfit idéntico | < 10 días → S_frescura = 0.10 | ★★ |
| τ de la curva de frescura | 3 días | ★★ |
| Pesos S_frescura (top/bottom/shoes/outer/head/acc) | 0.30/0.25/0.20/0.15/0.05/0.05 | ★ |
| Penalización par repetido < 6 días | −0.10 c/u, cap −0.30 | ★★ |
| Umbrales stock fungible (normal/alerta/urgente/bloqueo) | ≥3 / 2 / 1 / 0 | ★★★ |
| Factor saturación favorita (§8.3) | max(0.70, 1 − 0.08·max(0, usos_14d − 3)) | ★★ |

## A.7 Scoring final y búsqueda (Bloques 7–8)

| Constante | Valor | Sensibilidad |
|---|---|---|
| w_térmico / w_formalidad / w_color | 0.25 / 0.25 / 0.22 | ★★★ |
| w_frescura / w_season / w_meteo | 0.13 / 0.10 / 0.05 | ★★ |
| Filtro Fase 0: tolerancia calor / formalidad | ±1.5 / ±1.5 | ★★★ |
| Beam width K (Fase 2) | 25 | ★ |
| Máx. accesorios (Fase 3 greedy) | 3, parar si ganancia ≤ 0 | ★ |
| MMR: λ / Jaccard máx / slots estructurales distintos | 0.70 / 0.5 / ≥ 2 de {top,bottom,shoes} | ★★ |
| Score mínimo viable | 0.55 | ★★ |
| Orden de relajación | frescura → season → formalidad ±2.5 | ★★★ |
| Doble outfit: brecha de targets / hueco mínimo | ≥ 2 niveles / ≥ 90 min | ★★ |
| Duración por defecto de evento sin fin | 60 min | ★ |

---

# REFERENCIAS

**Teoría del color y armonía**

- Itten, J. (1961). *Kunst der Farbe* (El arte del color). Base de la rueda de 12 tonos, contrastes y esquemas análogos/complementarios usados en R3–R6.
- Munsell, A. H. (1905/1929). *A Color Notation*. Sistema tono–valor–croma; origen de las dimensiones L (valor) y S (croma) del §0.
- Ou, L.-C., & Luo, M. R. (2006). "A colour harmony model for two-colour combinations". *Color Research & Application*, 31(3), 191–204. Evidencia empírica de que la armonía percibida crece con la diferencia de valor (ΔL) y decrece con dos cromas altos juntos — justifica el ajuste −0.15 de R1, el 0.52 de complementarios saturados y M2.
- Palmer, S. E., & Schloss, K. B. (2010). "An ecological valence theory of human color preference". *PNAS*, 107(19), 8877–8882. Las preferencias cromáticas son contextuales y aprendidas — justifica la capa de excepciones editoriales [P] sobre la geometría pura [T].
- Regla 60-30-10: heurística estándar de diseño de interiores y estilismo, sin paper fundacional (marca [H]/[P] en §2.5).

**Análisis de color personal**

- Caygill, S. (1980). *Color: The Essence of You*. Origen del sistema de 4 estaciones.
- Jackson, C. (1980). *Color Me Beautiful*. Popularización del sistema de 4 estaciones usado en el Bloque 3.
- Nota de rigor: el *seasonal color analysis* carece de validación empírica revisada por pares (no hay estudios controlados que demuestren efectos robustos inter-observador). Se integra con peso bajo (0.10) y solo como bonus, nunca como descalificador, precisamente por esa debilidad [H] (§3.4).

**Termofisiología del vestir**

- Fanger, P. O. (1970). *Thermal Comfort: Analysis and Applications in Environmental Engineering*. Modelo PMV; base conceptual del mapeo temperatura→warmth.
- ISO 7730:2005. *Ergonomics of the thermal environment — PMV/PPD*. Estandarización del confort térmico.
- ISO 9920:2007. *Estimation of thermal insulation of a clothing ensemble* (unidad clo). Justifica los ~5.5 °C por nivel de warmth y los pesos de W_outfit (§5.1, §5.3).
- ASHRAE Standard 55. *Thermal Environmental Conditions for Human Occupancy*. Zona de confort y efecto de humedad/velocidad del aire.
- Osczevski, R., & Bluestein, M. (2005). "The New Wind Chill Equivalent Temperature Chart". *Bulletin of the American Meteorological Society*, 86(10), 1453–1458. Base del ajuste de sensación por viento (§5.1, simplificado linealmente).
- Shkolnik, A., Taylor, C. R., Finch, V., & Borut, A. (1980). "Why do Bedouins wear black robes in hot deserts?". *Nature*, 283, 373–374. El color oscuro absorbe más radiación pero el efecto sobre el confort depende de la ventilación de la prenda — justifica que la penalización por torso oscuro al sol sea moderada (−0.30 en S_meteo, peso 0.05) y no un descalificador (§5.2).

**Psicología social del vestuario**

- Adam, H., & Galinsky, A. D. (2012). "Enclothed cognition". *Journal of Experimental Social Psychology*, 48(4), 918–925. La ropa afecta al rendimiento y autopercepción — apoya priorizar el evento más exigente (§4.5).
- Bellezza, S., Gino, F., & Keinan, A. (2014). "The Red Sneakers Effect". *Journal of Consumer Research*, 41(1), 35–54. La desviación deliberada del código (zapatillas en contexto smart) puede leerse como estatus — justifica que zapatillas con gap 2 penalicen (×0.85) pero no descalifiquen salvo en target 5 (§4.4).
- La asimetría de coste social infra/sobre-vestido (σ_under 0.9 < σ_over 1.4, §4.6) se apoya en la lectura conjunta de ambos: ir por debajo del código señala descuido; ir por encima se tolera o incluso premia.

**Marcas de evidencia usadas en el documento:** [T] = teoría formal / norma técnica; [P] = práctica profesional consolidada del estilismo; [H] = heurística razonable sin respaldo empírico fuerte, marcada como tal deliberadamente.

*Fin del documento.*
