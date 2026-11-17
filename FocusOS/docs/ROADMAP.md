# FOCUS OS — Plan de implementación por fases

| Fase | Contenido | Estado |
|---|---|---|
| **0. Base** | Proyecto XcodeGen (app + 4 extensiones + tests), SwiftData compatible con CloudKit, sistema de diseño, navegación de 5 secciones, onboarding | ✅ Hecho |
| **1. Núcleo** | Bloques con todos los campos, estados, retraso y tiempo real; rutinas semanales por día; calendario visual con arrastrar y redimensionar; duplicar día; mover a mañana | ✅ Hecho |
| **2. Temporizador** | Sesiones por marcas temporales, pausa/descanso/distracción/cambio de tarea, DEEP WORK, recuperación de sesiones interrumpidas, cambios de hora | ✅ Hecho |
| **3. Alarmas** | Aviso previo, inicio, fin, "no has empezado", descanso próximo, fin de jornada, resumen diario, motivación a los 90 min, "vuelve al foco", acciones en la notificación (Empezar / Posponer), sonidos propios, ventana rodante de 64 | ✅ Hecho |
| **4. Efectividad y estadísticas** | Motor con pesos editables y confianza; Analytics día/semana/mes, heatmap, categorías, comparativas, tendencias; consulta de cualquier fecha | ✅ Hecho |
| **5. Distracciones** | Autorización Screen Time, selección de apps por tipo de bloque, política por bloque, bloqueo automático con app cerrada, medición por minutos, Shield personalizado, intentos registrados, pase de trabajo | ✅ Hecho (requiere cuenta de pago y probar en dispositivo) |
| **6. Superficies del sistema** | Widget (inicio + pantalla de bloqueo), Live Activity + Dynamic Island | ✅ Hecho |
| **7. Avanzado** | Revisión diaria con recomendaciones, plan de mañana, importación de Google Calendar vía EventKit, CSV, iCloud opcional, objetivos, XP, rachas y logros | ✅ Hecho |
| **8. Pulido (siguiente)** | App Intents (Siri/Atajos: "Empieza mi bloque"), botón de pausa interactivo en Live Activity (iOS 17 App Intents), control del Centro de Control (iOS 18), modo Focus del sistema vía Focus Filters, importación directa por la API de Google con OAuth, localización EN | ⏭️ Propuesto |

## Checklist de verificación en dispositivo

- [ ] Crear un bloque que empiece en 6 min → llega el aviso a los 5 min con la app cerrada.
- [ ] Empezar el bloque 3 min tarde → aparece "retraso 3 min" en el editor y en Analytics.
- [ ] Bloquear el iPhone 10 min con una sesión activa → al volver, el temporizador es exacto.
- [ ] Forzar cierre de la app durante una sesión y reabrir pasado el fin + 30 min → hoja de recuperación.
- [ ] Autorizar Screen Time, elegir TikTok en Trabajo profundo → al empezar un bloque profundo aparece el Shield de FOCUS OS.
- [ ] Bloque de 20 min con política *Medir* y usar YouTube 3 min → al abrir FOCUS OS aparecen 3 min de distracción (Screen Time).
- [ ] Pase de trabajo → el bloqueo desaparece 15 min y el uso se marca como autorizado.
- [ ] Widget mediano en inicio → muestra bloque actual, cuenta atrás, efectividad y próxima tarea.
- [ ] Live Activity → cuenta atrás en pantalla de bloqueo y Dynamic Island; al pausar se congela.
- [ ] Cambiar la hora del sistema → las alarmas se reprograman.
- [ ] Exportar CSV de 30 días y abrirlo en Numbers.
