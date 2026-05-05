-- =============================================================================
-- BeaconProcedures.sql
-- AlzMonitor — Stored Procedures: Módulo Rondas de Cuidador (BLE Beacon)
-- Base de datos: alzheimer
--
-- Convenciones:
--   - LANGUAGE plpgsql, nombre sp_cuidador_<accion>
--   - IDs manuales (COALESCE(MAX,0)+1 — no hay SERIAL en detecciones_beacon)
--   - Errores con RAISE EXCEPTION — Flask los captura como excepciones
--   - El trigger trg_cobertura_zona se dispara automáticamente tras el INSERT
--
-- Para aplicar:
--   psql -U palermingoat -d alzheimer -f BeaconProcedures.sql
-- =============================================================================


-- =============================================================================
-- sp_cuidador_registrar_ronda
-- Registra la detección de un beacon BLE durante una ronda de cuidador.
--
-- Parámetros:
--   p_id_beacon    INTEGER  — dispositivos.id_dispositivo (tipo BEACON)
--   p_id_cuidador  INTEGER  — cuidadores.id_empleado (NULL si ronda anónima)
--   p_rssi         INTEGER  — señal en dBm; 0 si check-in manual sin BLE real
--
-- Inserta en: detecciones_beacon
-- Dispara:    trg_cobertura_zona (automáticamente tras el INSERT)
--
-- Precondiciones:
--   - p_id_beacon debe existir en dispositivos con tipo = 'BEACON'
--   - p_id_cuidador, si se proporciona, debe existir en cuidadores
--
-- Errores posibles:
--   - 'Beacon % no existe o no es de tipo BEACON.'
--   - 'Cuidador % no encontrado.'
-- =============================================================================
CREATE OR REPLACE PROCEDURE sp_cuidador_registrar_ronda(
    p_id_beacon INTEGER,
    p_id_cuidador INTEGER, -- NULL permitido (ronda anónima)
    p_rssi INTEGER -- 0 si check-in manual
)
LANGUAGE plpgsql AS $$
DECLARE
    v_id_deteccion INTEGER;
BEGIN
    -- Verificar que el beacon existe y es del tipo correcto
    IF NOT EXISTS (
        SELECT 1 FROM dispositivos
        WHERE id_dispositivo = p_id_beacon AND tipo = 'BEACON'
    ) THEN
        RAISE EXCEPTION 'Beacon % no existe o no es de tipo BEACON.', p_id_beacon;
    END IF;

    -- Verificar cuidador si se proporcionó
    IF p_id_cuidador IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM cuidadores WHERE id_empleado = p_id_cuidador
    ) THEN
        RAISE EXCEPTION 'Cuidador % no encontrado.', p_id_cuidador;
    END IF;

    -- Calcular siguiente ID manual
    SELECT COALESCE(MAX(id_deteccion), 0) + 1
    INTO v_id_deteccion
    FROM detecciones_beacon;

    -- Insertar detección — trg_cobertura_zona se dispara aquí automáticamente
    INSERT INTO detecciones_beacon (id_deteccion, id_dispositivo, id_cuidador, fecha_hora, rssi)
    VALUES (v_id_deteccion, p_id_beacon, p_id_cuidador, NOW(), p_rssi);

    RAISE NOTICE 'Ronda registrada: deteccion=%, beacon=%, zona será verificada por trigger.', v_id_deteccion, p_id_beacon;
END;
$$;
