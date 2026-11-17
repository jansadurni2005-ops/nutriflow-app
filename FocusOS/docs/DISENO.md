# FOCUS OS — Sistema de diseño

Inspiración: la densidad de datos de WHOOP, la sobriedad de Linear, la calidez de Things 3 y el ritual de Forest. Nada de dashboard corporativo: una herramienta de alto rendimiento personal.

## Color

| Token | Hex | Uso |
|---|---|---|
| `background` | `#090909` | Fondo de todas las pantallas |
| `card` | `#171717` | Tarjetas |
| `cardElevated` | `#202020` | Controles, métricas dentro de tarjetas |
| `accent` | `#FF6500` | Naranja eléctrico: progreso, acción principal, estado activo |
| `success` | `#35D07F` | Completado |
| `warning` | `#FFB020` | Pausa, estimado, retraso |
| `danger` | `#FF3B30` | Distracciones, no realizado |
| Texto | `#FFFFFF` / `#A1A1A1` / `#5E5E5E` | Primario / secundario / terciario |

El color de la puntuación escala de rojo (< 50 %) a ámbar y naranja (≥ 85 %). El anillo se dibuja **discontinuo** cuando la puntuación es *estimada*.

## Tipografía

- **Números**: SF Pro *Condensed*, peso Heavy/Bold, dígitos monoespaciados (temporizador, %, horas). Sensación deportiva y lectura instantánea.
- **Etiquetas**: SF Pro *Expanded* semibold 11 pt en MAYÚSCULAS con *tracking* 1.4 ("EFECTIVIDAD", "TRABAJO PROFUNDO").
- **Títulos de pantalla**: SF Pro Expanded Heavy 30 pt.
- **Texto**: SF Pro estándar.

## Componentes

- **Tarjeta**: radio 24 continuo, borde 1 px blanco 7 %, resaltado con el color del bloque cuando está activa.
- **RingGauge**: anillo con gradiente angular, sombra del color, animación *spring* al aparecer y al cambiar.
- **MetricTile**: icono + etiqueta + valor condensado + nota al pie (p. ej. "Solo registro manual").
- **ControlButton**: botón circular de 56 pt con etiqueta (Pausar, Finalizar, Distracción, Cambiar).
- **Tab bar propia**: 5 secciones con cápsula naranja que se desplaza (`matchedGeometryEffect`) y háptico de selección.
- **Barra de sesión flotante**: aparece sobre la tab bar mientras hay una sesión activa fuera de DEEP WORK.
- **Toasts**: confirmaciones y avisos no intrusivos (3 s).
- **Estados vacíos** con acción directa (p. ej. "Usar jornada de ejemplo").

## Pantallas

1. **HOME** — saludo + fecha · anillo de efectividad grande (toca para ver el desglose y la fórmula) · 4 métricas (efectivo, planificado, distracciones, restante) + bloques completados · temporizador del bloque actual con Pausar / Finalizar / Marcar distracción / Cambiar tarea · estado del día (barra + mini línea temporal coloreada) · próximos bloques.
2. **SCHEDULE** — tira semanal (L–D) · línea temporal con bloques posicionados por hora, columnas si se solapan, línea "ahora" · mantener pulsado + arrastrar para mover (ajuste a 5 min, háptico) · tirador inferior para cambiar duración · toca una hora vacía para crear · modo **Rutinas** por día de la semana.
3. **FOCUS** — nueva sesión libre (25/50/90/120 min, tipo, categoría, bloqueo) · empezar un bloque de hoy · sesiones terminadas con concentración.
4. **DEEP WORK** (pantalla completa) — halo que "respira", objetivo, anillo con cuenta atrás grande, acumulado/distracción/fin, **barra de concentración**, estado del bloqueo, "He terminado" y "Necesito descansar", pantalla siempre encendida opcional.
5. **ANALYTICS** — Día / Semana / Mes · barras planificado vs efectivo · línea de efectividad con objetivo · mejor/peor día · comparativa con el periodo anterior · heatmap mensual (toca un día para abrirlo) · evolución de la concentración · donut por categoría · tendencia · nivel, XP, rachas y logros.
6. **SETTINGS** — objetivos, pesos de la puntuación, alarmas, Screen Time, calendario, datos/iCloud/CSV, transparencia de permisos.

## Movimiento

- Transiciones *spring* (respuesta 0,3–0,45 s, amortiguación 0,8–0,85).
- `contentTransition(.numericText)` en números que cambian.
- Hápticos: selección (tabs, chips), firme (empezar sesión, coger un bloque), éxito (terminar, soltar bloque), aviso (distracción).

## Gamificación sin infantilismo

Niveles con títulos sobrios (Iniciado → Constante → Enfocado → Disciplinado → Operador → Estratega → Élite → Maestro del foco), XP ligado a minutos reales de concentración, logros con barra de progreso y sin confeti. Todo se recalcula a partir del historial: no hay puntos "regalados".
