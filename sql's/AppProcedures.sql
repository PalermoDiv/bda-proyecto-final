-- AppProcedures.sql
-- DML stored procedures for app.py routes
-- Apply: psql -U alzadmin -d alzheimer -f AppProcedures.sql

-- ─────────────────────────────────────────────────────────────────────────────
-- PACIENTES
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_ins_paciente(
    p_id_paciente INT,
    p_nombre VARCHAR,
    p_apellido_p VARCHAR,
    p_apellido_m VARCHAR,
    p_fecha_nacimiento DATE,
    p_id_estado INT,
    p_id_sede INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_next_sp INT;
BEGIN
    IF EXISTS (SELECT 1 FROM pacientes WHERE id_paciente = p_id_paciente) THEN
        RAISE EXCEPTION 'Ya existe un paciente con ID %.', p_id_paciente;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM estados_paciente WHERE id_estado = p_id_estado) THEN
        RAISE EXCEPTION 'Estado % no existe en el catálogo.', p_id_estado;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM sedes WHERE id_sede = p_id_sede) THEN
        RAISE EXCEPTION 'Sede % no encontrada.', p_id_sede;
    END IF;
    IF p_fecha_nacimiento > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de nacimiento no puede ser futura.';
    END IF;
    SELECT COALESCE(MAX(id_sede_paciente), 0) + 1 INTO v_next_sp FROM sede_pacientes;
    INSERT INTO pacientes (id_paciente, nombre, apellido_p, apellido_m, fecha_nacimiento, id_estado)
    VALUES (p_id_paciente, p_nombre, p_apellido_p, p_apellido_m, p_fecha_nacimiento, p_id_estado);
    INSERT INTO sede_pacientes (id_sede_paciente, id_sede, id_paciente, fecha_ingreso, hora_ingreso)
    VALUES (v_next_sp, p_id_sede, p_id_paciente, CURRENT_DATE, CURRENT_TIME);
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_ins_paciente: % — %', SQLERRM, SQLSTATE;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_upd_paciente(
    p_id_paciente INT,
    p_nombre VARCHAR,
    p_apellido_p VARCHAR,
    p_apellido_m VARCHAR,
    p_fecha_nacimiento DATE,
    p_id_estado INT
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pacientes WHERE id_paciente = p_id_paciente) THEN
        RAISE EXCEPTION 'Paciente % no encontrado.', p_id_paciente;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM estados_paciente WHERE id_estado = p_id_estado) THEN
        RAISE EXCEPTION 'Estado % no existe en el catálogo.', p_id_estado;
    END IF;
    IF p_fecha_nacimiento > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de nacimiento no puede ser futura.';
    END IF;
    UPDATE pacientes
    SET nombre = p_nombre, apellido_p = p_apellido_p, apellido_m = p_apellido_m,
        fecha_nacimiento = p_fecha_nacimiento, id_estado = p_id_estado
    WHERE id_paciente = p_id_paciente;
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_upd_paciente: % — %', SQLERRM, SQLSTATE;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_del_paciente(
    p_id_paciente INT
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pacientes WHERE id_paciente = p_id_paciente) THEN
        RAISE EXCEPTION 'Paciente % no encontrado.', p_id_paciente;
    END IF;
    UPDATE pacientes SET id_estado = 3 WHERE id_paciente = p_id_paciente;
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_del_paciente: % — %', SQLERRM, SQLSTATE;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- ENFERMEDADES
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_ins_enfermedad(
    p_id_paciente INT,
    p_id_enfermedad INT,
    p_fecha_diag DATE
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO tiene_enfermedad (id_paciente, id_enfermedad, fecha_diag)
    VALUES (p_id_paciente, p_id_enfermedad, p_fecha_diag);
END;
$$;


CREATE OR REPLACE PROCEDURE sp_del_enfermedad(
    p_id_paciente INT,
    p_id_enfermedad INT
)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM tiene_enfermedad
    WHERE id_paciente = p_id_paciente AND id_enfermedad = p_id_enfermedad;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- CONTACTOS DE EMERGENCIA
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_ins_contacto(
    p_id_paciente INT,
    p_nombre VARCHAR,
    p_apellido_p VARCHAR,
    p_apellido_m VARCHAR,
    p_telefono VARCHAR,
    p_relacion VARCHAR,
    p_email VARCHAR,
    p_pin_acceso VARCHAR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_next_id INT;
    v_next_prio INT;
BEGIN
    SELECT COALESCE(MAX(id_contacto), 0) + 1 INTO v_next_id FROM contactos_emergencia;
    SELECT COALESCE(MAX(prioridad), 0) + 1 INTO v_next_prio FROM paciente_contactos WHERE id_paciente = p_id_paciente;

    INSERT INTO contactos_emergencia (id_contacto, nombre, apellido_p, apellido_m, telefono, relacion, email, pin_acceso)
    VALUES (v_next_id, p_nombre, p_apellido_p, p_apellido_m, p_telefono, p_relacion, p_email, p_pin_acceso);

    INSERT INTO paciente_contactos (id_paciente, id_contacto, prioridad)
    VALUES (p_id_paciente, v_next_id, v_next_prio);
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- KIT GPS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_ins_kit(
    p_id_paciente INT,
    p_id_dispositivo_gps INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_next_id INT; v_tipo VARCHAR(10); v_estado VARCHAR(20);
BEGIN
    SELECT tipo, estado INTO v_tipo, v_estado FROM dispositivos WHERE id_dispositivo = p_id_dispositivo_gps;
    IF v_tipo IS NULL THEN
        RAISE EXCEPTION 'Dispositivo % no encontrado.', p_id_dispositivo_gps;
    END IF;
    IF v_tipo != 'GPS' THEN
        RAISE EXCEPTION 'El dispositivo % es de tipo "%" — se requiere tipo GPS.', p_id_dispositivo_gps, v_tipo;
    END IF;
    IF v_estado != 'Activo' THEN
        RAISE EXCEPTION 'El dispositivo GPS % tiene estado "%" y no puede asignarse.', p_id_dispositivo_gps, v_estado;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pacientes WHERE id_paciente = p_id_paciente) THEN
        RAISE EXCEPTION 'Paciente % no encontrado.', p_id_paciente;
    END IF;
    SELECT COALESCE(MAX(id_monitoreo), 0) + 1 INTO v_next_id FROM asignacion_kit;
    INSERT INTO asignacion_kit (id_monitoreo, id_paciente, id_dispositivo_gps, fecha_entrega)
    VALUES (v_next_id, p_id_paciente, p_id_dispositivo_gps, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_ins_kit: % — %', SQLERRM, SQLSTATE;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_kit_reasignar(
    p_id_paciente INT,
    p_id_dispositivo_nuevo INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_next_id INT; v_tipo VARCHAR(10); v_estado VARCHAR(20);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM asignacion_kit WHERE id_paciente = p_id_paciente AND fecha_fin IS NULL) THEN
        RAISE EXCEPTION 'El paciente % no tiene un kit GPS activo para reasignar.', p_id_paciente;
    END IF;
    SELECT tipo, estado INTO v_tipo, v_estado FROM dispositivos WHERE id_dispositivo = p_id_dispositivo_nuevo;
    IF v_tipo IS NULL THEN
        RAISE EXCEPTION 'Dispositivo % no encontrado.', p_id_dispositivo_nuevo;
    END IF;
    IF v_tipo != 'GPS' THEN
        RAISE EXCEPTION 'El dispositivo % es de tipo "%" — se requiere tipo GPS.', p_id_dispositivo_nuevo, v_tipo;
    END IF;
    IF v_estado != 'Activo' THEN
        RAISE EXCEPTION 'El dispositivo GPS % tiene estado "%" y no puede asignarse.', p_id_dispositivo_nuevo, v_estado;
    END IF;
    UPDATE asignacion_kit SET fecha_fin = CURRENT_DATE WHERE id_paciente = p_id_paciente AND fecha_fin IS NULL;
    SELECT COALESCE(MAX(id_monitoreo), 0) + 1 INTO v_next_id FROM asignacion_kit;
    INSERT INTO asignacion_kit (id_monitoreo, id_paciente, id_dispositivo_gps, fecha_entrega)
    VALUES (v_next_id, p_id_paciente, p_id_dispositivo_nuevo, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_kit_reasignar: % — %', SQLERRM, SQLSTATE;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- TURNOS
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- SEDE TRANSFER
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_transferir_sede(
    p_id_paciente INT,
    p_nueva_sede_id INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_next_sp INT; v_sede_actual INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pacientes WHERE id_paciente = p_id_paciente) THEN
        RAISE EXCEPTION 'Paciente % no encontrado.', p_id_paciente;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM sedes WHERE id_sede = p_nueva_sede_id) THEN
        RAISE EXCEPTION 'Sede destino % no encontrada.', p_nueva_sede_id;
    END IF;
    SELECT id_sede INTO v_sede_actual FROM sede_pacientes
    WHERE id_paciente = p_id_paciente AND fecha_salida IS NULL LIMIT 1;
    IF v_sede_actual = p_nueva_sede_id THEN
        RAISE EXCEPTION 'El paciente % ya se encuentra en la sede %.', p_id_paciente, p_nueva_sede_id;
    END IF;
    UPDATE sede_pacientes SET fecha_salida = CURRENT_DATE, hora_salida = CURRENT_TIME
    WHERE id_paciente = p_id_paciente AND fecha_salida IS NULL;
    SELECT COALESCE(MAX(id_sede_paciente), 0) + 1 INTO v_next_sp FROM sede_pacientes;
    INSERT INTO sede_pacientes (id_sede_paciente, id_sede, id_paciente, fecha_ingreso, hora_ingreso)
    VALUES (v_next_sp, p_nueva_sede_id, p_id_paciente, CURRENT_DATE, CURRENT_TIME);
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_transferir_sede: % — %', SQLERRM, SQLSTATE;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- ALERTAS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_upd_alerta_atendida(
    p_id_alerta INT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE alertas SET estatus = 'Atendida' WHERE id_alerta = p_id_alerta;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_del_alerta(
    p_id_alerta INT
)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM alertas WHERE id_alerta = p_id_alerta;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- DISPOSITIVOS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_ins_dispositivo(
    p_id_dispositivo INT,
    p_id_serial VARCHAR,
    p_tipo VARCHAR,
    p_modelo VARCHAR
)
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM dispositivos WHERE id_serial = p_id_serial) THEN
        RAISE EXCEPTION 'Ya existe un dispositivo con serial "%".', p_id_serial;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM cat_tipo_dispositivo WHERE tipo = p_tipo) THEN
        RAISE EXCEPTION 'Tipo de dispositivo "%" no válido.', p_tipo;
    END IF;
    INSERT INTO dispositivos (id_dispositivo, id_serial, tipo, modelo, estado)
    VALUES (p_id_dispositivo, p_id_serial, p_tipo, p_modelo, 'Activo');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_ins_dispositivo: % — %', SQLERRM, SQLSTATE;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_upd_dispositivo(
    p_id_dispositivo INT,
    p_id_serial VARCHAR,
    p_tipo VARCHAR,
    p_modelo VARCHAR,
    p_estado VARCHAR
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dispositivos
    SET id_serial = p_id_serial, tipo = p_tipo, modelo = p_modelo, estado = p_estado
    WHERE id_dispositivo = p_id_dispositivo;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_del_dispositivo(
    p_id_dispositivo INT
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dispositivos WHERE id_dispositivo = p_id_dispositivo) THEN
        RAISE EXCEPTION 'Dispositivo % no encontrado.', p_id_dispositivo;
    END IF;
    IF EXISTS (SELECT 1 FROM asignacion_kit WHERE id_dispositivo_gps = p_id_dispositivo AND fecha_fin IS NULL) THEN
        RAISE EXCEPTION 'El dispositivo % tiene una asignación GPS activa y no puede eliminarse.', p_id_dispositivo;
    END IF;
    IF EXISTS (SELECT 1 FROM asignacion_beacon WHERE id_dispositivo = p_id_dispositivo AND fecha_fin IS NULL) THEN
        RAISE EXCEPTION 'El dispositivo % tiene una asignación beacon activa y no puede eliminarse.', p_id_dispositivo;
    END IF;
    DELETE FROM dispositivos WHERE id_dispositivo = p_id_dispositivo;
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_del_dispositivo: % — %', SQLERRM, SQLSTATE;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- ZONAS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_ins_zona(
    p_id_zona     INT,
    p_nombre_zona VARCHAR,
    p_latitud     DOUBLE PRECISION,
    p_longitud    DOUBLE PRECISION,
    p_radio_metros DOUBLE PRECISION
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO zonas (id_zona, nombre_zona, latitud_centro, longitud_centro, radio_metros, geom)
    VALUES (
        p_id_zona,
        p_nombre_zona,
        p_latitud,
        p_longitud,
        p_radio_metros,
        ST_SetSRID(ST_MakePoint(p_longitud, p_latitud), 4326)::geography
    );
