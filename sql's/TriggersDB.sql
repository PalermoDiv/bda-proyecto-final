-- =============================================================================
-- TriggersDB.sql — Triggers automáticos de la base de datos AlzMonitor
-- Aplicar: psql -U alzadmin -d alzheimer -f TriggersDB.sql
-- =============================================================================
-- Contenido:
--   BLOQUE 1: fn_verificar_cobertura_zona + trg_cobertura_zona
--             (zona sin cuidador >30 min → alerta automática)
--   BLOQUE 2: fn_bateria_baja_gps + trg_bateria_baja_gps
--             (nivel_bateria <= 15 en lecturas_gps → alerta Batería crítica)
--   BLOQUE 3: fn_zona_exit_gps + trg_zona_exit_gps
--             (paciente fuera de todas sus zonas → alerta Salida de Zona)
-- =============================================================================


-- =============================================================================
-- BLOQUE 1: COBERTURA DE ZONA (activado desde BLOQUE 11 del DDL)
-- Dispara cada vez que se inserta una detección beacon. Recorre todas las zonas
-- con turno activo en ese momento y genera una alerta si alguna lleva más de
-- 30 minutos sin presencia de cuidador identificado.
-- =============================================================================

DROP TRIGGER IF EXISTS trg_cobertura_zona ON detecciones_beacon;
DROP FUNCTION IF EXISTS fn_verificar_cobertura_zona();

CREATE OR REPLACE FUNCTION fn_verificar_cobertura_zona()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    r_zona RECORD;
    v_ultima TIMESTAMP;
    v_id_alerta INTEGER;
    v_dow INTEGER;
BEGIN
    -- día de la semana del evento (0=domingo … 6=sábado en PostgreSQL)
    v_dow := EXTRACT(DOW FROM NEW.fecha_hora)::INTEGER;

    -- recorrer todas las zonas con turno activo en este instante
    FOR r_zona IN
        SELECT DISTINCT tc.id_zona
        FROM turno_cuidador tc
        WHERE tc.activo = TRUE
          AND tc.hora_inicio <= NEW.fecha_hora::TIME
          AND tc.hora_fin > NEW.fecha_hora::TIME
          AND (
              (v_dow = 1 AND tc.lunes) OR
              (v_dow = 2 AND tc.martes) OR
              (v_dow = 3 AND tc.miercoles) OR
              (v_dow = 4 AND tc.jueves) OR
              (v_dow = 5 AND tc.viernes) OR
              (v_dow = 6 AND tc.sabado) OR
              (v_dow = 0 AND tc.domingo)
          )
    LOOP
        -- última detección con cuidador identificado en esta zona (últimos 30 min)
        SELECT MAX(db.fecha_hora) INTO v_ultima
        FROM detecciones_beacon db
        JOIN beacon_zona bz ON db.id_dispositivo = bz.id_dispositivo
        WHERE bz.id_zona = r_zona.id_zona
          AND db.id_cuidador IS NOT NULL
          AND db.fecha_hora >= NEW.fecha_hora - INTERVAL '30 minutes';

        -- si no hubo presencia reciente, crear alerta (evitar duplicados activos)
        IF v_ultima IS NULL THEN
            IF NOT EXISTS (
                SELECT 1 FROM alertas
                WHERE id_zona = r_zona.id_zona
                  AND tipo_alerta = 'Zona sin cobertura'
                  AND estatus = 'Activa'
                  AND fecha_hora >= NEW.fecha_hora - INTERVAL '2 hours'
            ) THEN
                SELECT COALESCE(MAX(id_alerta), 0) + 1 INTO v_id_alerta FROM alertas;
                INSERT INTO alertas
                    (id_alerta, id_paciente, id_zona, tipo_alerta, fecha_hora, estatus)
                VALUES
                    (v_id_alerta, NULL, r_zona.id_zona,
                     'Zona sin cobertura', NEW.fecha_hora, 'Activa');
            END IF;
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cobertura_zona
AFTER INSERT ON detecciones_beacon
FOR EACH ROW EXECUTE FUNCTION fn_verificar_cobertura_zona();


-- =============================================================================
-- BLOQUE 2: BATERÍA BAJA GPS
-- Dispara cuando se inserta una lectura GPS con nivel_bateria <= 15.
-- Inserta alerta 'Batería Baja' + origen en alerta_evento_origen.
-- Evita duplicados: no crea nueva alerta si ya hay una activa reciente (2h).
-- =============================================================================

