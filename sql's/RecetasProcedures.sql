-- =============================================================================
-- RecetasProcedures.sql
-- AlzMonitor — Stored Procedures: Módulo Recetas + NFC
-- Base de datos: alzheimer
--
-- Convenciones:
--   - LANGUAGE plpgsql, nombres sp_receta_<accion>
--   - IDs manuales (no hay SERIAL en las tablas clave)
--   - Errores con RAISE EXCEPTION — Flask los captura como excepciones
--   - Cada procedure opera dentro de una transacción implícita
--
-- Para aplicar:
--   psql -U palermingoat -d alzheimer -f RecetasProcedures.sql
-- =============================================================================


-- =============================================================================
-- BLOQUE 1: GESTIÓN DE RECETAS
-- =============================================================================

-- Crea una nueva receta vacía para un paciente.
-- Inserta en: recetas
-- Precondiciones: id_paciente debe existir y no estar dado de baja (id_estado != 3)
CREATE OR REPLACE PROCEDURE sp_receta_crear(
    p_id_receta INTEGER, -- PK manual
    p_id_paciente INTEGER,
    p_fecha DATE
)
LANGUAGE plpgsql AS $$
BEGIN
    -- Verificar que el paciente existe y está activo
    IF NOT EXISTS (
        SELECT 1 FROM pacientes
        WHERE id_paciente = p_id_paciente AND id_estado != 3
    ) THEN
        RAISE EXCEPTION 'Paciente % no encontrado o dado de baja.', p_id_paciente;
    END IF;

    -- Verificar que el ID de receta no esté en uso
    IF EXISTS (SELECT 1 FROM recetas WHERE id_receta = p_id_receta) THEN
        RAISE EXCEPTION 'Ya existe una receta con ID %.', p_id_receta;
    END IF;

    INSERT INTO recetas (id_receta, fecha, id_paciente)
    VALUES (p_id_receta, p_fecha, p_id_paciente);
END;
$$;


-- Agrega un medicamento a una receta existente.
-- Inserta en: receta_medicamentos
-- Precondiciones: receta y medicamento (gtin) deben existir
CREATE OR REPLACE PROCEDURE sp_receta_agregar_medicamento(
    p_id_detalle INTEGER, -- PK manual de receta_medicamentos
    p_id_receta INTEGER,
    p_gtin VARCHAR, -- FK a medicamentos.gtin
    p_dosis VARCHAR, -- ej. '10mg'
    p_frecuencia_horas INTEGER -- ej. 8, 12, 24
)
LANGUAGE plpgsql AS $$
BEGIN
    -- Verificar que la receta existe
    IF NOT EXISTS (SELECT 1 FROM recetas WHERE id_receta = p_id_receta) THEN
        RAISE EXCEPTION 'Receta % no encontrada.', p_id_receta;
    END IF;

    -- Verificar que el medicamento existe
    IF NOT EXISTS (SELECT 1 FROM medicamentos WHERE gtin = p_gtin) THEN
        RAISE EXCEPTION 'Medicamento con GTIN % no encontrado.', p_gtin;
    END IF;

    -- Verificar frecuencia válida
    IF p_frecuencia_horas <= 0 THEN
        RAISE EXCEPTION 'La frecuencia debe ser mayor a cero horas.';
    END IF;

    INSERT INTO receta_medicamentos (id_detalle, id_receta, gtin, dosis, frecuencia_horas)
    VALUES (p_id_detalle, p_id_receta, p_gtin, p_dosis, p_frecuencia_horas);
END;
$$;


-- Elimina un medicamento de una receta.
-- Borra de: receta_medicamentos
-- Precondiciones: el detalle debe pertenecer a la receta indicada
CREATE OR REPLACE PROCEDURE sp_receta_quitar_medicamento(
    p_id_detalle INTEGER,
    p_id_receta INTEGER
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM receta_medicamentos
        WHERE id_detalle = p_id_detalle AND id_receta = p_id_receta
    ) THEN
        RAISE EXCEPTION 'Detalle % no encontrado en receta %.', p_id_detalle, p_id_receta;
    END IF;

    DELETE FROM receta_medicamentos
    WHERE id_detalle = p_id_detalle AND id_receta = p_id_receta;
