# FOCUS OS — Arquitectura y viabilidad en iOS

## 1. Arquitectura

```
┌──────────────────────────── App FOCUS OS (SwiftUI, iOS 17+) ─────────────────────────────┐
│                                                                                          │
│  Features/ (vistas)          App/                     Engine/ (lógica pura, testeable)   │
│  ├─ Home                     ├─ FocusOSApp + AppDelegate   ├─ ScoringEngine   (efectividad)│
│  ├─ Schedule (+ drag&drop)   ├─ RootView (tab bar)    ├─ DayDataService  (agregados)     │
│  ├─ Focus + DEEP WORK        ├─ AppCoordinator        ├─ ScheduleService (rutinas)       │
│  ├─ Analytics (Charts)       └─ AppCoordinator+Session├─ GamificationEngine (XP/rachas)  │
│  ├─ Settings                    (máquina de estados)  └─ InsightsEngine  (revisión)      │
│  ├─ Review / Onboarding                                                                  │
│                                                                                          │
│  Models/ (SwiftData)                 Services/ (sistema)                                 │
│  ├─ WorkBlock    ├─ FocusSession     ├─ NotificationService  (UserNotifications)         │
│  ├─ RoutineItem  ├─ DistractionEvent ├─ ScreenTimeService    (FamilyControls/DeviceActivity)│
│  ├─ DayJournal   └─ AppSettings      ├─ LiveActivityService  (ActivityKit)               │
│                                      ├─ WidgetBridge         (WidgetKit)                 │
│                                      ├─ CalendarImportService(EventKit)                  │
│                                      └─ CSVExporter, Haptics                              │
└───────────────┬──────────────────────────────────────────────────────────────────────────┘
                │ App Group (UserDefaults compartidos: JSON pequeño)
   ┌────────────┼──────────────────────┬───────────────────────────┬─────────────────────┐
   ▼            ▼                      ▼                           ▼                     │
FocusOSWidgets  FocusOSMonitor         FocusOSShield               FocusOSShieldAction    │
Widget + Live   DeviceActivityMonitor  ShieldConfiguration         ShieldActionDelegate   │
Activity        (aplica/retira bloqueo,(pantalla de bloqueo con    (registra intentos de  │
                anota minutos de uso)  marca FOCUS OS)             abrir apps bloqueadas) │
```

### Principios

| Principio | Cómo se aplica |
|---|---|
| **Temporizador exacto** | `FocusSession` guarda `startedAt`, `pauseStartedAt`, `breakStartedAt` y acumulados. Todo tiempo se calcula como `ahora − marcas`, nunca con un contador en memoria. Funciona en segundo plano, con la app cerrada y tras reiniciar. |
| **Datos honestos** | `ScoringEngine` excluye componentes sin datos y marca la puntuación como *Estimada* o *Sin datos*. Las distracciones automáticas solo existen si Screen Time está autorizado y hay apps elegidas; si no, la UI dice "Solo registro manual". |
| **Local primero** | SwiftData en el dispositivo. iCloud (CloudKit privado) opcional; los modelos son compatibles (valores por defecto, sin `unique`, referencias por UUID). |
| **Lógica pura separada** | Motor de puntuación, rachas y logros no dependen de SwiftData → tests unitarios en `FocusOSTests`. |
| **Extensiones mínimas** | Las extensiones de Screen Time tienen ~6 MB de memoria: solo leen/escriben JSON pequeños en el App Group. |

### Flujo de una sesión

1. `startSession(block:)` → crea `FocusSession`, marca `block.actualStart` (registra retraso), estado *En curso*.
2. Si la política es *Bloquear* → `ManagedSettingsStore` aplica el Shield y se programa una actividad `DeviceActivity` que lo retira al terminar aunque la app esté cerrada.
3. Live Activity con cuenta atrás nativa (`Text(timerInterval:)`), notificaciones motivacionales a los 90/180/270 min de concentración.
4. Pausa (interrupción, cuenta en contra de la concentración) / Descanso autorizado (neutral) / Distracción manual.
5. `finishSession(reason:)` → vuelca tiempo efectivo, distracciones y pausas al bloque, fija `actualEnd` (registra si terminaste antes), retira bloqueo, cierra Live Activity, muestra resumen.
6. Si la app estuvo cerrada y la sesión superó su fin en > 30 min → hoja de **recuperación**: el usuario confirma cuándo terminó (no se inventa tiempo).

### Sincronización de servicios (`AppCoordinator.refresh`)