DROP TRIGGER IF EXISTS trg_bateria_baja_gps ON lecturas_gps;
DROP FUNCTION IF EXISTS fn_bateria_baja_gps();

CREATE OR REPLACE FUNCTION fn_bateria_baja_gps()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_id_paciente INTEGER;
    v_id_alerta INTEGER;
    v_id_origen INTEGER;
BEGIN
    -- Solo actuar cuando la batería es crítica
    IF NEW.nivel_bateria IS NULL OR NEW.nivel_bateria > 15 THEN
        RETURN NEW;
    END IF;

    -- Encontrar el paciente con ese dispositivo GPS activo
    SELECT ak.id_paciente INTO v_id_paciente
    FROM asignacion_kit ak
    WHERE ak.id_dispositivo_gps = NEW.id_dispositivo
      AND ak.fecha_fin IS NULL
    LIMIT 1;

    -- Sin paciente asignado — no hay a quién alertar
    IF v_id_paciente IS NULL THEN
        RETURN NEW;
    END IF;

    -- Evitar duplicados: ya existe alerta activa de batería en las últimas 2 horas
    IF EXISTS (
        SELECT 1 FROM alertas
        WHERE id_paciente = v_id_paciente
          AND tipo_alerta = 'Batería Baja'
          AND estatus = 'Activa'
          AND fecha_hora >= NEW.fecha_hora - INTERVAL '2 hours'
    ) THEN
        RETURN NEW;
    END IF;

    -- Insertar alerta
    SELECT COALESCE(MAX(id_alerta), 0) + 1 INTO v_id_alerta FROM alertas;
    INSERT INTO alertas (id_alerta, id_paciente, id_zona, tipo_alerta, fecha_hora, estatus)
    VALUES (v_id_alerta, v_id_paciente, NULL,
            'Batería Baja', NEW.fecha_hora, 'Activa');

    -- Registrar origen del evento
    SELECT COALESCE(MAX(id_origen), 0) + 1 INTO v_id_origen FROM alerta_evento_origen;
    INSERT INTO alerta_evento_origen
        (id_origen, id_alerta, tipo_evento, id_lectura_gps, regla_disparada)
    VALUES (v_id_origen, v_id_alerta, 'GPS', NEW.id_lectura,
            'Nivel de batería: ' || NEW.nivel_bateria || '% (umbral: 15%)');

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_bateria_baja_gps
AFTER INSERT ON lecturas_gps
FOR EACH ROW EXECUTE FUNCTION fn_bateria_baja_gps();


-- =============================================================================
-- BLOQUE 3: SALIDA DE ZONA GPS
-- Dispara en cada lectura GPS. Verifica si el punto está dentro de ALGUNA zona
-- activa del paciente usando PostGIS ST_DWithin. Si está fuera de todas → alerta.
-- Usa la sede actual del paciente para filtrar las zonas aplicables.
-- Evita duplicados: no crea nueva alerta si ya hay 'Salida de Zona' activa (1h).
-- =============================================================================

DROP TRIGGER IF EXISTS trg_zona_exit_gps ON lecturas_gps;
DROP FUNCTION IF EXISTS fn_zona_exit_gps();

CREATE OR REPLACE FUNCTION fn_zona_exit_gps()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_id_paciente INTEGER;
    v_id_sede INTEGER;
    v_dentro BOOLEAN;
    v_id_alerta INTEGER;
    v_id_origen INTEGER;
    v_zona_names TEXT;