END;
$$;


-- Actualiza la dosis o frecuencia de un medicamento en una receta.
-- Modifica: receta_medicamentos
CREATE OR REPLACE PROCEDURE sp_receta_actualizar_medicamento(
    p_id_detalle INTEGER,
    p_id_receta INTEGER,
    p_dosis VARCHAR,
    p_frecuencia_horas INTEGER
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM receta_medicamentos
        WHERE id_detalle = p_id_detalle AND id_receta = p_id_receta
    ) THEN
        RAISE EXCEPTION 'Detalle % no encontrado en receta %.', p_id_detalle, p_id_receta;
    END IF;

    IF p_frecuencia_horas <= 0 THEN
        RAISE EXCEPTION 'La frecuencia debe ser mayor a cero horas.';
    END IF;

    UPDATE receta_medicamentos
    SET dosis = p_dosis,
        frecuencia_horas = p_frecuencia_horas
    WHERE id_detalle = p_id_detalle AND id_receta = p_id_receta;
END;
$$;


-- =============================================================================
-- BLOQUE 2: GESTIÓN DE PULSERAS NFC
-- =============================================================================

-- Vincula un dispositivo NFC a una receta (inicia gestión de adherencia).
-- Inserta en: receta_nfc
-- Regla: una receta sólo puede tener un NFC activo a la vez
--        (uq_nfc_activo_por_receta). Verificar antes de insertar.
CREATE OR REPLACE PROCEDURE sp_receta_activar_nfc(
    p_id_receta INTEGER,
    p_id_dispositivo INTEGER, -- debe ser tipo NFC
    p_fecha_inicio DATE
)
LANGUAGE plpgsql AS $$
BEGIN
    -- Verificar que la receta existe
    IF NOT EXISTS (SELECT 1 FROM recetas WHERE id_receta = p_id_receta) THEN
        RAISE EXCEPTION 'Receta % no encontrada.', p_id_receta;
    END IF;

    -- Verificar que el dispositivo es de tipo NFC
    IF NOT EXISTS (
        SELECT 1 FROM dispositivos
        WHERE id_dispositivo = p_id_dispositivo AND tipo = 'NFC'
    ) THEN
        RAISE EXCEPTION 'El dispositivo % no es de tipo NFC o no existe.', p_id_dispositivo;
    END IF;

    -- Verificar que la receta no tiene ya un NFC activo
    IF EXISTS (
        SELECT 1 FROM receta_nfc
        WHERE id_receta = p_id_receta AND fecha_fin_gestion IS NULL
    ) THEN
        RAISE EXCEPTION 'La receta % ya tiene un dispositivo NFC activo. Ciérralo primero.', p_id_receta;
    END IF;

    INSERT INTO receta_nfc (id_receta, id_dispositivo, fecha_inicio_gestion, fecha_fin_gestion)
    VALUES (p_id_receta, p_id_dispositivo, p_fecha_inicio, NULL);
END;
$$;


-- Cierra la gestión NFC activa de una receta (fin de adherencia con ese dispositivo).
-- Modifica: receta_nfc (fecha_fin_gestion)
-- Útil cuando se cambia de pulsera o el paciente se da de baja.
CREATE OR REPLACE PROCEDURE sp_receta_cerrar_nfc(
    p_id_receta INTEGER,
    p_id_dispositivo INTEGER,
    p_fecha_fin DATE
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM receta_nfc
        WHERE id_receta = p_id_receta
          AND id_dispositivo = p_id_dispositivo
          AND fecha_fin_gestion IS NULL
    ) THEN
        RAISE EXCEPTION 'No hay vínculo NFC activo entre receta % y dispositivo %.', p_id_receta, p_id_dispositivo;
    END IF;

    UPDATE receta_nfc
    SET fecha_fin_gestion = p_fecha_fin
    WHERE id_receta = p_id_receta
      AND id_dispositivo = p_id_dispositivo
      AND fecha_fin_gestion IS NULL;
