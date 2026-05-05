-- AppProcedures.sql
-- DML stored procedures for app.py routes
-- Apply: psql -U palermingoat -d alzheimer -f AppProcedures.sql

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
    SELECT COALESCE(MAX(id_sede_paciente), 0) + 1 INTO v_next_sp FROM sede_pacientes;

    INSERT INTO pacientes (id_paciente, nombre, apellido_p, apellido_m, fecha_nacimiento, id_estado)
    VALUES (p_id_paciente, p_nombre, p_apellido_p, p_apellido_m, p_fecha_nacimiento, p_id_estado);

    INSERT INTO sede_pacientes (id_sede_paciente, id_sede, id_paciente, fecha_ingreso, hora_ingreso)
    VALUES (v_next_sp, p_id_sede, p_id_paciente, CURRENT_DATE, CURRENT_TIME);
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
    UPDATE pacientes
    SET nombre = p_nombre,
        apellido_p = p_apellido_p,
        apellido_m = p_apellido_m,
        fecha_nacimiento = p_fecha_nacimiento,
        id_estado = p_id_estado
    WHERE id_paciente = p_id_paciente;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_del_paciente(
    p_id_paciente INT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE pacientes SET id_estado = 3 WHERE id_paciente = p_id_paciente;
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
    v_next_id INT;
BEGIN
    SELECT COALESCE(MAX(id_monitoreo), 0) + 1 INTO v_next_id FROM asignacion_kit;

    INSERT INTO asignacion_kit (id_monitoreo, id_paciente, id_dispositivo_gps, fecha_entrega)
    VALUES (v_next_id, p_id_paciente, p_id_dispositivo_gps, CURRENT_DATE);
END;
$$;


CREATE OR REPLACE PROCEDURE sp_kit_reasignar(
    p_id_paciente INT,
    p_id_dispositivo_nuevo INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_next_id INT;
BEGIN
    UPDATE asignacion_kit
    SET fecha_fin = CURRENT_DATE
    WHERE id_paciente = p_id_paciente AND fecha_fin IS NULL;

    SELECT COALESCE(MAX(id_monitoreo), 0) + 1 INTO v_next_id FROM asignacion_kit;

    INSERT INTO asignacion_kit (id_monitoreo, id_paciente, id_dispositivo_gps, fecha_entrega)
    VALUES (v_next_id, p_id_paciente, p_id_dispositivo_nuevo, CURRENT_DATE);
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
    v_next_sp INT;
BEGIN
    UPDATE sede_pacientes
    SET fecha_salida = CURRENT_DATE, hora_salida = CURRENT_TIME
    WHERE id_paciente = p_id_paciente AND fecha_salida IS NULL;

    SELECT COALESCE(MAX(id_sede_paciente), 0) + 1 INTO v_next_sp FROM sede_pacientes;

    INSERT INTO sede_pacientes (id_sede_paciente, id_sede, id_paciente, fecha_ingreso, hora_ingreso)
    VALUES (v_next_sp, p_nueva_sede_id, p_id_paciente, CURRENT_DATE, CURRENT_TIME);
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
    INSERT INTO dispositivos (id_dispositivo, id_serial, tipo, modelo, estado)
    VALUES (p_id_dispositivo, p_id_serial, p_tipo, p_modelo, 'Activo');
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
    DELETE FROM dispositivos WHERE id_dispositivo = p_id_dispositivo;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- ZONAS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE sp_ins_zona(
    p_nombre_zona VARCHAR,
    p_latitud DOUBLE PRECISION,
    p_longitud DOUBLE PRECISION,
    p_radio_metros DOUBLE PRECISION
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO zonas (nombre_zona, latitud_centro, longitud_centro, radio_metros)
    VALUES (p_nombre_zona, p_latitud, p_longitud, p_radio_metros);
END;
$$;


CREATE OR REPLACE PROCEDURE sp_upd_zona(
    p_id_zona INT,
    p_nombre_zona VARCHAR,
    p_latitud DOUBLE PRECISION,
    p_longitud DOUBLE PRECISION,
    p_radio_metros DOUBLE PRECISION
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE zonas
    SET nombre_zona = p_nombre_zona,
        latitud_centro = p_latitud,
        longitud_centro = p_longitud,
        radio_metros = p_radio_metros
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
    INSERT INTO turno_cuidador (id_turno, id_cuidador, id_zona, hora_inicio, hora_fin,
        lunes, martes, miercoles, jueves, viernes, sabado, domingo, activo)
    VALUES (p_id_turno, p_id_cuidador, p_id_zona, p_hora_inicio, p_hora_fin,
        p_lunes, p_martes, p_miercoles, p_jueves, p_viernes, p_sabado, p_domingo, TRUE);
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
    INSERT INTO empleados (id_empleado, nombre, apellido_p, apellido_m, CURP_pasaporte, telefono)
    VALUES (p_id_empleado, p_nombre, p_apellido_p, p_apellido_m, p_curp, p_telefono);

    INSERT INTO cuidadores (id_empleado)
    VALUES (p_id_empleado);
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
    DELETE FROM cuidadores WHERE id_empleado = p_id_empleado;
    DELETE FROM empleados  WHERE id_empleado = p_id_empleado;
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
    SELECT COALESCE(MAX(id_alerta), 0) + 1 INTO v_id FROM alertas;
    INSERT INTO alertas (id_alerta, id_paciente, tipo_alerta, fecha_hora, estatus)
    VALUES (v_id, p_id_paciente, p_tipo_alerta, p_fecha_hora, 'Activa');
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
    UPDATE inventario_medicinas
    SET stock_actual = p_stock_nuevo
    WHERE GTIN = p_gtin AND id_sede = p_id_sede;
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
    v_id INT;
BEGIN
    SELECT COALESCE(MAX(id_lectura), 0) + 1 INTO v_id FROM lecturas_gps;
    INSERT INTO lecturas_gps
        (id_lectura, id_dispositivo, fecha_hora, latitud, longitud, altura, nivel_bateria, geom)
    VALUES (
        v_id, p_id_dispositivo, NOW(), p_latitud, p_longitud, p_altura, p_nivel_bateria,
        ST_SetSRID(ST_MakePoint(p_longitud, p_latitud), 4326)::geography
    );
END;
$$;
