# FOCUS OS

Sistema personal de productividad para iPhone, nativo en **Swift + SwiftUI** (iOS 17+).
Planifica tu jornada en bloques, mide el tiempo que trabajas de verdad, detecta y bloquea distracciones con las APIs oficiales de Screen Time y sigue tu rendimiento diario, semanal y mensual.

- **Arquitectura y qué permite iOS** → [`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md)
- **Sistema de diseño y pantallas** → [`docs/DISENO.md`](docs/DISENO.md)
- **Plan por fases y checklist de pruebas** → [`docs/ROADMAP.md`](docs/ROADMAP.md)

## Qué incluye

| Sección | Funciones |
|---|---|
| **HOME** | Anillo de efectividad 0–100 % con desglose, tiempo efectivo / planificado / distracciones / restante, bloques completados, temporizador del bloque actual (Pausar, Finalizar, Marcar distracción, Cambiar tarea), estado del día, próximos bloques |
| **SCHEDULE** | Calendario visual por día con **arrastrar para mover** y **tirador para redimensionar**, tira semanal, rutinas por día de la semana, duplicar día, mover tareas a mañana, importar Google Calendar |
| **FOCUS** | Sesiones libres o de bloques, pantalla **DEEP WORK** (temporizador grande, objetivo, barra de concentración, bloqueo de apps, «He terminado» / «Necesito descansar», pase de trabajo) |
| **ANALYTICS** | Día / semana / mes, barras, líneas, donut por categoría, heatmap, comparativas, tendencias, consulta de cualquier fecha, nivel, XP, rachas y logros |
| **SETTINGS** | Objetivos, pesos de la puntuación, alarmas y sonidos, Screen Time, calendario, iCloud, exportación CSV, transparencia de permisos |
| Sistema | Widget (inicio y pantalla de bloqueo), Live Activity + Dynamic Island, notificaciones con la app cerrada, revisión diaria y plan de mañana, onboarding |

## Estructura

```
FocusOS/
├── project.yml              ← proyecto XcodeGen (cuenta de pago, todas las funciones)
├── project-free.yml         ← variante para cuenta gratuita (sin Screen Time)
├── FocusOS/                 ← app
│   ├── App/                 ← entrada, RootView, AppCoordinator (+ sesiones)
│   ├── Models/              ← SwiftData + ajustes
│   ├── Engine/              ← puntuación, agregados, rutinas, gamificación, recomendaciones
│   ├── Services/            ← notificaciones, Screen Time, Live Activity, widget, calendario, CSV
│   ├── DesignSystem/        ← tipografía, tarjetas, anillos, botones
│   ├── Features/            ← Home, Schedule, Focus, Analytics, Settings, Review, Onboarding
│   └── Resources/           ← Assets (icono, colores), sonidos de alarma
├── Shared/                  ← código común app + extensiones (App Group, snapshot, Live Activity)
├── SharedScreenTime/        ← aplicación del Shield (app + monitor)
├── FocusOSWidgets/          ← widget + Live Activity
├── FocusOSMonitor/          ← DeviceActivityMonitor (bloqueo y medición con la app cerrada)
├── FocusOSShield/           ← pantalla de bloqueo personalizada
├── FocusOSShieldAction/     ← botones del Shield (registro de intentos)
└── FocusOSTests/            ← tests del motor de puntuación y rachas
```

---

## Instalación en tu iPhone

### Requisitos

- Mac con **Xcode 16** o superior.
- iPhone con **iOS 17** o superior y cable (o emparejado por Wi‑Fi).
- **Cuenta Apple Developer de pago (99 €/año)** para Screen Time (bloqueo y medición de apps), avisos *Time Sensitive*, App Groups (widget) e iCloud. Con una cuenta gratuita puedes usar la variante `project-free.yml` (ver más abajo).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) para generar el `.xcodeproj`:
  ```bash
  brew install xcodegen
  ```

### 1. Configura tus identificadores

Edita `project.yml` (sección `settings.base`):

```yaml
BUNDLE_PREFIX: com.tunombre.focusos        # p. ej. com.jansadurni.focusos (debe ser único)
APP_GROUP_ID: group.com.tunombre.focusos   # "group." + BUNDLE_PREFIX
DEVELOPMENT_TEAM: "ABCDE12345"             # tu Team ID (developer.apple.com › Membership)
```

Los bundle IDs resultantes son: `BUNDLE_PREFIX` (app), `.widgets`, `.monitor`, `.shield`, `.shieldaction`. El App Group se inyecta en los entitlements y en el Info.plist de todos los targets, así que solo se cambia aquí.

### 2. Genera y abre el proyecto

```bash
cd FocusOS
xcodegen generate
open FocusOS.xcodeproj
```

### 3. Firma

1. En Xcode selecciona el proyecto › cada target (FocusOS, FocusOSWidgets, FocusOSMonitor, FocusOSShield, FocusOSShieldAction) › **Signing & Capabilities**.
2. Marca **Automatically manage signing** y elige tu **Team**.
3. Xcode registrará los bundle IDs, el App Group y las capacidades (Family Controls, App Groups, Time Sensitive Notifications). Si alguna aparece en rojo, pulsa **Try Again** o añádela con **+ Capability**.

### 4. Activa el modo desarrollador en el iPhone

Ajustes › Privacidad y seguridad › **Modo de desarrollador** › activar y reiniciar (solo la primera vez).

### 5. Ejecuta

Conecta el iPhone, selecciónalo arriba en Xcode y pulsa **▶︎ Run** (⌘R). La primera vez puede que tengas que confiar en el certificado: Ajustes › General › VPN y gestión de dispositivos.

> ⚠️ Screen Time **no funciona en el simulador**: pruébalo siempre en el iPhone real.

### 6. Primer uso

1. Onboarding: activa notificaciones, autoriza Screen Time (Face ID/código) y carga la jornada tipo o empieza en blanco.
2. **Settings › Distracciones (Screen Time)**: elige las apps de *Trabajo profundo* (TikTok, Instagram, YouTube, X…) y de *Trabajo*, y la política (Bloquear / Solo medir / Nada).
3. Añade el widget: mantén pulsada la pantalla de inicio › **+** › FOCUS OS.
4. Para Google Calendar: Ajustes de iOS › Calendario › Cuentas › Añadir cuenta › Google, y luego Schedule › ⋯ › Importar.

### Cuenta gratuita

```bash
xcodegen generate --spec project-free.yml
```

Instala la app sin las extensiones de Screen Time ni los entitlements que Apple reserva a cuentas de pago. Todo lo demás funciona (bloques, temporizador, alarmas, estadísticas, Live Activity…). Las distracciones se registran manualmente y la app lo indica en la puntuación. La firma gratuita caduca a los **7 días**: vuelve a pulsar Run para renovarla. Si Xcode rechaza el App Group, quita esa clave de los entitlements (el widget se quedará sin datos).

### iCloud (opcional)

1. Target FocusOS › **+ Capability › iCloud** › marca **CloudKit** y crea un contenedor `iCloud.<BUNDLE_PREFIX>`.
2. En la app: Settings › Datos › **Sincronizar con iCloud** y reinicia la app.

### Distribución (TestFlight / App Store)

Para subirla necesitas además el **entitlement de distribución de Family Controls**: solicítalo en <https://developer.apple.com/contact/request/family-controls-distribution> para los 4 bundle IDs que lo usan (app, monitor, shield, shieldaction). Apple suele responder en días o semanas. Para uso personal en tu iPhone no hace falta.

### Tests

En Xcode: **⌘U**, o por terminal:

```bash
xcodebuild test -project FocusOS.xcodeproj -scheme FocusOS \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## Cómo se calcula la efectividad

| Componente | Peso por defecto | Fórmula |
|---|---|---|
| Concentración | 40 % | concentrado ÷ (concentrado + distracciones + pausas) en bloques de trabajo |
| Cumplimiento de bloques | 25 % | Σ min(trabajado, planificado) ÷ planificado que ya debería haber ocurrido |
| Tareas completadas | 25 % | bloques completados ÷ bloques vencidos |
| Puntualidad | 10 % | 100 % con ≤ 2 min de retraso, 0 % con ≥ 30 min, lineal entre medias |

- Los pesos se editan en Settings y se normalizan.
- **No penalizan**: descansos programados, «Necesito descansar», bloques de Reunión/llamada y el uso durante un pase de trabajo.
- Si falta un componente, se excluye y la puntuación aparece como **Estimada**; sin datos, **Sin datos suficientes**.
- Ejemplo: 6 h planificadas, 5 h 15 min efectivas y 45 min de distracciones → concentración 87,5 %, cumplimiento 87,5 %, tareas 100 %, puntualidad 100 % → **92 %**.

## Solución de problemas

| Problema | Solución |
|---|---|
| «Falta el entitlement com.apple.developer.family-controls» | Necesitas cuenta de pago y que el target tenga la capacidad Family Controls. Con cuenta gratuita usa `project-free.yml`. |
| El widget no muestra datos | El App Group debe ser idéntico en app y widget (lo es si solo lo cambias en `project.yml`) y estar firmado. Ver Settings › Permisos y límites. |
| No llegan las alarmas | Settings › Alarmas › Permitir. Revisa que el modo Concentración de iOS permita FOCUS OS. Abre la app una vez al día para renovar la ventana de avisos. |
| No se miden minutos de una app | Solo en bloques de ≥ 15 min con política *Medir* o *Bloquear*, apps elegidas para ese tipo de bloque y Screen Time autorizado. Los datos aparecen al abrir FOCUS OS. |
| La Live Activity no aparece | Ajustes de iOS › FOCUS OS › Actividades en vivo activadas. |
