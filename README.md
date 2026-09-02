# idemdd-deploy

Stack de producción del proyecto **IDE-MDD** (GORE Madre de Dios),
gestionado por Portainer con auto-pull desde
`ghcr.io/sgat-goremad/idemdd-backend` y `idemdd-admin-frontend`.

## Componentes

| Servicio  | Imagen                                          | Descripción                              |
|-----------|-------------------------------------------------|------------------------------------------|
| `db`      | `postgis/postgis:16-3.4-alpine`                 | PostgreSQL 16 + PostGIS                  |
| `api`     | `ghcr.io/sgat-goremad/idemdd-backend`           | WebApi .NET 10 + Tesseract               |
| `frontend`| `ghcr.io/sgat-goremad/idemdd-admin-frontend`    | React + Vite (nginx)                     |

Todos los servicios están en la red externa `traefik` (la misma donde corre
Traefik con Let's Encrypt). El routing público a `api` y `frontend` lo hace
Traefik vía `Host(...)` rules; la BD no se expone públicamente.

> **Storage / MinIO**: el servicio de object storage corre en un stack
> aparte (`idemdd-minio-prod`) y se consume desde el `api` por DNS a través
> de la red `traefik` compartida. No está definido en este compose.

> **Documentación operativa detallada**: variables de entorno, troubleshooting
> paso a paso, credenciales, URLs internas y procedimientos de despliegue
> viven en `DESPLIEGUE_PRODUCCION.md` (doc interno, no versionado en este
> repo). Este `README.md` es la referencia pública mínima.

## Configuración

Las variables de entorno se definen en la UI del stack en Portainer
(cifradas en su store). El compose usa defaults seguros con
`${VAR:-default}` para todas las no sensibles.

**Referencia completa de variables**: ver [`.env.example`](.env.example).

**Set mínimo requerido para arrancar el stack:**

| Variable | Notas |
|---|---|
| `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` | BD (SECRETS) |
| `JWT_KEY` (≥32 bytes), `JWT_ISSUER`, `JWT_AUDIENCE` | Auth (SECRETS) |
| `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD` | Deben coincidir con el stack `idemdd-minio-prod` (SECRETS) |

## Despliegue

### Automático (recomendado)

1. Push a `main` del repo `sgat-goremad/idemdd-backend` (o
   `idemdd-admin-frontend`).
2. GitHub Actions construye la imagen, la sube a GHCR y llama a la
   API de Portainer para hacer redeploy con `pullImage: true`.
3. Verificar en la pestaña **Actions** del repo que el step
   *Trigger Portainer redeploy* termine en verde.

### Manual (Portainer)

`Stacks → idemdd → Update → Pull and redeploy`. Útil cuando se cambian
variables de entorno del stack o el compose en este repo.

## ⚠️ Bug conocido: `${VAR:-default}` con `{0}` y `{1}` en Portainer

**Síntoma:** en producción, `docker exec idemdd-api printenv | grep
NamespaceUriTemplate` muestra un valor **malformado**, aunque la UI de
Portainer muestre el valor correcto. Por ejemplo:

| UI de Portainer (correcto) | `printenv` en el contenedor (malformado) |
|---|---|
| `https://ide.regionmadrededios.gob.pe/idemdd/{0}_{1}/geo` (55 chars) | `https://ide.regionmadrededios.gob.pe/idemdd/{0}_{1}/geo_{1}/geo}` (64 chars) |
| `idemdd_postgis_{0}` (18 chars) | `idemdd_postgis_{0}}` (19 chars) |

**Causa:** Portainer (y Docker Compose v1 / v2 temprano) interpreta mal las
llaves `{` y `}` literales dentro del **default** de `${VAR:-default}`.
El parser concatena fragmentos del propio string al final, produciendo
un template que `string.Format` no puede parsear. El handler de publish
tira un `FormatException` con 500 y stack trace críptico
(`offset 64, Format item ends prematurely`).

**Mitigación:** no usar `{0}` / `{1}` en defaults inline de env vars del
compose. Si el operador no setea la variable, el contenedor recibe `""`
y el código C# usa su default propio. Este compose ya evita ese patrón
para las env vars afectadas.

## Solución de problemas

Para troubleshooting detallado (conexiones al server, comandos de
diagnóstico, credenciales, networking entre stacks, manejo de MinIO y
backups, etc.) ver `DESPLIEGUE_PRODUCCION.md` (doc interno).

## Archivos

```
idemdd-deploy/
├── docker-compose.yml       # Stack principal (db, api, frontend)
├── .env.example             # Template de variables de entorno
├── .env                     # (gitignored) Config real
├── .gitignore               # .env, *.local, *.log
├── README.md                # Este archivo (público)
└── postgres/
    └── init/
        └── 01-extensions.sql # Extensiones Postgres (postgis, ltree)
```
