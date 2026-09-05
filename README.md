# Life Hub

Un panel personal autoalojado: hábitos, gimnasio, nutrición, sueño, tareas,
finanzas, correo y agenda en un solo sitio. Backend en FastAPI, PWA en React y
apps nativas de iOS y watchOS.

Cada quien despliega su propia instancia: los datos se quedan en tu servidor.

## Qué incluye

| Módulo | Qué hace |
|---|---|
| **Hábitos** | Rutinas por horario o cada N días, con rachas e historial |
| **Gimnasio** | Rutinas, registro de series y recomendación de peso por doble progresión |
| **Nutrición** | Recetario propio, plan semanal, macros y lista de la compra automática |
| **Sueño** | Ciclos, deuda de sueño y hora de dormir recomendada (Apple Salud) |
| **Progreso** | Peso, medidas corporales, fotos y récords personales |
| **Tareas** | Pendientes sueltos con fecha, y notas rápidas |
| **Finanzas** | Cartera de Alpaca y Bitvavo *(opcional)* |
| **Correo y agenda** | Gmail y calendario de iCloud *(opcional)* |
| **Estudios** | La IA revisa el repo de tu proyecto y te dice cómo vas *(opcional)* |
| **Armario** | Prendas, uso y sugerencia de outfit según el tiempo *(opcional)* |

Todos los módulos opcionales se apagan solos si no los configuras.

### Contador de repeticiones en el Apple Watch

La app de watchOS cuenta las repeticiones sola con el acelerómetro y el
giroscopio: PCA sobre la señal más un filtro paso banda, con la calibración por
ejercicio aprendida de tus correcciones. Funciona sin conexión y sincroniza el
entreno al terminar.

## Requisitos

- Python 3.11+
- Node 20+
- Un servidor donde alojarlo (basta un VPS pequeño)
- Xcode 15+ y una cuenta de Apple Developer, solo si quieres las apps nativas

## Puesta en marcha

### Backend

```bash
cd backend
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt

cp .env.example .env
python -c "import secrets; print(secrets.token_urlsafe(32))"   # para APP_PASSWORD
# edita .env y pega la clave

uvicorn app.main:app --reload
```

La base de datos SQLite se crea sola al arrancar, con un catálogo de ejercicios
y un recetario de ejemplo que puedes borrar entero.

### Frontend

```bash
cd frontend
npm install
npm run dev
```

En producción, `npm run build` y sirve `dist/` detrás del backend.

> **Sirve la app por HTTPS.** La clave de la API viaja en cada petición: sobre
> HTTP plano va en claro. Un proxy con Caddy o Nginx y un certificado de Let's
> Encrypt es suficiente.

### iOS y watchOS *(opcional)*

```bash
cd ios
xcodegen generate      # brew install xcodegen
open LifeHub.xcodeproj
```

Antes de compilar, cambia en `ios/project.yml` y en los `.entitlements`:

- `bundleIdPrefix` y los `PRODUCT_BUNDLE_IDENTIFIER`, por los tuyos
- el App Group `group.com.example.lifehub` (también en `AppConfig.swift`)

Al abrir la app te pedirá la URL del servidor y la clave, y las guardará en el
Keychain. **No hay credenciales en el código.**

## Configuración

Todo va en `backend/.env` — está documentado en
[`.env.example`](backend/.env.example). Lo único obligatorio es `APP_PASSWORD`.

Tus datos corporales (altura, edad, objetivo, material del gimnasio) se piden
la primera vez y se editan luego en Ajustes: no hay nada personal en el código.

## Seguridad

- `APP_PASSWORD` protege toda la API. Sin ella, queda abierta: úsala siempre en
  cualquier despliegue accesible desde fuera.
- El reloj usa su propio `GYM_DEVICE_TOKEN`, que solo sirve para
  `/api/gym/device/*`. Si se filtra, el alcance es limitado.
- Nunca commitees `.env`, `token.json` ni `*.pem`; ya están en `.gitignore`.

## Arquitectura

```
backend/     FastAPI + SQLModel sobre SQLite
  app/
    main.py            rutas de hábitos, middleware de auth y jobs programados
    profile.py         perfil y fórmulas (BMR, TDEE, objetivos)
    gym.py             entrenos y recomendación de peso
    diet.py            recetario, plan semanal y compra
    routine_templates.py  plantillas de rutina
    ...
frontend/    React + Vite + Tailwind (PWA)
ios/         App de iOS en SwiftUI + widgets
watch/       App de watchOS con el contador de repeticiones
docs/        Notas de diseño de los algoritmos
```

## Licencia

MIT — ver [LICENSE](LICENSE).
