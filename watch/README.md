# RepCounter — contador de repeticiones para Apple Watch

App de watchOS que cuenta repeticiones por el movimiento de la muñeca y las
registra en tu Life Hub. Cuenta con `CoreMotion`, mantiene el reloj despierto
con una sesión de HealthKit y manda cada serie a la API.

Funciona sin conexión: si el reloj no llega al servidor, guarda las series y
las sincroniza al terminar.

## Cómo detecta las repeticiones

El detector (`RepDetector.swift`) no cuenta picos de aceleración a lo bruto,
porque eso falla en cuanto el ejercicio cambia de plano:

1. **PCA** sobre la ventana de señal para encontrar el eje real del movimiento,
   sea cual sea la orientación de la muñeca.
2. **Filtro paso banda** en ese eje, para quedarse con la cadencia del ejercicio
   y descartar tanto la deriva lenta como el ruido.
3. **Conteo en el extremo** del recorrido, no en el cruce por cero: así una
   repetición a medias no suma.
4. **Calibración por ejercicio**, que aprende de tus correcciones (+/−) y se
   guarda por nombre de ejercicio.

Para ejercicios donde la muñeca casi no se mueve (prensa, extensiones) hay un
modo de conteo por toque.

## Endpoints que usa

- `GET  /api/gym/device/today` → rutina de hoy y ejercicios, con peso recomendado
- `POST /api/gym/device/set` → registra una serie `{exercise_id, weight, reps}`

Ambos van autenticados con la cabecera `X-Device-Token`, que es el
`GYM_DEVICE_TOKEN` del `.env` del servidor. Es un token aparte de la clave
principal a propósito: solo sirve para estos endpoints, así que si el reloj se
pierde el alcance es limitado.

Para marcar hábitos y comidas usa los endpoints normales con `APP_PASSWORD`.

## Requisitos

- Mac con Xcode 15 o superior
- iPhone y Apple Watch emparejados, ambos en Modo desarrollador
- Una cuenta de Apple Developer (la gratuita vale; la firma caduca a los 7 días)

## Compilar

```bash
brew install xcodegen     # si no lo tienes
cd watch
xcodegen generate
open RepCounter.xcodeproj
```

Antes de compilar, cambia `bundleIdPrefix` en `project.yml` por el tuyo. En
Signing & Capabilities elige tu Team; el proyecto no lleva ninguno fijado.

Elige tu Apple Watch como destino y dale a Run.

## Configurar

No hay credenciales en el código. Al abrir la app por primera vez el reloj no
sabe a qué servidor hablar, y hay dos formas de decírselo:

- **Desde el iPhone** (recomendado): en la app de Life Hub, Ajustes → Reloj,
  pega el `GYM_DEVICE_TOKEN` y pulsa "Enviar al reloj". Va por
  WatchConnectivity y no hay que escribir nada en la pantalla pequeña.
- **En el propio reloj**: última pestaña (Ajustes), rellenando URL, token y
  clave a mano.

## Pestañas

Se navega deslizando en vertical:

1. **Gym** — entreno en curso, series y repeticiones
2. **Rutinas** — marcar hábitos del día
3. **Comida** — marcar comidas
4. **Sueño** — alarma inteligente por ciclos
5. **Ajustes** — configuración del servidor
