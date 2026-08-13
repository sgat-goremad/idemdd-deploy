-- ============================================================
-- 01-extensions.sql — extensiones de PostgreSQL
--
-- Se ejecuta SOLO la primera vez que se inicializa el volumen
-- (mecanismo /docker-entrypoint-initdb.d del contenedor).
-- Para volúmenes ya existentes ejecutar manualmente (ver
-- DESPLIEGUE_LOCAL.md).
-- ============================================================

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_raster;
CREATE EXTENSION IF NOT EXISTS ltree;
