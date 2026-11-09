# evolution-patch

Parche temporal sobre la imagen `evoapicloud/evolution-api:latest`
(Evolution API v2.3.7, Baileys `7.0.0-rc.9`).

## Por qué existe

WhatsApp está desplegando por fases un cambio que entrega los estados de los
contactos como un stanza `<status>` de primer nivel, en lugar del
`<message from="status@broadcast">` de siempre. Baileys no tiene handler para
ese nodo, así que nunca lo confirma con un ack. Unos 50 minutos después el
servidor corta el stream:

```json
{"tag":"stream:error","content":[{"tag":"ack","attrs":{"class":"status",...}}]}
```

Lo que más duele no es la desconexión: **mientras el `<status>` espera su ack,
WhatsApp retiene los mensajes entrantes**. La sesión aparece conectada pero no
llega nada, y al reconectar entra todo de golpe.

Incidente real en producción el 7 nov 2026: 5 h 45 min de mensajes de clientes
retenidos, liberados todos a la vez a las 22:24 UTC.

## Qué contiene

`messages-recv.js` es el fichero compilado
`/evolution/node_modules/baileys/lib/Socket/messages-recv.js` de esa imagen, con
tres cambios (17 líneas) portados del PR de Baileys:

1. `handleStatus`, que solo manda el ack vía `sendMessageAck`
2. Registro de `['status', handleStatus]` en el mapa de nodos offline
3. `ws.on('CB:status', ...)` enrutado por `processNode`

No descifra nada, no toca el flujo de mensajes ni la criptografía.

## Origen

- Bug: https://github.com/WhiskeySockets/Baileys/issues/2858
- Fix portado de: https://github.com/WhiskeySockets/Baileys/pull/2883

**El PR no estaba mergeado cuando se aplicó esto (9 nov 2026).** Varios terceros
reportan en el hilo haberlo aplicado en producción sobre esta misma combinación
(Evolution 2.3.7 + Baileys rc.9) sin tener que reescanear el QR.

## Cuándo borrar esto

En cuanto el fix llegue a la imagen oficial de Evolution. Entonces hay que quitar:

1. Esta carpeta
2. La línea del volumen en `docker-compose.yaml`
3. `evolution-patch/` del `source:` en `.github/workflows/deploy-development.yml`

Si no se quita, estaríamos pisando una versión futura de Baileys con código viejo.

## Ojo al tocarlo

El bind-mount necesita que el fichero exista en el host. Si se referencia en el
compose y no se copia, Docker crea un **directorio vacío** en esa ruta y Evolution
no arranca bien. Los tres puntos de arriba van siempre juntos.
