# Life Hub

Un panel personal para el día a día: hábitos, gimnasio, nutrición, sueño,
tareas y progreso, en una app de iOS con widgets y contador de repeticiones
para el Apple Watch.

**Funciona nada más instalarla.** No hace falta montar ningún servidor ni
tocar una línea de código: se compila en Xcode, se abre, se rellenan cuatro
datos y ya está. Todo se guarda en tu iPhone.

Si quieres además correo, agenda, finanzas y resúmenes con IA, puedes conectar
un backend propio desde Ajustes. Es opcional.

## Empezar en 5 minutos

Necesitas un Mac con Xcode y un iPhone.

```bash
git clone https://github.com/daniel-madrid-07/lifehub.git
cd lifehub/ios
brew install xcodegen     # si no lo tienes
xcodegen generate
open LifeHub.xcodeproj
```

En Xcode:

1. Selecciona el target **LifeHub** → pestaña **Signing & Capabilities**.
2. En **Team**, elige tu cuenta de Apple (la gratuita vale).
3. Cambia el **Bundle Identifier** por uno tuyo, por ejemplo
   `com.tunombre.lifehub`. Haz lo mismo en el target **LifeHubWidgets**
   (`com.tunombre.lifehub.widgets`).
4. Elige tu iPhone como destino y pulsa **Run**.

La primera vez que abras la app te preguntará tu altura, edad, sexo, objetivo
y cómo entrenas. Con eso calcula tus calorías y proteína, y te ofrece crear
las rutinas a partir de una plantilla. Nada más.

> Con una cuenta de Apple gratuita la app caduca a los 7 días y hay que volver
> a instalarla. Con el Apple Developer Program (99 €/año) dura un año.

### App Group (solo si quieres widgets)

Los widgets comparten datos con la app mediante un App Group. Si los vas a
usar, en **Signing & Capabilities** de ambos targets cambia
`group.com.example.lifehub` por uno tuyo, y actualiza `appGroupID` en
[`ios/LifeHub/Core/AppConfig.swift`](ios/LifeHub/Core/AppConfig.swift).

Sin esto la app funciona igual; solo los widgets se quedan sin datos.

## Qué incluye

Sin servidor, guardando todo en el iPhone:

| Módulo | Qué hace |
|---|---|
| **Hábitos** | Rutinas por horario, por días de la semana o cada N días, con rachas |
| **Gimnasio** | Rutinas, registro de series y recomendación de peso por doble progresión |
| **Nutrición** | Registro de comidas con objetivos de calorías y proteína calculados |
| **Progreso** | Peso, medidas corporales y récords personales |
| **Tareas** | Pendientes con fecha, y notas rápidas |
| **Widgets** | Hábitos de hoy, macros, entreno del día |

Conectando un backend propio, además:

| Módulo | Qué añade |
|---|---|
| **Correo y agenda** | Gmail y calendario de iCloud |
| **Finanzas** | Cartera de Alpaca y Bitvavo |
| **Estudios** | La IA revisa el repo de tu proyecto y te dice cómo vas |
| **Sueño** | Análisis por ciclos con datos de Apple Salud |
| **Armario** | Prendas, uso y sugerencia de outfit según el tiempo |
| **Resúmenes IA** | Coach diario, análisis de entrenos y de macros |
| **Sincronización** | Los mismos datos en varios dispositivos |

### Contador de repeticiones en el Apple Watch

La app de watchOS cuenta las repeticiones sola con el acelerómetro: PCA sobre
la señal para encontrar el eje real del movimiento, filtro paso banda y conteo
en el extremo del recorrido, con calibración por ejercicio que aprende de tus
correcciones. Funciona sin conexión.

Se compila aparte, igual que la de iOS: ver [`watch/README.md`](watch/README.md).

## Conectar un servidor (opcional)

Solo si quieres los módulos de la segunda tabla.

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

Después, en la app: **Ajustes → Servidor**, pon la URL y la clave, y conecta.

La base de datos SQLite se crea sola, con un catálogo de ejercicios y un
recetario de ejemplo que puedes borrar entero.

Todas las variables están documentadas en
[`backend/.env.example`](backend/.env.example). Lo único obligatorio es
`APP_PASSWORD`.

> **Sirve el backend por HTTPS.** La clave viaja en cada petición: sobre HTTP
> plano va en claro. Un proxy con Caddy y un certificado de Let's Encrypt
> basta.

### PWA (opcional)

Hay también una versión web, por si la prefieres en el navegador o en Android:

```bash
cd frontend
npm install
npm run dev
```

Necesita el backend en marcha. En producción, `npm run build` y sirve `dist/`
detrás del backend.

## Seguridad

- No hay ninguna credencial en el código. La URL y la clave del servidor se
  guardan en el Keychain del dispositivo.
- `APP_PASSWORD` protege toda la API del backend. Sin ella queda abierta:
  úsala siempre que sea accesible desde fuera.
- El reloj usa su propio `GYM_DEVICE_TOKEN`, que solo sirve para
  `/api/gym/device/*`. Si se filtra, el alcance es limitado.
- Nunca commitees `.env`, `token.json` ni `*.pem`; ya están en `.gitignore`.

## Arquitectura

```
ios/         App de iOS en SwiftUI + widgets
  LifeHub/Core/
    LocalStore.swift    almacen local (modo sin servidor)
    LocalAPI.swift      resuelve las peticiones contra el almacen local
    APIClient.swift     decide entre local y red en un solo punto
    AppConfig.swift     URL y clave del servidor (Keychain)
watch/       App de watchOS con el contador de repeticiones
backend/     FastAPI + SQLModel sobre SQLite (opcional)
  app/
    profile.py            perfil y formulas (BMR, TDEE, objetivos)
    gym.py                entrenos y recomendacion de peso
    diet.py               recetario, plan semanal y compra
    routine_templates.py  plantillas de rutina
frontend/    React + Vite + Tailwind (PWA, opcional)
docs/        Notas de diseño de los algoritmos
```

Como todas las llamadas pasan por un único `request()`, el modo local y el
modo servidor comparten exactamente las mismas vistas: la app no sabe en cuál
de los dos está.

## Licencia

MIT — ver [LICENSE](LICENSE).
