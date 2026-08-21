# idemdd-deploy — Stack de producción (Portainer)

Stack de producción del proyecto **IDE-MDD** (GORE Madre de Dios), gestionado
por Portainer con auto-pull desde `ghcr.io/sgat-goremad/idemdd-backend` y
`idemdd-admin-frontend`.

## Arquitectura

```
                ┌────────────────────────────────────────────────────────┐
                │  Traefik (red `traefik`, externo)                     │
                │  - tls via Let's Encrypt (certresolver `ssl`)         │
                └───────┬─────────────────────────────┬──────────────────┘
                        │ HTTPS                       │ HTTPS
                        ▼                             ▼
        ┌───────────────────────────┐   ┌───────────────────────────────┐
        │  idemdd-frontend (nginx)  │   │  idemdd-api (.NET 10 + Tesseract)│
        │  React + Vite             │   │  ASP.NET Core 5000            │
        └───────────────────────────┘   └──────┬────────────────────────┘
                                              │ conexión interna
                                              ▼
                              ┌────────────────────────────┐
                              │  idemdd-postgres            │
                              │  postgis/postgis:16-3.4     │
                              │  puerto host 9006 → 5432    │
                              └────────────────────────────┘
                                              ▲
                                              │ HTTP (dentro de red)
                                              │
                              ┌────────────────────────────┐
                              │  GeoServer (externo)        │
                              │  https://ide.regionmadrededios.gob.pe/geoserver
                              └────────────────────────────┘
```

**Volúmenes nombrados:**
- `postgres_data` — `/var/lib/postgresql/data` (Postgres)
- `storage_data` — `/app/Storage` (archivos digitalizados)

## Configuración inicial

### 1. Crear la red de Traefik (si no existe)

```bash
docker network create traefik
```

### 2. Copiar `.env.example` y completar valores sensibles

```bash
cp .env.example .env
# Editar .env y completar: POSTGRES_PASSWORD, JWT_KEY, GEOSERVER_PASSWORD, etc.
```

**Importante:** el `.env` está en `.gitignore`, nunca se commitea.

### 3. Validar la config antes de desplegar

```bash
pwsh ./validate-yaml.ps1
```

(o `pwsh validate-yaml.ps1` desde la carpeta). El script valida sintaxis YAML
y que las env vars requeridas estén definidas.

### 4. Desplegar el stack en Portainer

- Stacks → Add stack → Repository
  - Repository URL: `https://github.com/sgat-goremad/idemdd-deploy`
  - Compose path: `docker-compose.yml`
  - Enable **"Automatic updates"** si querés que Portainer haga pull + redeploy
    cuando se actualice el repo
- Variables de entorno: pegar las del `.env` (Portainer las cifra en su store)

## Variables de entorno

| Variable | Default | Requerida | Notas |
|---|---|---|---|
| `POSTGRES_USER` | — | ✅ | Usuario Postgres |
| `POSTGRES_PASSWORD` | — | ✅ | Password Postgres (SECRET) |
| `POSTGRES_DB` | `idemdd` | ❌ | |
| `POSTGRES_HOST_PORT` | `9006` | ❌ | Puerto en el host para Postgres |
| `JWT_KEY` | — | ✅ | Clave de firma JWT (≥32 bytes) (SECRET) |
| `JWT_ISSUER` | — | ✅ | Issuer del JWT |
| `JWT_AUDIENCE` | — | ✅ | Audience del JWT |
| `OCR_ENABLED` | `true` | ❌ | Habilita OCR con Tesseract |
| `OCR_MAX_PAGES` | `10` | ❌ | |
| `OCR_MAX_CHARS` | `50000` | ❌ | |
| `OCR_TIMEOUT` | `00:02:00` | ❌ | Timeout por documento |
| `GEOSERVER_ENABLED` | `true` | ❌ | Master switch del módulo WFS |
| `GEOSERVER_BASE_URL` | — | ✅ | URL del GeoServer externo (sin trailing slash) |
| `GEOSERVER_USERNAME` | — | ✅ | Usuario admin de GeoServer |
| `GEOSERVER_PASSWORD` | — | ✅ | Password admin (SECRET) |
| `GEOSERVER_WORKSPACE_PREFIX` | `idemdd` | ❌ | Prefijo del nombre del workspace |
| `GEOSERVER_NAMESPACE_URI_TEMPLATE` | (default del código) | ❌ | Ver ⚠️ abajo |
| `GEOSERVER_DATASTORE_NAME` | (default del código) | ❌ | Ver ⚠️ abajo |
| `GEOSERVER_POSTGRES_CONNECTION_STRING` | (fallback a la del backend) | ❌ | Connection string dedicada para GeoServer |
| `GEOSERVER_REQUEST_TIMEOUT_SECONDS` | `30` | ❌ | |
| `TRAEFIK_NETWORK` | `traefik` | ❌ | Red de Traefik |
| `TRAEFIK_ENTRYPOINT` | `websecure` | ❌ | |
| `TRAEFIK_CERTRESOLVER` | `ssl` | ❌ | Resolver de Let's Encrypt |
| `REGISTRY` | `ghcr.io/sgat-goremad` | ❌ | |
| `API_TAG` | `latest` | ❌ | Tag de la imagen del backend |
| `FRONTEND_TAG` | `latest` | ❌ | Tag de la imagen del frontend |

