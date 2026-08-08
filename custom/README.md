# custom/

Extensiones propias de BrandPatch a Chatwoot, construidas de forma independiente
a `enterprise/` (que permanece intacta y sin usar). Esta carpeta es donde va
**todo** desarrollo custom que hagamos de ahora en adelante — no solo Custom
Roles, sino también SLA y cualquier feature futura. Este README es un
documento vivo: cada vez que se agregue un desarrollo nuevo bajo `custom/`,
debería sumarse aquí su propia sección siguiendo el mismo formato.

## Índice

- [Por qué existe esta carpeta](#por-qué-existe-esta-carpeta)
- [Cómo se carga (mecanismo genérico, aplica a todo lo que se agregue acá)](#cómo-se-carga-mecanismo-genérico-aplica-a-todo-lo-que-se-agregue-acá)
- [Reglas de oro (aplican a cualquier desarrollo nuevo acá)](#reglas-de-oro-aprendidas-a-las-malas-aplican-a-cualquier-desarrollo-nuevo-acá)
- [Hallazgos importantes de arquitectura](#hallazgos-importantes-de-arquitectura)
- [Custom Roles](#custom-roles)
  - [Permisos soportados (idénticos a los de la referencia EE)](#permisos-soportados-idénticos-a-los-de-la-referencia-ee)
  - [Feature flag](#feature-flag)
  - [Columna y asociación propias](#columna-y-asociación-propias)
  - [Mapa de archivos (backend)](#mapa-de-archivos-backend)
  - [Mapa de archivos (frontend)](#mapa-de-archivos-frontend)
  - [Bugs encontrados durante el QA (ya corregidos)](#bugs-encontrados-durante-el-qa-ya-corregidos)
  - [Comandos útiles (SSH)](#comandos-útiles-ssh)
- [SLA](#sla)
  - [Feature flag](#feature-flag-1)
  - [Tablas reutilizadas (sin columnas propias)](#tablas-reutilizadas-sin-columnas-propias)
  - [Mapa de archivos (backend)](#mapa-de-archivos-backend-1)
  - [Mapa de archivos (frontend)](#mapa-de-archivos-frontend-1)
  - [Bugs encontrados durante el QA (ya corregidos)](#bugs-encontrados-durante-el-qa-ya-corregidos-1)
  - [Comandos útiles (SSH)](#comandos-útiles-ssh-1)

## Por qué existe esta carpeta

Chatwoot Community no incluye ciertas funcionalidades que sí vienen en la
versión Enterprise (pago). En vez de activar el código de `enterprise/` (lo
cual violaría la licencia Enterprise de Chatwoot, aunque el sistema no lo
impida técnicamente — ver "Hallazgos importantes" más abajo), reimplementamos
esas funcionalidades desde cero, con nuestro propio código, bajo esta carpeta.

## Cómo se carga (mecanismo genérico, aplica a todo lo que se agregue acá)

- `config/application.rb` agrega `custom/app/**`, `custom/lib` y
  `custom/listeners` a los `eager_load_paths`, espejando exactamente cómo se
  carga `enterprise/`.
- `custom/config/initializers/*.rb` se cargan igual que los de
  `enterprise/config/initializers`.
- Las clases namespaced bajo `Custom::` se auto-descubren mediante los mismos
  hooks `include_mod_with`/`prepend_mod_with` que usa `Enterprise::` (ver
  `ChatwootApp.extensions` en `lib/chatwoot_app.rb` y
  `config/initializers/01_inject_enterprise_edition_module.rb`).
- `ChatwootApp.custom?` (chequea que la carpeta `custom/` exista) es el
  equivalente a `ChatwootApp.enterprise?`. Las rutas propias van en
  `config/routes.rb` dentro de `if ChatwootApp.custom?`.
- El namespace `Custom` se define explícitamente en
  `custom/config/initializers/00_define_namespace.rb` — **no borrar este
  archivo**, sin él el boot de toda la app se rompe apenas la carpeta
  `custom/` existe (ver "Hallazgos importantes").

## Reglas de oro (aplican a cualquier desarrollo nuevo acá)

1. **Nunca reutilizar una columna o asociación que ya use `enterprise/`.**
   Si el nombre coincide (ej. `custom_role_id`, `custom_role`), el código
   Enterprise correspondiente puede "activarse" solo con nuestros datos, sin
   que lo hayamos llamado nosotros — viola el principio de no depender de
   código con licencia Enterprise. Usar siempre un nombre propio y distinto
   (ej. `brandpatch_custom_role_id`).

2. **Usar `class_name` explícito y absoluto (con `::` al inicio) en
   asociaciones de ActiveRecord** cuando el modelo vive bajo `Custom::`. Rails
   resuelve nombres de clase sin namespace de forma relativa al declarante
   primero — puede encontrar por error otro módulo nuestro (ej.
   `Custom::AccountUser`, que es un módulo de prepend, no un modelo) antes de
   caer al modelo real de nivel superior.

3. **Prefijar los métodos privados de módulos que se prependean sobre una
   clase core** (ej. `Custom::ConversationPolicy`) cuando la misma clase
   también tiene un módulo `Enterprise::` prependeado. Ruby resuelve llamadas
   sin receptor desde el frente de la cadena de ancestros — nombres iguales
   entre `Custom::` y `Enterprise::` hacen que el código de uno dependa
   silenciosamente de los métodos del otro.

4. **El código de `enterprise/` sigue ejecutándose siempre que la carpeta
   exista**, sin importar ningún feature flag. Nuestra única defensa es no
   compartir columnas/asociaciones con él (regla 1) — así queda como código
   inerte que nunca altera nada.

5. **Los feature flags nuevos van con `column: feature_flags_ext_1`**
   (`feature_flags` está al límite de 63/63) y con un `name` propio, distinto
   del equivalente de Enterprise — nunca reutilizar el flag original (ej.
   `custom_roles`, `sla`), porque `Internal::ReconcilePlanConfigService` los
   desactiva automáticamente todos los días vía cron para instalaciones en
   plan community.

6. **`enabled: true` en `config/features.yml` solo aplica a cuentas nuevas**
   (vía `ConfigLoader`, enganchado a `db:migrate`). Para que aplique también a
   cuentas que ya existen, hace falta una migración de datos explícita que
   recorra `Account.find_in_batches` y llame `enable_features!`.

## Hallazgos importantes de arquitectura

- **El "candado" de Enterprise es solo de licencia y UI, no técnico.**
  `ChatwootApp.enterprise?` únicamente chequea si la carpeta `enterprise/`
  existe; no hay ningún check de licencia en runtime. El paywall del
  frontend depende solo de un feature flag. Por eso es fácil "destapar"
  código Enterprise por accidente — de ahí la regla de oro #1.
- **`app/javascript/**` nunca tiene licencia Enterprise**, incluso los
  componentes que renderizan features EE (ej. el paywall de Custom Roles)
  viven bajo la licencia MIT raíz. Solo la carpeta `enterprise/` (backend
  Ruby) tiene su propia licencia distinta.
- **Crear la carpeta `custom/` vacía rompe el boot de toda la app.** El
  mecanismo de inyección de módulos de Chatwoot no está preparado para una
  extensión sin ningún archivo `.rb` real bajo ella (namespace `Custom` sin
  definir). Por eso existe `00_define_namespace.rb`.
- **Anidar `resources :x do resources :y end` en `config/routes.rb` no
  namespacea el controller**, solo la URL. Hace falta `scope module: :x do
  ... end` adentro para que Rails busque el controller en el módulo
  correcto.
- **`ActionController::ParamsWrapper` ya envuelve el body JSON** bajo el
  nombre del recurso automáticamente — el frontend puede mandar los atributos
  "pelados" sin envolver, `params.require(:recurso)` funciona igual.

## Custom Roles

Reimplementación propia de la funcionalidad "Custom Roles" de Chatwoot
Enterprise: permite crear roles con permisos granulares (más allá de
Agente/Administrador) y asignárselos a agentes.

### Permisos soportados (idénticos a los de la referencia EE)

`conversation_manage`, `conversation_unassigned_manage`,
`conversation_participating_manage`, `contact_manage`, `report_manage`,
`knowledge_base_manage`.

### Feature flag

`custom_roles_brandpatch` (`config/features.yml`, `column:
feature_flags_ext_1`, `enabled: true`). Activable/desactivable por cuenta
desde Super Admin → Accounts → editar cuenta → "Custom Roles (Brandpatch)",
o por consola:

```ruby
Account.find(ID).enable_features!('custom_roles_brandpatch')
Account.find(ID).disable_features!('custom_roles_brandpatch')
```

### Columna y asociación propias

`account_users.brandpatch_custom_role_id` / `belongs_to
:brandpatch_custom_role` — deliberadamente separadas de `custom_role_id`
(Enterprise) por la regla de oro #1.

### Mapa de archivos (backend)

| Archivo | Qué hace |
|---|---|
| `db/migrate/20260804180000_add_brandpatch_custom_role_to_account_users.rb` | Columna `brandpatch_custom_role_id` |
| `db/migrate/20260804190000_enable_custom_roles_brandpatch_for_existing_accounts.rb` | Backfill del flag para cuentas existentes |
| `custom/app/models/custom/custom_role.rb` | Modelo `Custom::CustomRole`, validaciones, callbacks de invalidación de caché |
| `custom/app/models/custom/concerns/account.rb` | `Account#brandpatch_custom_roles` |
| `custom/app/models/custom/concerns/account_user.rb` | `AccountUser#brandpatch_custom_role` |
| `custom/app/models/custom/account_user.rb` | Prepend de `permissions` (incluye los permisos del rol) y `filtered_unread_count_visibility_changed?` |
| `custom/app/policies/custom/custom_role_policy.rb` | CRUD del propio Custom Role, admin-only |
| `custom/app/policies/custom/conversation_policy.rb` | Jerarquía de permisos sobre acceso a una conversación puntual |
| `custom/app/policies/custom/contact_policy.rb`, `report_policy.rb`, `csat_survey_response_policy.rb`, `article_policy.rb`, `category_policy.rb`, `portal_policy.rb` | Aplican `contact_manage`, `report_manage`, `knowledge_base_manage` |
| `custom/app/services/custom/conversations/permission_filter_service.rb` | Filtra el listado de conversaciones según el rol |
| `custom/app/controllers/custom/api/v1/accounts/custom_roles_controller.rb` | CRUD vía API, scoping multi-tenant por `Current.account.brandpatch_custom_roles` |
| `custom/app/controllers/custom/api/v1/accounts/agents_controller.rb` | Asignar/quitar el rol al crear/editar un agente |
| `custom/app/views/custom/api/v1/accounts/custom_roles/*.jbuilder`, `custom/app/views/custom/api/v1/models/_custom_role.json.jbuilder` | Respuestas JSON del CRUD |
| `custom/app/views/custom/api/v1/models/_account_user.json.jbuilder` | Expone el rol en la respuesta del usuario logueado |
| `custom/app/views/custom/api/v1/conversations/partials/_conversation.json.jbuilder` | Campo `participating` (ver bugs encontrados) |
| `config/routes.rb` (bloque `if ChatwootApp.custom?`) | Rutas del CRUD |
| `app/views/api/v1/models/_agent.json.jbuilder` (línea agregada) | Expone `brandpatch_custom_role_id` en el listado de agentes |
| `app/views/api/v1/conversations/partials/_conversation.json.jbuilder` (línea agregada) | Llama al partial propio de arriba |
| `app/views/api/v1/models/_user.json.jbuilder` (línea agregada) | Llama al partial de `_account_user` propio |

### Mapa de archivos (frontend)

| Archivo | Qué hace |
|---|---|
| `app/javascript/dashboard/api/ApiClient.js` | Soporte para `options.custom` (prefijo `/custom`) |
| `app/javascript/dashboard/api/customRole.js` | Usa `custom: true` |
| `app/javascript/dashboard/routes/dashboard/settings/customRoles/Index.vue` | Paywall lee `custom_roles_brandpatch` |
| `app/javascript/dashboard/featureFlags.js` | `CUSTOM_ROLES_BRANDPATCH` (no está en `PREMIUM_FEATURES`) |
| `app/javascript/dashboard/routes/dashboard/settings/customRoles/customRole.routes.js` | Usa el flag propio |
| `app/javascript/dashboard/routes/dashboard/settings/agents/{AddAgent,EditAgent,Index}.vue` | Selector y listado usan `brandpatch_custom_role_id` |
| `app/javascript/dashboard/helper/permissionsHelper.js`, `store/modules/auth.js`, `components-next/sidebar/SidebarAccountSwitcher.vue` | Leen `brandpatch_custom_role_id` con fallback al campo viejo |
| `app/javascript/dashboard/store/modules/conversations/helpers.js` | `applyRoleFilter` considera `conversation.participating` |
| `app/javascript/dashboard/components/ChatList.vue` | Guarda contra condición de carrera en `loadMoreConversations` |

### Bugs encontrados durante el QA (ya corregidos)

1. **`applyRoleFilter` (frontend) nunca consideraba "soy participante"** para
   `conversation_participating_manage`, solo "soy assignee" — el backend sí lo
   permitía, pero el navegador escondía la conversación igual. Se agregó el
   campo `participating` al JSON de conversación.
2. **Condición de carrera entre el fetch de cambio de pestaña y el disparador
   de scroll infinito** cuando la lista visible es muy corta — generaba un
   parpadeo cargando/vacío en loop. Se agregó una guarda en
   `loadMoreConversations`.

### Comandos útiles (SSH)

Todos se corren por SSH contra la instancia con:
`docker exec -it chatwoot-rails-1 bundle exec rails runner "..."`.

**Confirmar que todo el mecanismo base está bien cableado:**
```ruby
puts ChatwootApp.custom?
puts ChatwootApp.extensions.inspect
puts Object.const_defined?(:Custom, false)
```

**Confirmar el flag para una cuenta:**
```ruby
account = Account.find(ID)
puts account.feature_enabled?('custom_roles_brandpatch')
```

**Ver qué conversaciones le permite ver el filtro a un agente puntual:**
```ruby
user = User.find_by(email: 'correo@ejemplo.com')
account = Account.find(ID)
account_user = account.account_users.find_by(user_id: user.id)
puts account_user.brandpatch_custom_role&.permissions

filtered = Conversations::PermissionFilterService.new(account.conversations, user, account).perform
filtered.each { |c| puts "id=#{c.id}, assignee_id=#{c.assignee_id.inspect}" }
```

**Ciclo de prueba completo (crea, asigna y limpia un rol de prueba sin dejar residuos):**
```ruby
account = Account.find(ID)
account_user = account.account_users.first
role = account.brandpatch_custom_roles.create!(name: 'QA Temporal', permissions: ['contact_manage'])
account_user.update!(brandpatch_custom_role_id: role.id)
account_user.reload
puts account_user.brandpatch_custom_role&.name
# limpieza
account_user.update!(brandpatch_custom_role_id: nil)
role.destroy!
```

**Confirmar el orden de la cadena de prepends (nuestro módulo debe ir primero):**
```ruby
puts ConversationPolicy.ancestors.first(3).inspect
puts Conversations::PermissionFilterService.ancestors.first(3).inspect
puts Api::V1::Accounts::AgentsController.ancestors.first(3).inspect
```

## SLA

Reimplementación propia de la funcionalidad SLA de Chatwoot Enterprise:
políticas con umbrales de FRT (First Response Time), NRT (Next Response Time)
y RT (Resolution Time), evaluación periódica por job, badge en tiempo real en
la UI, notificaciones a agentes asignados al incumplirse un umbral, reportes
en Informes → SLA, y soporte de business hours. La asignación de una política
puede hacerse manualmente desde el sidebar de conversación o automáticamente
via automatizaciones.

### Feature flag

`custom_sla` (`config/features.yml`, `column: feature_flags_ext_1`,
`enabled: false`). Activable/desactivable por cuenta desde Super Admin →
Accounts → editar cuenta → "SLA (Brandpatch)", o por consola:

```ruby
Account.find(ID).enable_features!('custom_sla')
Account.find(ID).disable_features!('custom_sla')
```

El flag se llama `custom_sla` y no `sla` deliberadamente: `sla` es desactivado
automáticamente cada día por `Internal::ReconcilePlanConfigService` en
instalaciones community. `custom_sla` usa `feature_flags_ext_1`, que ese
servicio no toca.

### Tablas reutilizadas (sin columnas propias)

No se crean tablas ni columnas nuevas. Se reutilizan las tablas de Enterprise:
`sla_policies`, `applied_slas` y `sla_events` — accedidas directamente como
modelos de Rails (`SlaPolicy`, `AppliedSla`, `SlaEvent`), sin pasar por ningún
código de `enterprise/`. Los controladores y rutas de SLA se desbloquean para
cuentas `custom_sla` vía el initializer `01_sla_controller_patches.rb`.

### Mapa de archivos (backend)

| Archivo | Qué hace |
|---|---|
| `config/features.yml` | Flag `custom_sla` en `feature_flags_ext_1` |
| `custom/config/initializers/01_sla_controller_patches.rb` | Desbloquea rutas y controladores enterprise de SLA para cuentas `custom_sla` |
| `custom/app/jobs/custom/trigger_scheduled_items_job.rb` | Hook diario que lanza el job de SLA para cuentas `custom_sla` |
| `custom/app/jobs/custom/sla/trigger_slas_for_accounts_job.rb` | Itera cuentas con `custom_sla` activo y lanza evaluación por cuenta |
| `custom/app/jobs/custom/sla/process_account_applied_slas_job.rb` | Procesa todos los `AppliedSla` abiertos de una cuenta |
| `custom/app/jobs/custom/sla/process_applied_sla_job.rb` | Evalúa un `AppliedSla` individual y crea `SlaEvent` + notificaciones si corresponde |
| `custom/app/services/custom/sla/evaluate_applied_sla_service.rb` | Override del servicio enterprise de evaluación, gateado por `custom_sla` |
| `custom/app/services/custom/sla/business_hours_service.rb` | Override del servicio enterprise de business hours para cálculo de tiempo hábil |
| `custom/app/services/custom/action_service.rb` | `Custom::ActionService#add_sla` — permite la acción "Añadir SLA" en automatizaciones para cuentas `custom_sla` (el servicio enterprise la bloquea tras el flag `sla`) |
| `custom/app/views/custom/api/v1/conversations/partials/_conversation.json.jbuilder` | Expone `applied_sla` y `sla_events` en la API para cuentas `custom_sla` (el partial enterprise los bloquea tras el flag `sla`) |
| `app/views/api/v1/conversations/partials/_conversation.json.jbuilder` (modificado) | Guard de `sla_policy_id` ampliado para incluir `custom_sla`; llama al partial propio |

### Mapa de archivos (frontend)

| Archivo | Qué hace |
|---|---|
| `app/javascript/dashboard/featureFlags.js` | Constante `CUSTOM_SLA` |
| `app/javascript/dashboard/api/inbox/conversation.js` | Método `updateSla` — PATCH con `sla_policy_id` |
| `app/javascript/dashboard/store/modules/conversations/actions.js` | Acción `assignSla` del store |
| `app/javascript/dashboard/routes/dashboard/conversation/ConversationAction.vue` | Selector de política SLA en el sidebar; muestra nombre si ya hay una asignada |
| `app/javascript/dashboard/i18n/locale/en/conversation.json` | Strings i18n para el selector y mensajes de éxito/error |
| `app/javascript/dashboard/routes/dashboard/settings/sla/sla.routes.js` | Ruta de configuración SLA desbloqueada para `custom_sla` |
| `app/javascript/dashboard/routes/dashboard/settings/profile/NotificationPreferences.vue` | Opciones de notificación SLA visibles cuando `custom_sla` o `sla` están activos |

### Bugs encontrados durante el QA (ya corregidos)

1. **`Enterprise::ActionService#add_sla` bloqueaba la acción de automatización**
   para cuentas `custom_sla` — el método tiene un guard `return unless
   @account.feature_enabled?('sla')` que lo hace silencioso. Corregido con
   `Custom::ActionService` que overridea `add_sla` para cuentas `custom_sla`
   y delega a `super` cuando el flag enterprise `sla` está activo.

2. **El partial jbuilder enterprise bloqueaba `applied_sla` y `sla_events`**
   en la respuesta de la API — los exponía solo para cuentas con flag `sla`.
   Corregido con el partial propio en `custom/app/views/...` y ampliando el
   guard de `sla_policy_id` en el partial base para incluir `custom_sla`.

### Comandos útiles (SSH)

Todos se corren contra la instancia con:
`docker compose exec rails bundle exec rails runner "..."`.

**Confirmar el flag para una cuenta:**
```ruby
puts Account.find(ID).feature_enabled?('custom_sla')
```

**Activar/desactivar manualmente:**
```ruby
Account.find(ID).enable_features!('custom_sla')
Account.find(ID).disable_features!('custom_sla')
```

**Correr el job de evaluación SLA manualmente:**
```ruby
Sla::TriggerSlasForAccountsJob.perform_now
```

**Verificar eventos SLA de una conversación:**
```ruby
conv = Conversation.find_by(display_id: NUMERO)
puts conv.sla_policy&.name
puts conv.applied_sla.inspect
conv.sla_events.each { |e| puts "#{e.event_type} | #{e.created_at}" }
```

**Verificar notificaciones SLA enviadas:**
```ruby
Notification.where(notification_type: %w[sla_missed_next_response sla_missed_resolution])
            .order(created_at: :desc).limit(10).each do |n|
  puts "#{n.notification_type} | user_id: #{n.user_id} | read: #{n.read_at.present?}"
end
```

**Confirmar que `ReconcilePlanConfigService` no desactiva el flag:**
```ruby
Internal::ReconcilePlanConfigService.new.perform
puts Account.find(ID).feature_enabled?('custom_sla') ? 'ACTIVO ✓' : 'DESACTIVADO ✗'
```