END;
$$;


CREATE OR REPLACE PROCEDURE sp_upd_zona(
    p_id_zona      INT,
    p_nombre_zona  VARCHAR,
    p_latitud      DOUBLE PRECISION,
    p_longitud     DOUBLE PRECISION,
    p_radio_metros DOUBLE PRECISION
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE zonas
    SET nombre_zona     = p_nombre_zona,
        latitud_centro  = p_latitud,
        longitud_centro = p_longitud,
        radio_metros    = p_radio_metros,
        geom = ST_SetSRID(ST_MakePoint(p_longitud, p_latitud), 4326)::geography
    WHERE id_zona = p_id_zona;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_del_zona(
    p_id_zona INT
)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM zonas WHERE id_zona = p_id_zona;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_ins_sede_zona(
    p_id_zona INT,
    p_id_sede INT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO sede_zonas (id_sede, id_zona)
    VALUES (p_id_sede, p_id_zona)
    ON CONFLICT DO NOTHING;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_del_sedes_zona(
    p_id_zona INT
)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM sede_zonas WHERE id_zona = p_id_zona;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- BEACON — asignación y detección
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_ins_asignacion_beacon(
    p_id_dispositivo INT,
    p_id_cuidador INT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO asignacion_beacon (id_dispositivo, id_cuidador, fecha_inicio)
    VALUES (p_id_dispositivo, p_id_cuidador, CURRENT_DATE);
END;
$$;


CREATE OR REPLACE PROCEDURE sp_ins_deteccion_beacon(
    p_id_dispositivo INT,
    p_id_cuidador INT,
    p_rssi INT,
    p_gateway_id VARCHAR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_next_id INT;
BEGIN
    SELECT COALESCE(MAX(id_deteccion), 0) + 1 INTO v_next_id FROM detecciones_beacon;

    INSERT INTO detecciones_beacon (id_deteccion, id_dispositivo, id_cuidador, fecha_hora, rssi, id_gateway)
    VALUES (v_next_id, p_id_dispositivo, p_id_cuidador, NOW(), p_rssi, p_gateway_id);
END;
$$;


CREATE OR REPLACE PROCEDURE sp_upd_cerrar_asignacion_beacon(
    p_id_asignacion INT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE asignacion_beacon SET fecha_fin = CURRENT_DATE WHERE id_asignacion = p_id_asignacion;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- TURNOS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_ins_turno(
    p_id_turno INT,
    p_id_cuidador INT,
    p_id_zona INT,
    p_hora_inicio TIME,
    p_hora_fin TIME,
    p_lunes BOOLEAN,
    p_martes BOOLEAN,
    p_miercoles BOOLEAN,
    p_jueves BOOLEAN,
    p_viernes BOOLEAN,
    p_sabado BOOLEAN,
    p_domingo BOOLEAN
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM cuidadores WHERE id_empleado = p_id_cuidador) THEN
        RAISE EXCEPTION 'Cuidador % no encontrado.', p_id_cuidador;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM zonas WHERE id_zona = p_id_zona) THEN
        RAISE EXCEPTION 'Zona % no encontrada.', p_id_zona;
    END IF;
    IF p_hora_fin <= p_hora_inicio THEN
        RAISE EXCEPTION 'La hora de fin debe ser posterior a la hora de inicio.';
    END IF;
    INSERT INTO turno_cuidador (id_turno, id_cuidador, id_zona, hora_inicio, hora_fin,
        lunes, martes, miercoles, jueves, viernes, sabado, domingo, activo)
    VALUES (p_id_turno, p_id_cuidador, p_id_zona, p_hora_inicio, p_hora_fin,
        p_lunes, p_martes, p_miercoles, p_jueves, p_viernes, p_sabado, p_domingo, TRUE);
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_ins_turno: % — %', SQLERRM, SQLSTATE;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_upd_turno(
    p_id_turno INT,
    p_id_cuidador INT,
    p_id_zona INT,
    p_hora_inicio TIME,
    p_hora_fin TIME,
    p_lunes BOOLEAN,
    p_martes BOOLEAN,
    p_miercoles BOOLEAN,
    p_jueves BOOLEAN,
    p_viernes BOOLEAN,
    p_sabado BOOLEAN,
    p_domingo BOOLEAN,
    p_activo BOOLEAN
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE turno_cuidador
    SET id_cuidador = p_id_cuidador,
        id_zona = p_id_zona,
        hora_inicio = p_hora_inicio,
        hora_fin = p_hora_fin,
        lunes = p_lunes,
        martes = p_martes,
        miercoles = p_miercoles,
        jueves = p_jueves,
        viernes = p_viernes,
        sabado = p_sabado,
        domingo = p_domingo,
        activo = p_activo
    WHERE id_turno = p_id_turno;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_del_turno(
    p_id_turno INT
)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM turno_cuidador WHERE id_turno = p_id_turno;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SP 23 — Cuidadores
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_ins_cuidador(
    p_id_empleado   INT,
    p_nombre        VARCHAR,
    p_apellido_p    VARCHAR,
    p_apellido_m    VARCHAR,
    p_curp          VARCHAR,
    p_telefono      VARCHAR
)
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM empleados WHERE CURP_pasaporte = p_curp) THEN
        RAISE EXCEPTION 'Ya existe un empleado con CURP/pasaporte "%".', p_curp;
    END IF;
    IF EXISTS (SELECT 1 FROM empleados WHERE id_empleado = p_id_empleado) THEN
        RAISE EXCEPTION 'Ya existe un empleado con ID %.', p_id_empleado;
    END IF;
    INSERT INTO empleados (id_empleado, nombre, apellido_p, apellido_m, CURP_pasaporte, telefono)
    VALUES (p_id_empleado, p_nombre, p_apellido_p, p_apellido_m, p_curp, p_telefono);
    INSERT INTO cuidadores (id_empleado) VALUES (p_id_empleado);
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_ins_cuidador: % — %', SQLERRM, SQLSTATE;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_upd_cuidador(
    p_id_empleado   INT,
    p_nombre        VARCHAR,
    p_apellido_p    VARCHAR,
    p_apellido_m    VARCHAR,
    p_curp          VARCHAR,
    p_telefono      VARCHAR
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE empleados
    SET nombre = p_nombre, apellido_p = p_apellido_p, apellido_m = p_apellido_m,
        telefono = p_telefono, CURP_pasaporte = p_curp
    WHERE id_empleado = p_id_empleado;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_del_cuidador(
    p_id_empleado INT
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM cuidadores WHERE id_empleado = p_id_empleado) THEN
        RAISE EXCEPTION 'Cuidador % no encontrado.', p_id_empleado;
    END IF;
    IF EXISTS (SELECT 1 FROM asignacion_cuidador WHERE id_cuidador = p_id_empleado AND fecha_fin IS NULL) THEN
        RAISE EXCEPTION 'El cuidador % tiene pacientes asignados activos y no puede eliminarse.', p_id_empleado;
    END IF;
    DELETE FROM cuidadores WHERE id_empleado = p_id_empleado;
    DELETE FROM empleados  WHERE id_empleado = p_id_empleado;
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_del_cuidador: % — %', SQLERRM, SQLSTATE;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SP 26 — Alertas
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_ins_alerta(
    p_id_paciente   INT,        -- NULL for zone-level alerts
    p_tipo_alerta   VARCHAR,
    p_fecha_hora    TIMESTAMP
)
LANGUAGE plpgsql AS $$
DECLARE
    v_id INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM cat_tipo_alerta WHERE tipo_alerta = p_tipo_alerta) THEN
        RAISE EXCEPTION 'Tipo de alerta "%" no existe en el catálogo.', p_tipo_alerta;
    END IF;
    IF p_id_paciente IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pacientes WHERE id_paciente = p_id_paciente) THEN
        RAISE EXCEPTION 'Paciente % no encontrado.', p_id_paciente;
    END IF;
    SELECT COALESCE(MAX(id_alerta), 0) + 1 INTO v_id FROM alertas;
    INSERT INTO alertas (id_alerta, id_paciente, tipo_alerta, fecha_hora, estatus)
    VALUES (v_id, p_id_paciente, p_tipo_alerta, p_fecha_hora, 'Activa');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_ins_alerta: % — %', SQLERRM, SQLSTATE;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SP 27 — Farmacia
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_upd_stock(
    p_gtin          VARCHAR,
    p_id_sede       INT,
    p_stock_nuevo   INT
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_stock_nuevo < 0 THEN
        RAISE EXCEPTION 'El stock no puede ser negativo (valor recibido: %).', p_stock_nuevo;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM inventario_medicinas WHERE GTIN = p_gtin AND id_sede = p_id_sede) THEN
        RAISE EXCEPTION 'No existe inventario para GTIN "%" en la sede %.', p_gtin, p_id_sede;
    END IF;
    UPDATE inventario_medicinas SET stock_actual = p_stock_nuevo WHERE GTIN = p_gtin AND id_sede = p_id_sede;
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_upd_stock: % — %', SQLERRM, SQLSTATE;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_ins_suministro(
    p_id_suministro INT,
    p_id_farmacia   INT,
    p_id_sede       INT,
    p_fecha_entrega DATE,
    p_estado        VARCHAR
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO suministros (id_suministro, id_farmacia, id_sede, fecha_entrega, estado)
    VALUES (p_id_suministro, p_id_farmacia, p_id_sede, p_fecha_entrega, p_estado);
END;
$$;


CREATE OR REPLACE PROCEDURE sp_ins_suministro_linea(
    p_id_suministro INT,
    p_gtin          VARCHAR,
    p_cantidad      INT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO suministro_medicinas (id_suministro, GTIN, cantidad)
    VALUES (p_id_suministro, p_gtin, p_cantidad)
    ON CONFLICT (id_suministro, GTIN)
    DO UPDATE SET cantidad = suministro_medicinas.cantidad + EXCLUDED.cantidad;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_upd_suministro_estado(
    p_id_suministro INT,
    p_estado        VARCHAR
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE suministros SET estado = p_estado WHERE id_suministro = p_id_suministro;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_del_suministro(
    p_id_suministro INT
)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM suministros WHERE id_suministro = p_id_suministro;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SP 32 — Visitas
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_ins_visita(
    p_id_visita     INT,
    p_id_paciente   INT,
    p_id_visitante  INT,
    p_id_sede       INT,
    p_fecha_entrada DATE,
    p_hora_entrada  TIME
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO visitas (id_visita, id_paciente, id_visitante, id_sede, fecha_entrada, hora_entrada)
    VALUES (p_id_visita, p_id_paciente, p_id_visitante, p_id_sede, p_fecha_entrada, p_hora_entrada);
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SP 33 — GPS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_ins_lectura_gps(
    p_id_dispositivo    INT,
    p_latitud           DOUBLE PRECISION,
    p_longitud          DOUBLE PRECISION,
    p_nivel_bateria     INT,
    p_altura            DOUBLE PRECISION    -- NULL if not provided
)
LANGUAGE plpgsql AS $$
DECLARE
    v_id INT; v_tipo VARCHAR(10);
BEGIN
    SELECT tipo INTO v_tipo FROM dispositivos WHERE id_dispositivo = p_id_dispositivo;
    IF v_tipo IS NULL THEN
        RAISE EXCEPTION 'Dispositivo % no encontrado.', p_id_dispositivo;
    END IF;
    IF v_tipo != 'GPS' THEN
        RAISE EXCEPTION 'El dispositivo % es de tipo "%" — se esperaba GPS.', p_id_dispositivo, v_tipo;
    END IF;
    IF p_latitud < -90 OR p_latitud > 90 THEN
        RAISE EXCEPTION 'Latitud % fuera de rango [-90, 90].', p_latitud;
    END IF;
    IF p_longitud < -180 OR p_longitud > 180 THEN
        RAISE EXCEPTION 'Longitud % fuera de rango [-180, 180].', p_longitud;
    END IF;
    IF p_nivel_bateria IS NOT NULL AND (p_nivel_bateria < 0 OR p_nivel_bateria > 100) THEN
        RAISE EXCEPTION 'Nivel de batería % fuera de rango [0, 100].', p_nivel_bateria;
    END IF;
    SELECT COALESCE(MAX(id_lectura), 0) + 1 INTO v_id FROM lecturas_gps;
    INSERT INTO lecturas_gps (id_lectura, id_dispositivo, fecha_hora, latitud, longitud, altura, nivel_bateria, geom)
    VALUES (v_id, p_id_dispositivo, NOW(), p_latitud, p_longitud, p_altura, p_nivel_bateria,
        ST_SetSRID(ST_MakePoint(p_longitud, p_latitud), 4326)::geography);
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_ins_lectura_gps: % — %', SQLERRM, SQLSTATE;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SEDES — CRUD
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_ins_sede(
    p_id_sede    INT,
    p_nombre     VARCHAR,
    p_calle      VARCHAR,
    p_numero     VARCHAR,
    p_municipio  VARCHAR,
    p_estado     VARCHAR
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO sedes (id_sede, nombre_sede, calle, numero, municipio, estado)
    VALUES (p_id_sede, p_nombre, p_calle, p_numero, p_municipio, p_estado);
END;
$$;


CREATE OR REPLACE PROCEDURE sp_upd_sede(
    p_id_sede    INT,
    p_nombre     VARCHAR,
    p_calle      VARCHAR,
    p_numero     VARCHAR,
    p_municipio  VARCHAR,
    p_estado     VARCHAR
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE sedes
    SET nombre_sede = p_nombre,
        calle       = p_calle,
        numero      = p_numero,
        municipio   = p_municipio,
        estado      = p_estado
    WHERE id_sede = p_id_sede;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_del_sede(
    p_id_sede INT
)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM sedes WHERE id_sede = p_id_sede;
END;
$$;
