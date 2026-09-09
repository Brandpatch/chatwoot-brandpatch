# Infraestructura autoalojada

Cómo está armado el entorno donde corre BrandPatch: qué máquinas hay, qué
corre en cada una, cómo se despliega y qué avisa cuando algo se rompe.

Vive en `custom/` a propósito: upstream no tiene esta carpeta, así que ningún
merge desde `chatwoot/chatwoot` la puede pisar.

> **Este documento es arquitectónico, no operativo.** No lleva direcciones IP,
> identificadores de instancia, rutas de credenciales ni estado de respaldos —
> el repositorio es público. Ese detalle lo tiene el equipo de infraestructura
> aparte; pedirlo cuando haga falta.

## Índice

- [Topología](#topología)
- [Dominios](#dominios)
- [Qué corre en cada máquina](#qué-corre-en-cada-máquina)
- [Cómo se despliega](#cómo-se-despliega)
- [Bases de datos y acceso](#bases-de-datos-y-acceso)
- [Sistema de avisos](#sistema-de-avisos)
- [Cosas que confunden](#cosas-que-confunden)

## Topología

Tres instancias EC2 con Ubuntu 24.04 LTS:

| entorno | qué aloja |
|---|---|
| **dev** | Chatwoot **y** Evolution API en la misma máquina |
| **prod chatwoot** | solo Chatwoot |
| **prod evolution** | solo Evolution API, en EC2 dedicado |

Dos diferencias entre dev y producción que ya causaron confusión:

- **En dev las dos aplicaciones conviven; en producción están separadas.** El
  servidor de Evolution en producción es fácil de olvidar porque no participa
  de ningún flujo de despliegue.
- **Dev está en una región de AWS distinta** (`us-east-2`) que las dos de
  producción (`us-east-1`). Importa para cualquier recurso regional: alarmas de
  CloudWatch, temas de SNS, funciones Lambda y snapshots se crean por región,
  así que cubrir las tres máquinas implica duplicar el andamiaje.

## Dominios

| dominio | entorno |
|---|---|
| `chat.mybrandpatch.com` | prod chatwoot |
| `chat-dev.mybrandpatch.com` | dev |
| `evo.mybrandpatch.com` | prod evolution |
| `evo-dev.mybrandpatch.com` | dev |

Certificados de Let's Encrypt con certbot, autenticador `nginx`. La renovación
es automática vía `certbot.timer`.

## Qué corre en cada máquina

**Chatwoot** — nginx termina TLS y hace proxy al contenedor de Rails. Los
servicios son los de [`docker-compose.production.yaml`](../docker-compose.production.yaml):
`base`, `rails`, `sidekiq`, `postgres` (imagen pgvector) y `redis`, con
volúmenes para datos de Postgres, Redis y `storage`.

**Evolution API** — nginx hace proxy al contenedor de la API, acompañado de su
propio Postgres y su propio Redis.

**dev** — ambas aplicaciones en la misma máquina, con **dos Redis separados**
(uno para Chatwoot y otro para Evolution) y un Postgres compartido.

## Cómo se despliega

GitHub Actions, dos flujos espejo:

| rama | imagen | destino | workflow |
|---|---|---|---|
| `develop` | `ghcr.io/brandpatch/chatwoot-brandpatch:test` | dev | [`deploy-development.yml`](../.github/workflows/deploy-development.yml) |
| `main` | `ghcr.io/brandpatch/chatwoot-brandpatch:latest` | prod chatwoot | [`deploy-production.yml`](../.github/workflows/deploy-production.yml) |

Cada uno construye la imagen y la empuja a GHCR, copia el compose por SCP y
entra por SSH para hacer `pull`, `up -d` y `rails db:migrate`.

Dos consecuencias que conviene tener presentes:

- **El `pull` nombra solo `rails` y `sidekiq`.** Postgres y Redis nunca se
  recrean en un despliegue, así que cambios en la configuración del daemon de
  Docker —la rotación de logs, por ejemplo— no los alcanzan hasta que alguien
  los recree a mano.
- **Evolution API no tiene despliegue automatizado.** Se administra a mano en
  su servidor.

## Bases de datos y acceso

Postgres y Redis corren **en contenedores en la misma máquina** que la
aplicación, con volúmenes locales. No hay RDS ni ElastiCache.

**Nunca se exponen al exterior.** Para conectarse a la base desde afuera, hacerlo
por túnel SSH; no abrir el puerto.

Los adjuntos de ActiveStorage **no viven en el disco de la máquina** sino en S3.
El correo saliente va por SMTP. Las credenciales de canal (Twilio, WhatsApp) no
están en variables de entorno: Chatwoot las guarda en la base, por inbox.

## Sistema de avisos

Los servidores avisan a un canal de Discord del equipo cuando algo necesita
atención. Tres capas:

| capa | qué mira | dónde corre |
|---|---|---|
| 1 | que la renovación de certificados falle, vía `OnFailure` de systemd | las tres |
| 2 | el certificado que cada dominio **sirve de verdad**, consultado desde afuera | solo dev |
| 3 | uso de disco, con umbrales de aviso y crítico | las tres |

Notas de diseño que importan si alguien las toca:

- **Hay un único punto de salida** (`brandpatch-notify`). Cambiar el destino de
  todos los avisos se hace en un solo lugar.
- **La capa 2 mira desde afuera a propósito.** Detecta el caso que desde el
  disco es invisible: que la renovación funcione pero nadie recargue nginx, y
  el navegador siga viendo un certificado vencido.
- **La capa 3 no avisa en cada corrida.** Guarda el nivel y solo habla cuando
  cambia, con un recordatorio diario mientras el problema siga. Corre cada
  hora, y sin eso serían dos docenas de mensajes por día hasta que nadie mire
  el canal.
- **Rotar el webhook de Discord deja mudos a los tres servidores** hasta que se
  actualice la configuración en cada uno. Son tres archivos y nada avisa si
  quedan viejos.

## Cosas que confunden

- **`chatwoot-base-1` aparece como `Exited (0)` y es lo normal.** Corre las
  migraciones al desplegar y termina. No es un contenedor caído.
- **En producción el compose es `docker-compose.production.yaml`**, no el
  nombre por defecto. Todo comando `docker compose` ahí necesita `-f`.
- **`docker ps` muestra "Up N days", que es tiempo desde el último reinicio, no
  desde la creación.** Para saber si un contenedor se recreó después de un
  cambio de configuración hay que mirar `docker inspect -f '{{.Created}}'`.