END;
$$;


-- Sustituye el dispositivo NFC de una receta en un solo paso atómico.
-- Cierra el vínculo actual e inicia uno nuevo.
-- Modifica: receta_nfc (UPDATE + INSERT)
CREATE OR REPLACE PROCEDURE sp_receta_cambiar_nfc(
    p_id_receta INTEGER,
    p_id_dispositivo_nuevo INTEGER,
    p_fecha_cambio DATE
)
LANGUAGE plpgsql AS $$
DECLARE
    v_dispositivo_actual INTEGER;
BEGIN
    -- Obtener el dispositivo NFC activo actual
    SELECT id_dispositivo INTO v_dispositivo_actual
    FROM receta_nfc
    WHERE id_receta = p_id_receta AND fecha_fin_gestion IS NULL;

    IF v_dispositivo_actual IS NULL THEN
        RAISE EXCEPTION 'La receta % no tiene un NFC activo para reemplazar.', p_id_receta;
    END IF;

    -- Verificar que el nuevo dispositivo es NFC
    IF NOT EXISTS (
        SELECT 1 FROM dispositivos
        WHERE id_dispositivo = p_id_dispositivo_nuevo AND tipo = 'NFC'
    ) THEN
        RAISE EXCEPTION 'El dispositivo % no es de tipo NFC o no existe.', p_id_dispositivo_nuevo;
    END IF;

    -- Cerrar el vínculo actual
    UPDATE receta_nfc
    SET fecha_fin_gestion = p_fecha_cambio
    WHERE id_receta = p_id_receta AND id_dispositivo = v_dispositivo_actual
      AND fecha_fin_gestion IS NULL;

    -- Abrir el nuevo vínculo
    INSERT INTO receta_nfc (id_receta, id_dispositivo, fecha_inicio_gestion, fecha_fin_gestion)
    VALUES (p_id_receta, p_id_dispositivo_nuevo, p_fecha_cambio, NULL);
END;
$$;


-- =============================================================================
-- BLOQUE 3: LECTURAS NFC (adherencia terapéutica)
-- =============================================================================

-- Registra una lectura NFC de administración de medicamento.
-- Inserta en: lecturas_nfc
-- Llamado por el endpoint POST /api/nfc/lectura cuando el cuidador
-- toca la pulsera del paciente con su teléfono (Web NFC API).
CREATE OR REPLACE PROCEDURE sp_nfc_registrar_lectura(
    p_id_lectura_nfc INTEGER,
    p_id_dispositivo INTEGER,
    p_id_receta INTEGER,
    p_fecha_hora TIMESTAMP,
    p_tipo_lectura VARCHAR, -- 'Administración' | 'Verificación'
    p_resultado VARCHAR -- 'Exitosa' | 'Fallida'
)
LANGUAGE plpgsql AS $$
BEGIN
    -- Verificar que el vínculo NFC–receta existe y está activo
    IF NOT EXISTS (
        SELECT 1 FROM receta_nfc
        WHERE id_receta = p_id_receta
          AND id_dispositivo = p_id_dispositivo
          AND fecha_fin_gestion IS NULL
    ) THEN
        RAISE EXCEPTION 'No hay vínculo NFC activo entre receta % y dispositivo %.', p_id_receta, p_id_dispositivo;
    END IF;

    -- Verificar que el tipo_lectura es válido
    IF p_tipo_lectura NOT IN ('Administración', 'Verificación') THEN
        RAISE EXCEPTION 'tipo_lectura inválido: %. Usar Administración o Verificación.', p_tipo_lectura;
    END IF;

    -- Verificar que el resultado es válido
    IF p_resultado NOT IN ('Exitosa', 'Fallida') THEN
        RAISE EXCEPTION 'resultado inválido: %. Usar Exitosa o Fallida.', p_resultado;
    END IF;

    INSERT INTO lecturas_nfc
        (id_lectura_nfc, id_dispositivo, id_receta, fecha_hora, tipo_lectura, resultado)
    VALUES
        (p_id_lectura_nfc, p_id_dispositivo, p_id_receta, p_fecha_hora, p_tipo_lectura, p_resultado);