Se ejecuta al abrir la app, tras cada cambio (con *debounce*), en cambios de hora/zona horaria/día y en la tarea `BGAppRefreshTask`:

1. Genera bloques de rutinas para hoy y mañana (una vez por día).
2. Marca como *No realizado* los bloques vencidos sin empezar.
3. Ingiere minutos de uso y los intentos bloqueados que escribieron las extensiones → `DistractionEvent`.
4. Reprograma notificaciones (ventana rodante, límite 64), monitorización de Screen Time, widget y Live Activity.

---

## 2. Qué es posible en iOS y qué no

| Funcionalidad | Estado | API / Notas |
|---|---|---|
| Bloques, rutinas, estados, retrasos, tiempo real | ✅ Completo | SwiftData |
| Temporizador correcto en segundo plano | ✅ | Marcas temporales persistidas |
| Alarmas con la app cerrada | ✅ | `UNCalendarNotificationTrigger`. Límite: 64 pendientes → ventana de ~36 h que se renueva |
| Sonidos personalizados | ✅ | WAV < 30 s en el bundle (`pulse`, `chime`, `rise`) |
| Vibración de notificaciones | ⚠️ | La controla iOS (no hay patrones personalizados para notificaciones). En la app: hápticos |
| Avisos *Time Sensitive* | ✅ | Entitlement `usernotifications.time-sensitive` (cuenta de pago) |
| Live Activity + Dynamic Island | ✅ | ActivityKit, sin push: la cuenta atrás la anima el sistema |
| Widget pantalla de inicio y bloqueo | ✅ | WidgetKit + App Group; entradas en cada cambio de bloque |
| Bloquear TikTok/Instagram/YouTube/X durante bloques | ✅ | FamilyControls (`.individual`) + ManagedSettings. Funciona con la app cerrada vía DeviceActivityMonitor |
| Medir minutos de uso de apps elegidas por bloque | ✅ con límites | `DeviceActivityEvent` con umbrales 1…60 min. Intervalo mínimo 15 min. Nº de actividades limitado → se monitorizan los próximos 12 bloques |
| Saber qué app concreta de la selección se usó | ❌ | Los tokens son opacos; se mide el conjunto |
| Distinguir Reels (ocio) de publicar (trabajo) en Instagram | ❌ | iOS no lo expone. **Alternativa**: política por bloque (No medir / Medir / Bloquear), *pase de trabajo* de ≥ 15 min que registra el uso como autorizado, y registro manual |
| Leer el historial de Tiempo de uso | ❌ | `DeviceActivityReport` solo dibuja dentro de una extensión aislada sin salida de datos |
| Detectar que sales de FOCUS OS | ⚠️ | Se sabe que la app pasa a segundo plano, no a qué app. Se envía "vuelve al foco" salvo si bloqueas el iPhone. No se cuenta como distracción automáticamente |
| Abrir la app desde el Shield | ❌ | No permitido por iOS; el Shield registra el intento y cierra la app bloqueada |
| Google Calendar | ✅ | EventKit tras añadir la cuenta Google en Ajustes de iOS. Solo lectura, sin duplicados (ID de evento + inicio) |
| Sincronización iCloud | ✅ opcional | SwiftData + CloudKit privado (cuenta de pago + capacidad iCloud) |
| Exportar CSV | ✅ | Resumen diario + detalle por bloque, `;` y BOM UTF-8 para Excel |

### Permisos especiales de Apple

| Capacidad | Desarrollo (tu iPhone) | Distribución (TestFlight / App Store) |
|---|---|---|
| **Family Controls** (`com.apple.developer.family-controls`) | Disponible con **cuenta de pago** (99 €/año). Xcode añade "Family Controls (Development)". **No funciona con cuenta gratuita** | Hay que solicitar el entitlement de distribución en <https://developer.apple.com/contact/request/family-controls-distribution> (uno por cada bundle ID: app + 3 extensiones) |
| Time Sensitive Notifications | Cuenta de pago | Igual |
| App Groups | Cuenta de pago (recomendado). Con cuenta gratuita puede no estar disponible | Igual |
| iCloud / CloudKit | Cuenta de pago | Igual |
| Live Activities, WidgetKit, EventKit, UserNotifications | Cualquier cuenta | — |

Con **cuenta gratuita** la app se instala (7 días de validez) usando `project-free.yml`: funciona todo salvo bloqueo/medición de apps, avisos Time Sensitive y (si tu equipo no permite App Groups) el widget.
