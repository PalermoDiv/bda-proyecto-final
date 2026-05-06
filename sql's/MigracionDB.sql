-- =============================================================================
-- MigracionDB.sql — parches incrementales sobre la DB existente
-- Aplicar UNA VEZ, luego re-aplicar ViewsDB.sql
-- =============================================================================

-- 1. Columna id_gateway en detecciones_beacon
ALTER TABLE detecciones_beacon
    ADD COLUMN IF NOT EXISTS id_gateway VARCHAR(50) DEFAULT 'central';

-- 2. Tabla asignacion_beacon (beacon portado por el cuidador)
CREATE TABLE IF NOT EXISTS asignacion_beacon (
    id_asignacion  SERIAL PRIMARY KEY,
    id_dispositivo INTEGER NOT NULL,
    id_cuidador    INTEGER NOT NULL,
    fecha_inicio   DATE    NOT NULL DEFAULT CURRENT_DATE,
    fecha_fin      DATE,
    CONSTRAINT fk_ab_dispositivo FOREIGN KEY (id_dispositivo)
        REFERENCES dispositivos(id_dispositivo) ON DELETE RESTRICT,
    CONSTRAINT fk_ab_cuidador FOREIGN KEY (id_cuidador)
        REFERENCES cuidadores(id_empleado) ON DELETE RESTRICT,
    CONSTRAINT chk_ab_fechas CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_beacon_activo_por_cuidador
    ON asignacion_beacon (id_cuidador) WHERE fecha_fin IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_beacon_dispositivo_activo
    ON asignacion_beacon (id_dispositivo) WHERE fecha_fin IS NULL;

-- Seed: dispositivo 401 asignado al cuidador 1 (Juan Martínez)
INSERT INTO asignacion_beacon (id_dispositivo, id_cuidador, fecha_inicio)
SELECT 401, 1, '2026-03-01'
WHERE NOT EXISTS (SELECT 1 FROM asignacion_beacon WHERE id_dispositivo = 401 AND fecha_fin IS NULL);

-- 3. DROP de vistas con alias de columna incompatibles
--    (CREATE OR REPLACE no puede renombrar columnas existentes)
DROP VIEW IF EXISTS v_pacientes_activos CASCADE;
DROP VIEW IF EXISTS v_cuidadores        CASCADE;

DO $$
BEGIN
    RAISE NOTICE 'MigracionDB aplicada. Ahora re-aplica ViewsDB.sql.';
END;
$$;
