# Resultados del piloto local

Evaluación del 18/11/2026 con Qwen3-4B-Instruct-2507 Q4_K_M, inferencia enteramente en CPU mediante llama.cpp b7100. No se llamó a una API de IA de pago. Los dos controles de seguridad explícitos (baja y asentimiento sin contexto) son parte del sistema evaluado.

| Bloque | Nivel | Indicadores exactos | Muy interesados detectados | Falsos muy interesados |
|---|---:|---:|---:|---:|
| 16 casos de desarrollo | 16/16 | 16/16 | 6/6 | 0 |
| 8 casos adicionales | 8/8 | 8/8 | 3/3 | 0 |
| 6 parejas castellano/catalán | 12/12 | 12/12 | 4/4 | 0 |

Son ejemplos ficticios; los ejemplos de desarrollo sirvieron para ajustar el clasificador. Estas cifras no estiman la precisión real en la bandeja de Jan. El modelo en Ollama se debe volver a evaluar en el equipo donde vaya a funcionar.

20 pruebas de código de validación, privacidad, identidad, transporte y revisión del piloto: superadas. No son ensayos en la cuenta real.

| Caso | Nivel esperado | Resultado | Indicadores |
|---|---|---|---|
| yes-call | hot | hot | call_accepted |
| yes-resource | neutral | neutral | — |
| yes-goal | warm | warm | — |
| service-how | hot | hot | — |
| recipe-how | neutral | neutral | — |
| nutritionist-interest | hot | hot | has_nutritionist |
| nutritionist-decline | cold | cold | has_nutritionist |
| budget | warm | warm | price_objection |
| catalan-interest | warm | warm | — |
| catalan-price | hot | hot | — |
| catalan-stop | cold | cold | do_not_contact |
| social | neutral | neutral | — |
| missing-context | unknown | unknown | — |
| recent-rejection | cold | cold | — |
| recent-interest | hot | hot | — |
| booked | hot | hot | call_scheduled |
| ca-trucada | hot | hot | call_accepted |
| ca-regal | neutral | neutral | — |
| es-registro | neutral | neutral | — |
| es-plaza | hot | hot | — |
| ca-nutri | hot | hot | has_nutritionist |
| es-baja | cold | cold | do_not_contact |
| ca-goal | warm | warm | — |
| short | unknown | unknown | — |
| es-precio | hot | hot | — |
| ca-precio | hot | hot | — |
| es-esperar | warm | warm | price_objection |
| ca-esperar | warm | warm | price_objection |
| es-no-mensajes | cold | cold | do_not_contact |
| ca-no-mensajes | cold | cold | do_not_contact |
| es-pauta | neutral | neutral | — |
| ca-pauta | neutral | neutral | — |
| es-reservada | hot | hot | call_scheduled |
| ca-reservada | hot | hot | call_scheduled |
| es-sin-contexto | unknown | unknown | — |
| ca-sin-contexto | unknown | unknown | — |

**Pruebas reales pendientes:** dos vías del diálogo, campos auténticos de Manychat, No leídos antes/después, ausencia de mensajes adicionales y regresión de los flujos actuales. Nunca se abrió un chat real ni se activó producción desde estas pruebas.
