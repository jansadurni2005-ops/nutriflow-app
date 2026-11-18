# Clasificación comercial de Manychat — preparación y auditoría, 18/11/2026

> **Actualización del piloto local:** la auditoría de abajo es la foto inicial. El [código actual, instrucciones de uso y límites](../integrations/lead-classifier/README.md) y los [resultados de inferencia real](../integrations/lead-classifier/resultados.md) la actualizan. No se ha activado en la bandeja de producción.

## Estado en la primera auditoría

Código de preparación, NO sistema instalado. No se ha cambiado Manychat, ni sus
etiquetas/campos/filtros, ni bienvenida/protocolo/Default Reply, ni se ha procesado
una conversación real. No hay proveedor IA, webhook, worker, esquema SQL ni
adaptador Meta desplegados para este clasificador. No se ha probado el estado de
no leído. Esta propuesta NO reemplaza la integración de leads ya existente.

Se ha comprobado mediante consulta de metadatos en Supabase que la credencial
Instagram del CRM venció el 17/11/2026. Esto no demuestra que esté caducada la
conexión independiente de Manychat. No se han consultado ni exportado tokens.
No hay credenciales de Manychat/modelo configuradas en este entorno de trabajo;
esto no permite determinar qué secretos tiene ya configurados el servidor.

## Auditoría oficial

| Pregunta | Hallazgo y límite |
|---|---|
| Inbox/no leídos | Hay filtro Unread y filtros por condiciones. Etiquetas de Inbox automáticas por condiciones, sujetas a beta/plan/cuenta. No se han inspeccionado chats de esta cuenta. |
| Campos/etiquetas | La API pública permite crearlos y actualizar campos/addTag/removeTag. Preferir un campo principal + booleanos independientes, evitando categorías contradictorias y disparadores de etiquetas existentes. |
| Intention Recognition | Es un disparador de intención de mensaje, disponible en Instagram. Su documentación no garantiza acceso al historial de ambos participantes ni cobertura de conversaciones manuales pausadas. No basta para certificar este requisito contextual. |
| Clasificación sin respuesta | La integración ChatGPT documenta guardar respuesta en campo y, separadamente, enviarla con un bloque de texto. Por tanto es viable diseñar solo metadatos; falta comprobar cobertura y efectos en esta cuenta. No activar AI Replies/AI Step conversacional. |
| Entrantes/Default Reply | Se configura por mensaje o una vez/24h; Last Text Input registra último texto del contacto, no historial completo. Es un fallback, no suscripción universal independiente a todos los mensajes. |
| Conversaciones manuales | Inbox pausa automatizaciones al responder manualmente (30 min por defecto). No garantizar captura universal con Default Reply/intenciones. La API de conversaciones Meta es la candidata para historial real; permisos/routing y cobertura pendientes. |
| Historial API Manychat | Swagger público Page API consultado: getInfo y last_input_text, sin endpoint de historial completo documentado. No confundir historial visible en Inbox con historial accesible por API. |
| Contexto Meta | Conversations/Message APIs son oficiales. La referencia Graph documenta detalles consultables de los últimos 20 mensajes. Instagram Login usa permisos diferentes de Facebook Login; verificar producto, versión y permisos de la app real antes de implementar. |
| Webhook/external request | External Request admite HTTPS con campos del contacto y personalizados. No aporta por sí mismo tus respuestas anteriores. Webhooks Meta son candidatos oficiales; hace falta suscripción, permisos de mensajes y vínculo estable del ID Instagram al subscriber Manychat. No enlazar por nombre aproximado. |
| Lectura/no leído | Meta documenta acción explícita mark_seen; el diseño la excluye. Eso NO prueba el estado local Unread de Manychat al escribir metadatos. Prueba A obligatoria antes de piloto. |
| Plan | API y External Request dependen del plan. Pro actual ofrece API y organización de Inbox; hay cuentas con precios/modelos anteriores. No se ha verificado disponibilidad exacta de etiquetas/IA en esta cuenta. |
| Coste IA | API se factura separadamente de ChatGPT. Puede haber créditos promocionales para Pro elegible, pero requieren activación y verificación de saldo. No se han contratado servicios ni generado consumo. Presupuesto pendiente de modelo, volumen y longitud del contexto. |
| Automatizaciones actuales | No se han editado. Es necesario auditar acciones que reaccionen a campos/etiquetas antes de escribir cualquier resultado. No se ha certificado la prueba G. |
| NO CONTACTAR | Un booleano del clasificador NO detiene por sí mismo flujos existentes. Hace falta supresión comercial efectiva y verificada, con cambios revisados de los flujos afectados. No se debe retirar automáticamente una exclusión previa por omisión del modelo. |

## Implementación incluida

`integrations/lead-classifier/core.mjs` incluye prompt contextual castellano/catalán,
salida estructurada, validación, evidencia por IDs, abstención con contexto
incompleto/baja confianza/error, flags independientes y escritor limitado al
endpoint oficial `/fb/subscriber/setCustomFields`. Sin métodos de enviar mensajes,
marcar lectura, abrir/cerrar chats ni borrar contactos. No guarda texto bruto.
`infer` es una dependencia aún no conectada; no es un modelo ni un simulador por
palabras clave. No existe recepción autenticada de eventos todavía.