BEGIN
    -- El punto debe tener coordenadas PostGIS para poder comparar
    IF NEW.geom IS NULL THEN
        RETURN NEW;
    END IF;

    -- Encontrar el paciente con ese dispositivo GPS activo
    SELECT ak.id_paciente INTO v_id_paciente
    FROM asignacion_kit ak
    WHERE ak.id_dispositivo_gps = NEW.id_dispositivo
      AND ak.fecha_fin IS NULL
    LIMIT 1;

    IF v_id_paciente IS NULL THEN
        RETURN NEW;
    END IF;

    -- Sede actual del paciente
    SELECT sp.id_sede INTO v_id_sede
    FROM sede_pacientes sp
    WHERE sp.id_paciente = v_id_paciente AND sp.fecha_salida IS NULL
    LIMIT 1;

    -- Verificar si el punto está dentro de ALGUNA zona de esa sede
    SELECT EXISTS (
        SELECT 1
        FROM zonas z
        JOIN sede_zonas szr ON szr.id_zona = z.id_zona
        WHERE szr.id_sede = v_id_sede
          AND ST_DWithin(
                NEW.geom::geography,
                z.geom::geography,
                z.radio_metros
              )
    ) INTO v_dentro;

    -- Está dentro — sin alerta
    IF v_dentro THEN
        RETURN NEW;
    END IF;

    -- Evitar duplicados: ya hay una alerta activa de salida de zona reciente (1h)
    IF EXISTS (
        SELECT 1 FROM alertas
        WHERE id_paciente = v_id_paciente
          AND tipo_alerta = 'Salida de Zona'
          AND estatus = 'Activa'
          AND fecha_hora >= NEW.fecha_hora - INTERVAL '1 hour'
    ) THEN
        RETURN NEW;
    END IF;

    -- Nombres de zonas disponibles (para la descripción)
    SELECT STRING_AGG(z.nombre_zona, ', ') INTO v_zona_names
    FROM zonas z
    JOIN sede_zonas szr ON szr.id_zona = z.id_zona
    WHERE szr.id_sede = v_id_sede;

    -- Insertar alerta
    SELECT COALESCE(MAX(id_alerta), 0) + 1 INTO v_id_alerta FROM alertas;
    INSERT INTO alertas (id_alerta, id_paciente, id_zona, tipo_alerta, fecha_hora, estatus)
    VALUES (v_id_alerta, v_id_paciente, NULL,
            'Salida de Zona', NEW.fecha_hora, 'Activa');

    -- Registrar origen
    SELECT COALESCE(MAX(id_origen), 0) + 1 INTO v_id_origen FROM alerta_evento_origen;
    INSERT INTO alerta_evento_origen
        (id_origen, id_alerta, tipo_evento, id_lectura_gps, regla_disparada)
    VALUES (v_id_origen, v_id_alerta, 'GPS', NEW.id_lectura,
            'Fuera de zona(s): ' || COALESCE(v_zona_names, 'Sin zonas configuradas') ||
            ' — Posición: ' || ROUND(NEW.latitud::NUMERIC, 5)::TEXT ||
            ', ' || ROUND(NEW.longitud::NUMERIC, 5)::TEXT);

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_zona_exit_gps
AFTER INSERT ON lecturas_gps
FOR EACH ROW EXECUTE FUNCTION fn_zona_exit_gps();


-- =============================================================================
-- BLOQUE 4: KIT GPS ÚNICO POR PACIENTE
-- Dispara antes de insertar en asignacion_kit.
-- Garantiza que un paciente no tenga dos GPS activos simultáneamente y que un
-- dispositivo GPS no esté asignado a más de un paciente a la vez.
-- =============================================================================

DROP TRIGGER IF EXISTS trg_kit_activo_unico ON asignacion_kit;
DROP FUNCTION IF EXISTS fn_kit_activo_unico();

CREATE OR REPLACE FUNCTION fn_kit_activo_unico()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM asignacion_kit
        WHERE id_paciente = NEW.id_paciente
          AND fecha_fin IS NULL
    ) THEN
        RAISE EXCEPTION 'El paciente % ya tiene un kit GPS activo asignado.', NEW.id_paciente;
    END IF;

    IF EXISTS (
        SELECT 1 FROM asignacion_kit
        WHERE id_dispositivo_gps = NEW.id_dispositivo_gps
          AND fecha_fin IS NULL
    ) THEN
        RAISE EXCEPTION 'El dispositivo GPS % ya está asignado a otro paciente activo.', NEW.id_dispositivo_gps;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_kit_activo_unico
BEFORE INSERT ON asignacion_kit
FOR EACH ROW EXECUTE FUNCTION fn_kit_activo_unico();


-- =============================================================================
-- BLOQUE 5: TURNO DE CUIDADOR SIN SOLAPAMIENTO
-- Dispara antes de insertar o actualizar en turno_cuidador.
-- Impide que un mismo cuidador tenga dos turnos activos con horas traslapadas
-- en al menos un día de la semana en común.
-- =============================================================================

DROP TRIGGER IF EXISTS trg_turno_solapado ON turno_cuidador;
DROP FUNCTION IF EXISTS fn_turno_solapado();