## ⚠️ Bug conocido: `${VAR:-default}` con `{0}` y `{1}` en Portainer

**Síntoma:** en producción, `docker exec idemdd-api printenv | grep NamespaceUriTemplate`
muestra un valor **malformado**, aunque la UI de Portainer muestre el valor
correcto. Por ejemplo:

| UI de Portainer (correcto) | `printenv` en el contenedor (malformado) |
|---|---|
| `https://ide.regionmadrededios.gob.pe/idemdd/{0}_{1}/geo` (55 chars) | `https://ide.regionmadrededios.gob.pe/idemdd/{0}_{1}/geo_{1}/geo}` (64 chars) |
| `idemdd_postgis_{0}` (18 chars) | `idemdd_postgis_{0}}` (19 chars) |

**Causa:** Portainer (y Docker Compose v1 / v2 temprano) interpreta mal las
llaves `{` y `}` literales dentro del **default** de `${VAR:-default}`. El
parser de compose cuenta llaves de manera incorrecta y concatena fragmentos
del propio string al final, produciendo un template que `string.Format` no
puede parsear. El resultado: el handler del publish tira un `FormatException`
con `500 Internal Server Error` y stack trace críptico (`offset 64, Format
item ends prematurely`).

**Fix aplicado (jun-2026):** se quitaron los defaults inline en
`docker-compose.yml` para `GeoServer__NamespaceUriTemplate` y
`GeoServer__DatastoreName`. Ahora si la env var no está seteada, el
contenedor recibe `""` y el código C# usa el default propio:

| Env var | Default del código (GeoServerSettings) |
|---|---|
| `GeoServer__NamespaceUriTemplate` | `http://localhost/idemdd/{0}_{1}/geo` |
| `GeoServer__DatastoreName` | `idemdd_postgis_{0}` |

**Cómo verificar el fix después de un redeploy:**

```bash
docker exec idemdd-api printenv | grep -iE 'NamespaceUriTemplate|DatastoreName'
```

Debería mostrar:
```
GeoServer__NamespaceUriTemplate=
GeoServer__DatastoreName=
```
(vacías — el código usará sus defaults propios). Si ves basura, significa que
Portainer todavía tiene un valor viejo cacheado y hay que **eliminar y recrear
el contenedor**, no solo restart.

**Fix complementario (código):** los handlers de publish/unpublish ahora
validan el template con `GeoServerSettings.SafeFormat`, que traduce un
template malformado en un `ArgumentException` con el valor exacto y el
detalle del error, elevado a `BusinessRuleException` (HTTP 400) con un
mensaje claro para el operador. Nunca más un 500 críptico por typo en
env vars.

## Troubleshooting

### El publish en GeoServer devuelve 500 con "Format item ends prematurely"

1. Verificar el template activo en el contenedor:
   ```bash
   docker exec idemdd-api printenv | grep -iE 'NamespaceUriTemplate|DatastoreName'
   ```
2. Si muestra basura (caracteres extra concatenados), ver la sección de
   bug conocido arriba. Hay que **recrear** el contenedor en Portainer
   (NO solo restart).
3. Si muestra el valor correcto, el problema es de otro tipo. Ver logs:
   ```bash
   docker logs --tail 200 idemdd-api | grep -A 30 'publish'
   ```

### El healthcheck del contenedor api falla

```bash
docker inspect idemdd-api --format '{{.State.Health.Status}}'
docker inspect idemdd-api --format '{{range .State.Health.Log}}{{println .Output}}{{end}}' | tail -20
```

Si el `start-period=60s` no es suficiente (BD tarda más en arrancar en
composición nueva), el healthcheck queda en `starting` hasta que `db`
termine. Esperá o reiniciá el contenedor `api` después de que `db` esté
`healthy`.

### Postgres no arranca después de un restore

Si el directorio `postgres_data` tiene un PG_VERSION distinto al de la
imagen actual, Postgres se niega a arrancar. Solución: backup + recreate
del volumen `postgres_data` (⚠️ borra todos los datos).

### GeoServer devuelve 401 al intentar crear el datastore

`GeoServer__Password` está vacío. Verificar con `printenv` y completar
en Portainer.

## Archivos del directorio

```
idemdd-deploy/
├── docker-compose.yml       # Stack principal (api, db, frontend)
├── .env.example             # Template de variables de entorno
├── .env                     # (gitignored) Config real
├── .gitignore               # .env, *.local, *.log
├── README.md                # Este archivo
├── validate-yaml.ps1        # Helper de validación local
└── postgres/
    └── init/
        └── 01-extensions.sql # Extensiones Postgres (postgis, etc.)
```