Campos propuestos (NO creados): SN Interés, SN Motivo, SN Confianza, SN Revisar,
SN Clasificado, y booleanos SN has_nutritionist / call_accepted / call_scheduled /
current_client / do_not_contact / price_objection. Motivo es un código comercial,
no texto libre potencialmente sensible; evidencia solo IDs en backend. Interés:
hot, warm, neutral, cold, unknown. Valores españoles en etiquetas de Inbox al
configurarlas. No almacenar estado no leído si no hay fuente oficial.

Escritor en dry_run por defecto. Los gates del módulo son precondiciones para un
futuro worker de confianza, NO autenticación ni prueba persistente de aprobación.
No exponerlo como endpoint al que un cliente pueda aportar estos booleanos.
Requiere antes del uso real: trabajador autenticado, identidad exacta de contacto,
cola serial por contacto, idempotencia, control de revisiones obsoletas, retención,
RLS por propietario y control persistente de aprobación. NO CONTACTAR debe ser
persistente hasta revocación humana verificable. Conservar cliente actual desde
CRM autoritativo; no confiar solo en el modelo para esa exclusión.

## Arquitectura candidata

1. Fuente oficial Meta (webhook + consulta de contexto autorizada) mantiene ambas
   partes del diálogo. No cambiar propiedad/routing de Manychat para conseguirlo.
2. Worker Supabase autenticado obtiene contexto mínimo en memoria. Si falta
   historial o hay audio/imagen no interpretados, abstenerse o pedir revisión.
3. Tras acordar proveedor, condiciones de tratamiento, presupuesto y retención,
   invocar IA con JSON estructurado. No enviar información sensible sin resolver
   ese tratamiento; no afirmar que anonimizar el nombre elimina los datos de salud.
4. Persistir clasificación comercial mínima y evidencia por ID, con control de
   revisión y exclusiones. Sin transcript bruto en logs/campos públicos.
5. Escribir metadatos Manychat solo tras prueba A y auditoría de efectos secundarios.
6. Crear etiquetas automáticas por condiciones si esta cuenta las admite y combinar
   con Unread. Mantener Inbox como herramienta principal.

Esta arquitectura no está certificada: permisos Meta/Conversation Routing pueden
limitar cobertura paralela con Manychat. Si no hay vía oficial que la respete,
parar la activación y pedir confirmación técnica a Manychat antes de sustituirla.

## Pruebas y criterios de activación

Ejecutar `node --test tests/lead-classifier.test.mjs`.
14 pruebas locales de contrato/seguridad pasan. Transportes y resultado de IA son
stubs: NO miden precisión de un modelo ni conexión real a Manychat. El conjunto
`evaluation.json` contiene 16 casos sintéticos esperados, AÚN NO evaluados con IA.
No contiene conversaciones privadas ni ejemplos extraídos de Inbox.

| Prueba solicitada | Estado |
|---|---|
| A no leído y cero mensajes | Pendiente: contacto de prueba, observación oficial/por Jan antes y después, escritura de metadatos y comprobación del número de mensajes salientes. No abrir chat con automatización. |
| B contexto | Casos preparados, evaluación IA pendiente. |
| C nutricionista | Normalización de flags comprobada con stubs; interpretación IA pendiente. |
| D cambio de interés | Reemplazo de campo comprobado; evaluación IA y orden de eventos pendientes. |
| E negativa | Flag/modelo preparado; supresión real de flujos y persistencia pendientes. |
| F conversación manual | Bloqueada por acceso autorizado al contexto real y prueba de cobertura. |
| G automatizaciones existentes | Sin cambios realizados; regresión controlada pendiente. |
| H calidad masiva | Pendiente de corpus anonimizado revisado por Jan y modelo/presupuesto aprobado. |

No activar masivamente. Tras resolver acceso y privacidad, evaluar casos sintéticos,
revisar falsos positivos de hot (recurso/llamada), catalán y abstención. Después
piloto de un único contacto autorizado; A/F/G deben pasar antes de aumentar
cobertura. La activación gradual requiere aprobación explícita de Jan.

## Fuentes consultadas

- https://help.manychat.com/en/articles/17742012-manychat-inbox
- https://help.manychat.com/en/articles/17742162-manychat-ai-intention-recognition
- https://help.manychat.com/en/articles/17742069-default-reply-in-manychat
- https://help.manychat.com/en/articles/17742126-dev-tools-external-request
- https://help.manychat.com/en/articles/17741925-chatgpt-integration
- https://help.manychat.com/hc/en-us/articles/25800228332572-Pro-plan
- https://help.manychat.com/en/articles/17742089-how-to-generate-a-token-for-the-manychat-api-and-where-to-get-parameters
- https://api.manychat.com/swagger/compileJson?type=Page_API
- https://developers.facebook.com/docs/graph-api/reference/conversation/
- https://developers.facebook.com/docs/graph-api/webhooks/reference/instagram
- https://developers.facebook.com/documentation/business-messaging/instagram-messaging/changelog/
- https://help.openai.com/en/articles/9039756-managing-billing-for-chatgpt-and-the-api-platform
- https://help.openai.com/en/articles/20001626-api-credits-benefit-for-eligible-chatgpt-subscriptions