CREATE OR REPLACE FUNCTION fn_turno_solapado()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM turno_cuidador
        WHERE id_cuidador = NEW.id_cuidador
          AND activo = TRUE
          AND id_turno != COALESCE(NEW.id_turno, -1)
          AND (hora_inicio, hora_fin) OVERLAPS (NEW.hora_inicio, NEW.hora_fin)
          AND (
              (NEW.lunes     AND lunes)     OR
              (NEW.martes    AND martes)    OR
              (NEW.miercoles AND miercoles) OR
              (NEW.jueves    AND jueves)    OR
              (NEW.viernes   AND viernes)   OR
              (NEW.sabado    AND sabado)    OR
              (NEW.domingo   AND domingo)
          )
    ) THEN
        RAISE EXCEPTION
            'El cuidador % ya tiene un turno activo que se solapa en ese horario y día.',
            NEW.id_cuidador;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_turno_solapado
BEFORE INSERT OR UPDATE ON turno_cuidador
FOR EACH ROW EXECUTE FUNCTION fn_turno_solapado();


-- =============================================================================
-- BLOQUE 6: DISPOSITIVO GPS ASIGNABLE
-- Dispara antes de insertar en asignacion_kit.
-- Rechaza la asignación si el dispositivo GPS tiene estado 'Inactivo' o
-- 'Mantenimiento'; solo permite estado 'Activo'.
-- =============================================================================

DROP TRIGGER IF EXISTS trg_dispositivo_asignable ON asignacion_kit;
DROP FUNCTION IF EXISTS fn_dispositivo_asignable();

CREATE OR REPLACE FUNCTION fn_dispositivo_asignable()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_estado VARCHAR(20);
BEGIN
    SELECT estado INTO v_estado
    FROM dispositivos
    WHERE id_dispositivo = NEW.id_dispositivo_gps;

    IF v_estado IS NULL THEN
        RAISE EXCEPTION 'El dispositivo GPS % no existe.', NEW.id_dispositivo_gps;
    END IF;

    IF v_estado != 'Activo' THEN
        RAISE EXCEPTION
            'El dispositivo GPS % tiene estado "%" y no puede asignarse a un paciente.',
            NEW.id_dispositivo_gps, v_estado;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_dispositivo_asignable
BEFORE INSERT ON asignacion_kit
FOR EACH ROW EXECUTE FUNCTION fn_dispositivo_asignable();


-- =============================================================================
-- BLOQUE 7: RECETA SOLO PARA PACIENTE ACTIVO
-- Dispara antes de insertar en recetas.
-- Bloquea la creación de una receta si el paciente tiene estado 'Baja'.
-- =============================================================================

DROP TRIGGER IF EXISTS trg_receta_solo_paciente_activo ON recetas;
DROP FUNCTION IF EXISTS fn_receta_solo_paciente_activo();

CREATE OR REPLACE FUNCTION fn_receta_solo_paciente_activo()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_desc_estado VARCHAR(50);
BEGIN
    SELECT ep.desc_estado INTO v_desc_estado
    FROM pacientes p
    JOIN estados_paciente ep ON p.id_estado = ep.id_estado
    WHERE p.id_paciente = NEW.id_paciente;

    IF v_desc_estado = 'Baja' THEN
        RAISE EXCEPTION
            'No se puede crear una receta: el paciente % tiene estado "%".',
            NEW.id_paciente, v_desc_estado;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_receta_solo_paciente_activo
BEFORE INSERT ON recetas
FOR EACH ROW EXECUTE FUNCTION fn_receta_solo_paciente_activo();


-- =============================================================================
-- BLOQUE 8: CIERRE AUTOMÁTICO DE RECETA ANTERIOR
-- Dispara antes de insertar en recetas.
-- Cuando se crea una receta nueva para un paciente, cierra automáticamente
-- cualquier receta previa 'Activa', garantizando máximo una receta activa por
-- paciente sin depender de la capa de aplicación.
-- =============================================================================

DROP TRIGGER IF EXISTS trg_cerrar_receta_anterior ON recetas;
DROP FUNCTION IF EXISTS fn_cerrar_receta_anterior();

CREATE OR REPLACE FUNCTION fn_cerrar_receta_anterior()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    UPDATE recetas
    SET estado = 'Cerrada'
    WHERE id_paciente = NEW.id_paciente
      AND estado = 'Activa';

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cerrar_receta_anterior
BEFORE INSERT ON recetas
FOR EACH ROW EXECUTE FUNCTION fn_cerrar_receta_anterior();


-- =============================================================================
-- BLOQUE 9: AUDITORÍA DE CAMBIOS DE ESTADO DE PACIENTE
-- Dispara después de actualizar pacientes.
-- Registra en auditoria_pacientes cada cambio de id_estado, guardando el
-- estado anterior, el nuevo y el timestamp exacto del cambio.
-- =============================================================================

