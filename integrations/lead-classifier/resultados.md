# Resultados del piloto local

Resultados históricos de la versión anterior (2e35645). Evaluación del 18/11/2026 con Qwen3-4B-Instruct-2507 Q4_K_M, inferencia enteramente en CPU mediante llama.cpp b7100. No se llamó a una API de IA de pago. Los dos controles de seguridad explícitos (baja y asentimiento sin contexto) son parte del sistema evaluado.

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

## Qué se corrige el 19/11/2026

En la ejecución local comunicada desde Windows no hubo errores de inferencia. La tanda general tuvo un falso prioritario (15/16 niveles y 16/16 indicadores). La tanda adicional acertó los ocho ejemplos. Las dos consultas de precio del bloque bilingüe quedaron en el nivel correcto, pero recibieron una etiqueta económica indebida (12/12 niveles, 10/12 indicadores). La captura no identifica el falso prioritario de la tanda general.

Esta revisión distingue una pregunta de precio de una barrera económica, contrasta las consultas comerciales ambiguas con el turno del atleta y su antecedente, e informa de los identificadores sintéticos que fallen. No se han cambiado los casos, los resultados esperados ni los umbrales. Se debe volver a pasar la prueba en el PC de destino.

La revisión del 19/11 se verificó con el modelo Qwen3 indicado, ejecutado en Ollama 0.11.10 sobre CPU Linux. Generamos respuestas reales para las 36 conversaciones ficticias; para agilizar la evaluación se agruparon peticiones con el mismo prefijo. Se volvió a pasar el lanzador de calidad sobre esas mismas respuestas, reutilizadas únicamente en el entorno de verificación. El programa distribuido no incluye esa caché y en Windows ejecuta su propia inferencia local.

| Bloque | Nivel | Etiquetas exactas | Falsos muy interesados |
|---|---:|---:|---:|
| General | 16/16 | 16/16 | 0 |
| Adicional | 8/8 | 8/8 | 0 |
| Parejas de castellano y catalán | 12/12 | 12/12 | 0 |

Además pasaron 31 pruebas de código. Los resultados son de ejemplos ficticios, no de una instalación en Windows ni de una bandeja real. El ZIP no contiene resultados del equipo de Jan, claves, modelos ni permisos de activación.
