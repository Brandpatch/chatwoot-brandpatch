# custom/ — Instrucciones para Claude Code

Esta carpeta contiene **todos los desarrollos propios de BrandPatch** que
reimplementan funcionalidad de Chatwoot Enterprise sin depender de
`enterprise/` (que permanece intacta y sin usar en el proyecto). Actualmente
incluye **Custom Roles** y **SLA** (ver detalle de cada uno abajo).

**Antes de tocar cualquier archivo bajo `custom/`, leé primero
`custom/README.md`** — tiene el mapa de archivos completo, los comandos de
verificación por SSH, y el detalle de los bugs ya encontrados y corregidos.
Este archivo (`CLAUDE.md`) es un resumen orientado a decisiones y reglas de
comportamiento; el README tiene el detalle exhaustivo.

## Contexto general del proyecto

Este es un fork white-label de Chatwoot para BrandPatch, corriendo en
Community Edition (sin licencia Enterprise paga). La empresa pidió
reimplementar funcionalidades de Chatwoot Enterprise (Custom Roles, SLA) de
forma propia, **sin activar ni depender del código bajo `enterprise/`**,
aunque el sistema no lo impida técnicamente (ver "Por qué esto importa" más
abajo). La decisión de no tocar/borrar `enterprise/` fue explícita del
usuario — se mantiene intacta pero inerte.

## Reglas de comportamiento para cualquier trabajo en `custom/`

1. **Nunca reutilizar una columna, asociación o nombre de feature flag que ya
   use `enterprise/`.** Si el nombre coincide, el código Enterprise
   correspondiente puede "activarse" solo con nuestros datos, sin que nadie lo
   haya llamado explícitamente. Siempre usar un nombre propio y distinto
   (prefijo `brandpatch_` en columnas/asociaciones, sufijo `_brandpatch` en
   feature flags).

2. **Verificar siempre si existe una colisión de namespace antes de nombrar
   una clase/módulo nuevo bajo `Custom::`.** Ya existen módulos de prepend
   (ej. `Custom::AccountUser`) que no son modelos — un `belongs_to`/`has_many`
   sin `class_name: '::NombreReal'` explícito puede resolver mal por la forma
   en que Rails busca constantes relativas al namespace del declarante.

3. **Si se prependea un módulo `Custom::X` sobre una clase que también tiene
   un módulo `Enterprise::X` prependeado** (chequear siempre si existe
   contraparte en `enterprise/app/**` antes de escribir el prepend), prefijar
   todos los métodos privados nuevos para evitar que Ruby resuelva llamadas
   sin receptor hacia el módulo equivocado.

4. **No asumir que `enabled: true` en `config/features.yml` alcanza.** Solo
   aplica a cuentas nuevas (vía `ConfigLoader`, enganchado a `db:migrate`).
   Cuentas existentes necesitan una migración de datos explícita
   (`Account.find_in_batches` + `enable_features!`).

5. **No ejecutar comandos en la terminal a menos que el usuario lo pida
   explícitamente** — ni siquiera en modo de prueba/dry-run (ver memoria del
   proyecto). Dar el comando y dejar que el usuario lo corra.

6. **Verificar en el código real antes de asumir comportamiento**, en
   especial alrededor de: mecanismos de carga de Rails, feature flags, y
   cualquier interacción entre nuestro código y `enterprise/`. Este proyecto
   tiene varios casos ya encontrados donde la intuición llevó a conclusiones
   equivocadas (ver "Hallazgos" abajo) — siempre confirmar con grep/lectura
   directa o, si aplica, pidiendo al usuario que corra un comando de
   verificación por SSH contra `chat-dev`.

## Por qué esto importa (contexto de licencia)