DROP TRIGGER IF EXISTS trg_auditoria_estado_paciente ON pacientes;
DROP FUNCTION IF EXISTS fn_auditoria_estado_paciente();
DROP TABLE IF EXISTS auditoria_pacientes;

CREATE TABLE auditoria_pacientes (
    id_auditoria      SERIAL PRIMARY KEY,
    id_paciente       INTEGER      NOT NULL,
    id_estado_ant     INTEGER,
    desc_estado_ant   VARCHAR(50),
    id_estado_nuevo   INTEGER,
    desc_estado_nuevo VARCHAR(50),
    fecha_cambio      TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION fn_auditoria_estado_paciente()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.id_estado IS DISTINCT FROM NEW.id_estado THEN
        INSERT INTO auditoria_pacientes
            (id_paciente,
             id_estado_ant,    desc_estado_ant,
             id_estado_nuevo,  desc_estado_nuevo,
             fecha_cambio)
        SELECT
            NEW.id_paciente,
            OLD.id_estado,  ep_ant.desc_estado,
            NEW.id_estado,  ep_nvo.desc_estado,
            NOW()
        FROM estados_paciente ep_ant
        CROSS JOIN estados_paciente ep_nvo
        WHERE ep_ant.id_estado = OLD.id_estado
          AND ep_nvo.id_estado = NEW.id_estado;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auditoria_estado_paciente
AFTER UPDATE ON pacientes
FOR EACH ROW EXECUTE FUNCTION fn_auditoria_estado_paciente();


-- =============================================================================
-- BLOQUE 10: AUDITORÍA DE RESOLUCIÓN DE ALERTAS
-- Dispara después de actualizar alertas.
-- Registra en auditoria_alertas cada cambio de estatus (p. ej. 'Activa' →
-- 'Atendida'), con el timestamp exacto, para trazabilidad clínica completa.
-- =============================================================================

DROP TRIGGER IF EXISTS trg_auditoria_resolucion_alerta ON alertas;
DROP FUNCTION IF EXISTS fn_auditoria_resolucion_alerta();
DROP TABLE IF EXISTS auditoria_alertas;

CREATE TABLE auditoria_alertas (
    id_auditoria  SERIAL PRIMARY KEY,
    id_alerta     INTEGER      NOT NULL,
    id_paciente   INTEGER,
    tipo_alerta   VARCHAR(30),
    estatus_ant   VARCHAR(20),
    estatus_nuevo VARCHAR(20),
    fecha_cambio  TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION fn_auditoria_resolucion_alerta()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.estatus IS DISTINCT FROM NEW.estatus THEN
        INSERT INTO auditoria_alertas
            (id_alerta, id_paciente, tipo_alerta,
             estatus_ant, estatus_nuevo, fecha_cambio)
        VALUES
            (NEW.id_alerta, NEW.id_paciente, NEW.tipo_alerta,
             OLD.estatus, NEW.estatus, NOW());
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auditoria_resolucion_alerta
AFTER UPDATE ON alertas
FOR EACH ROW EXECUTE FUNCTION fn_auditoria_resolucion_alerta();


-- =============================================================================
-- Confirmación
-- =============================================================================
DO $$
BEGIN
    RAISE NOTICE '✓ trg_cobertura_zona aplicado (beacon sin cuidador > 30 min)';
    RAISE NOTICE '✓ trg_bateria_baja_gps aplicado (nivel_bateria <= 15)';
    RAISE NOTICE '✓ trg_zona_exit_gps aplicado (PostGIS ST_DWithin)';
    RAISE NOTICE '✓ trg_kit_activo_unico aplicado (un GPS activo por paciente)';
    RAISE NOTICE '✓ trg_turno_solapado aplicado (turnos sin traslape por cuidador)';
    RAISE NOTICE '✓ trg_dispositivo_asignable aplicado (solo GPS Activo asignable)';
    RAISE NOTICE '✓ trg_receta_solo_paciente_activo aplicado (no recetas a paciente Baja)';
    RAISE NOTICE '✓ trg_cerrar_receta_anterior aplicado (cierre automático de receta previa)';
    RAISE NOTICE '✓ trg_auditoria_estado_paciente aplicado (tabla auditoria_pacientes)';
    RAISE NOTICE '✓ trg_auditoria_resolucion_alerta aplicado (tabla auditoria_alertas)';
END;
$$;