END;
$$;


-- =============================================================================
-- BLOQUE 4: OPERACIONES DE CIERRE
-- =============================================================================

-- Cierra completamente una receta: cierra el NFC activo (si lo tiene)
-- y marca todos los vínculos NFC como finalizados.
-- Útil cuando el paciente completa su tratamiento o cambia de esquema.
-- Modifica: receta_nfc
-- NOTA: No elimina la receta para preservar el historial.
CREATE OR REPLACE PROCEDURE sp_receta_cerrar(
    p_id_receta INTEGER,
    p_fecha_fin DATE
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM recetas WHERE id_receta = p_id_receta) THEN
        RAISE EXCEPTION 'Receta % no encontrada.', p_id_receta;
    END IF;

    -- Cerrar todos los vínculos NFC activos de esta receta
    UPDATE receta_nfc
    SET fecha_fin_gestion = p_fecha_fin
    WHERE id_receta = p_id_receta AND fecha_fin_gestion IS NULL;

    -- (Opcional) Si en el futuro la tabla recetas tiene campo activo/inactivo,
    -- aquí se haría el UPDATE correspondiente.
END;
$$;


-- =============================================================================
-- BLOQUE 5: ASIGNACIÓN DIRECTA NFC ↔ PACIENTE
-- =============================================================================

-- Asigna (o reasigna) un dispositivo NFC a un paciente.
-- Cierra cualquier asignación activa previa del paciente o del dispositivo,
-- luego abre una nueva en asignacion_nfc.
CREATE OR REPLACE PROCEDURE sp_nfc_asignar(
    p_id_paciente INTEGER,
    p_id_dispositivo INTEGER
)
LANGUAGE plpgsql AS $$
BEGIN
    -- Verificar que el paciente existe y no está dado de baja
    IF NOT EXISTS (
        SELECT 1 FROM pacientes
        WHERE id_paciente = p_id_paciente AND id_estado != 3
    ) THEN
        RAISE EXCEPTION 'Paciente % no encontrado o dado de baja.', p_id_paciente;
    END IF;

    -- Verificar que el dispositivo es de tipo NFC y existe
    IF NOT EXISTS (
        SELECT 1 FROM dispositivos
        WHERE id_dispositivo = p_id_dispositivo AND tipo = 'NFC'
    ) THEN
        RAISE EXCEPTION 'Dispositivo % no es de tipo NFC o no existe.', p_id_dispositivo;
    END IF;

    -- Cerrar asignación activa del paciente (si tiene una)
    UPDATE asignacion_nfc
    SET fecha_fin = CURRENT_DATE
    WHERE id_paciente = p_id_paciente AND fecha_fin IS NULL;

    -- Cerrar asignación activa del dispositivo (si está asignado a otro paciente)
    UPDATE asignacion_nfc
    SET fecha_fin = CURRENT_DATE
    WHERE id_dispositivo = p_id_dispositivo AND fecha_fin IS NULL;

    -- Crear nueva asignación
    INSERT INTO asignacion_nfc (id_paciente, id_dispositivo, fecha_inicio)
    VALUES (p_id_paciente, p_id_dispositivo, CURRENT_DATE);
END;
$$;


-- =============================================================================
-- FIN RecetasProcedures.sql
-- Para verificar que los procedures se cargaron correctamente:
--   SELECT proname FROM pg_proc WHERE proname LIKE 'sp_receta%' OR proname LIKE 'sp_nfc%';
-- =============================================================================