El "candado" de Chatwoot Enterprise es solo de licencia y de UI — no hay
ningún check de licencia real en el backend. `ChatwootApp.enterprise?` solo
verifica que la carpeta `enterprise/` exista en el filesystem; si existiera y
se reutilizaran sus columnas/asociaciones, ese código licenciado se
ejecutaría de verdad en producción sin que nadie lo haya activado a
propósito. Por eso las reglas de arriba (especialmente la #1) no son
opcionales — son la única barrera real contra activar código con licencia
Enterprise sin querer.

## Hallazgos de arquitectura que ya causaron bugs reales (no repetir)

- Crear la carpeta `custom/` sin ningún archivo `.rb` real rompe el boot de
  **toda la app** (no solo lo custom) — el namespace `Custom` debe existir
  explícitamente (`custom/config/initializers/00_define_namespace.rb`).
- Anidar `resources :x do resources :y end` en `config/routes.rb` namespacea
  la URL pero no el controller — hace falta `scope module: :x do ... end`.
- `app/javascript/**` nunca tiene licencia Enterprise, aunque renderice
  features EE (ej. paywalls) — es seguro modificarlo libremente.
- El código de `enterprise/` se ejecuta siempre que la carpeta exista, sin
  importar ningún feature flag — la única defensa real es no compartir
  columnas/asociaciones con él (regla #1).

## Custom Roles (implementado, ver README.md para el detalle completo)

Reimplementación propia de Custom Roles: roles con permisos granulares
(`conversation_manage`, `conversation_unassigned_manage`,
`conversation_participating_manage`, `contact_manage`, `report_manage`,
`knowledge_base_manage`) asignables a agentes.

- **Feature flag**: `custom_roles_brandpatch` (`feature_flags_ext_1`,
  `enabled: true`, activable/desactivable por cuenta).
- **Columna/asociación propia**: `account_users.brandpatch_custom_role_id` /
  `belongs_to :brandpatch_custom_role` — nunca usar `custom_role_id` (es de
  Enterprise).
- **Estado**: completo y validado end-to-end en `chat-dev` (backend +
  frontend + los 6 permisos probados individualmente y combinados). Ver
  `README.md` → sección "Custom Roles" para el mapa de archivos exacto, los 2
  bugs de QA ya corregidos, y los comandos de verificación por SSH.
- **Antes de modificar algo de Custom Roles**: releer la sección
  correspondiente del README, y si se toca autorización de conversaciones,
  releer especialmente las reglas #2 y #3 de arriba — son las que causaron
  los bugs más difíciles de diagnosticar durante el desarrollo.

## SLA (implementado, ver README.md para el detalle completo)

Reimplementación propia de SLA de Chatwoot Enterprise: políticas con umbrales
de FRT, NRT y RT, evaluación por job programado, badge en tiempo real,
notificaciones a agentes, reportes, y asignación manual o via automatizaciones.

- **Feature flag**: `custom_sla` (`feature_flags_ext_1`, `enabled: false`,
  activable/desactivable por cuenta desde Super Admin → "SLA (Brandpatch)").
- **Sin columnas/tablas propias**: reutiliza `sla_policies`, `applied_slas` y
  `sla_events` de Enterprise — son modelos de Rails accedidos directamente,
  no a través de código `enterprise/`. Las rutas y controladores de SLA se
  desbloquean vía `custom/config/initializers/01_sla_controller_patches.rb`.
- **Flag propio es obligatorio**: el flag enterprise `sla` es desactivado
  automáticamente cada día por `ReconcilePlanConfigService` en instalaciones
  community. Por eso usamos `custom_sla` en `feature_flags_ext_1`, que ese
  servicio no toca.
- **Estado**: completo y validado end-to-end en `chat-dev` (políticas, badge,
  job de breach, business hours, reportes, automatizaciones, notificaciones,
  seguridad por flag, resistencia a reconciliación). Ver `README.md` → sección
  "SLA" para el mapa de archivos exacto, los bugs de QA ya corregidos, y los
  comandos de verificación.
- **Antes de modificar algo de SLA**: tener en cuenta que tanto
  `Enterprise::ActionService#add_sla` como el partial jbuilder de conversación
  tienen guards sobre el flag `sla` (enterprise) — cualquier funcionalidad
  nueva que dependa de esos puntos de extensión necesitará su propio override
  en `Custom::` siguiendo el mismo patrón ya establecido.
