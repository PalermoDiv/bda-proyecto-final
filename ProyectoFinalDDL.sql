-- =============================================================================
-- ProyectoFinalDDL.sql
-- AlzMonitor — Sistema de Monitoreo de Pacientes con Alzheimer
-- Base de datos: alzheimer
-- Uso: psql -U palermingoat -d alzheimer -f ProyectoFinalDDL.sql
--
-- CAMBIOS RESPECTO AL AVANCE ANTERIOR (según retroalimentación del profesor)
--   1. Eliminación de PACIENTE_RECETAS (redundancia con id_paciente en RECETAS)
--   2. Catálogos normalizados para tipos y estados (reemplazan CHECK literales)
--   3. ALERTA_EVENTO_ORIGEN — trazabilidad de fuente que disparó la alerta
--   4. LECTURAS_NFC — tabla separada de DETECCIONES_BEACON (corrección semántica)
-- =============================================================================


-- =============================================================================
-- LIMPIEZA  (ejecutar en orden inverso de dependencias)
-- =============================================================================

DROP TABLE IF EXISTS bitacora_comedor       CASCADE;
DROP TABLE IF EXISTS suministro_medicinas   CASCADE;
DROP TABLE IF EXISTS suministros            CASCADE;
DROP TABLE IF EXISTS inventario_medicinas   CASCADE;
DROP TABLE IF EXISTS farmacias_proveedoras  CASCADE;
DROP TABLE IF EXISTS entregas_externas      CASCADE;
DROP TABLE IF EXISTS visitas                CASCADE;
DROP TABLE IF EXISTS visitantes             CASCADE;
DROP TABLE IF EXISTS sede_pacientes         CASCADE;
DROP TABLE IF EXISTS sede_empleados         CASCADE;
DROP TABLE IF EXISTS sede_zonas             CASCADE;
DROP TABLE IF EXISTS sedes                  CASCADE;
DROP TABLE IF EXISTS alerta_evento_origen   CASCADE;
DROP TABLE IF EXISTS alertas                CASCADE;
DROP TABLE IF EXISTS lecturas_nfc           CASCADE;
DROP TABLE IF EXISTS receta_nfc             CASCADE;
DROP TABLE IF EXISTS receta_medicamentos    CASCADE;
DROP TABLE IF EXISTS recetas                CASCADE;
DROP TABLE IF EXISTS detecciones_beacon     CASCADE;
DROP TABLE IF EXISTS lecturas_gps           CASCADE;
DROP TABLE IF EXISTS asignacion_kit         CASCADE;
DROP TABLE IF EXISTS zona_beacons           CASCADE;
DROP TABLE IF EXISTS gateways               CASCADE;
DROP TABLE IF EXISTS zonas                  CASCADE;
DROP TABLE IF EXISTS dispositivos           CASCADE;
DROP TABLE IF EXISTS asignacion_cuidador    CASCADE;
DROP TABLE IF EXISTS cocineros              CASCADE;
DROP TABLE IF EXISTS cuidadores             CASCADE;
DROP TABLE IF EXISTS empleados              CASCADE;
DROP TABLE IF EXISTS paciente_contactos     CASCADE;
DROP TABLE IF EXISTS contactos_emergencia   CASCADE;
DROP TABLE IF EXISTS tiene_enfermedad       CASCADE;
DROP TABLE IF EXISTS pacientes              CASCADE;
DROP TABLE IF EXISTS medicamentos           CASCADE;
DROP TABLE IF EXISTS enfermedades           CASCADE;
DROP TABLE IF EXISTS estados_paciente       CASCADE;
DROP TABLE IF EXISTS cat_tipo_dispositivo   CASCADE;
DROP TABLE IF EXISTS cat_estado_dispositivo CASCADE;
DROP TABLE IF EXISTS cat_tipo_alerta        CASCADE;
DROP TABLE IF EXISTS cat_estado_alerta      CASCADE;
DROP TABLE IF EXISTS cat_estado_suministro  CASCADE;
DROP TABLE IF EXISTS cat_estado_entrega     CASCADE;
DROP TABLE IF EXISTS cat_turno_comedor      CASCADE;


-- =============================================================================
-- BLOQUE 1: CATÁLOGOS
-- Reemplazan los CHECK con literales; permiten agregar valores sin ALTER TABLE
-- =============================================================================

-- Catálogo existente — estados de paciente
CREATE TABLE estados_paciente (
    id_estado   INTEGER      PRIMARY KEY,
    desc_estado VARCHAR(50)  NOT NULL,
    CONSTRAINT uq_desc_estado UNIQUE (desc_estado)
);

-- NUEVO — tipo de dispositivo IoT
CREATE TABLE cat_tipo_dispositivo (
    tipo  VARCHAR(10)  PRIMARY KEY
);

-- NUEVO — estado operativo de dispositivo
CREATE TABLE cat_estado_dispositivo (
    estado  VARCHAR(20)  PRIMARY KEY
);

-- NUEVO — tipo de alerta clínica
CREATE TABLE cat_tipo_alerta (
    tipo_alerta  VARCHAR(30)  PRIMARY KEY
);

-- NUEVO — estado de resolución de alerta
CREATE TABLE cat_estado_alerta (
    estatus  VARCHAR(20)  PRIMARY KEY
);

-- NUEVO — estado de orden de suministro
CREATE TABLE cat_estado_suministro (
    estado  VARCHAR(20)  PRIMARY KEY
);

-- NUEVO — estado de entrega externa
CREATE TABLE cat_estado_entrega (
    estado  VARCHAR(20)  PRIMARY KEY
);

-- NUEVO — turno del comedor
CREATE TABLE cat_turno_comedor (
    turno  VARCHAR(20)  PRIMARY KEY
);

-- Catálogos de dominio clínico
CREATE TABLE enfermedades (
    id_enfermedad     INTEGER       PRIMARY KEY,
    nombre_enfermedad VARCHAR(100)  NOT NULL,
    CONSTRAINT uq_nombre_enfermedad UNIQUE (nombre_enfermedad)
);

CREATE TABLE medicamentos (
    GTIN               VARCHAR(20)   PRIMARY KEY,
    nombre_medicamento VARCHAR(100)  NOT NULL,
    descripcion        VARCHAR(255),
    CONSTRAINT uq_nombre_medicamento UNIQUE (nombre_medicamento)
);


-- =============================================================================
-- BLOQUE 2: PACIENTES Y SUS RELACIONES
-- =============================================================================

CREATE TABLE pacientes (
    id_paciente      INTEGER      PRIMARY KEY,
    nombre           VARCHAR(80)  NOT NULL,
    apellido_p       VARCHAR(80)  NOT NULL,
    apellido_m       VARCHAR(80)  NOT NULL,
    fecha_nacimiento DATE         NOT NULL,
    id_estado        INTEGER      NOT NULL,
    CONSTRAINT fk_paciente_estado
        FOREIGN KEY (id_estado) REFERENCES estados_paciente (id_estado)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE tiene_enfermedad (
    id_paciente   INTEGER  NOT NULL,
    id_enfermedad INTEGER  NOT NULL,
    fecha_diag    DATE     NOT NULL,
    CONSTRAINT pk_tiene_enfermedad PRIMARY KEY (id_paciente, id_enfermedad),
    CONSTRAINT fk_te_paciente
        FOREIGN KEY (id_paciente)   REFERENCES pacientes    (id_paciente)
        ON DELETE RESTRICT,
    CONSTRAINT fk_te_enfermedad
        FOREIGN KEY (id_enfermedad) REFERENCES enfermedades (id_enfermedad)
        ON DELETE RESTRICT
);

CREATE TABLE contactos_emergencia (
    id_contacto    INTEGER      PRIMARY KEY,
    nombre         VARCHAR(80)  NOT NULL,
    apellido_p     VARCHAR(80)  NOT NULL,
    apellido_m     VARCHAR(80),
    telefono       VARCHAR(20)  NOT NULL,
    fecha_nac      DATE,
    CURP_pasaporte VARCHAR(20),
    relacion       VARCHAR(50)  NOT NULL
);

CREATE TABLE paciente_contactos (
    id_paciente  INTEGER  NOT NULL,
    id_contacto  INTEGER  NOT NULL,
    prioridad    INTEGER  NOT NULL CHECK (prioridad > 0),
    CONSTRAINT pk_paciente_contactos PRIMARY KEY (id_paciente, id_contacto),
    CONSTRAINT fk_pc_paciente
        FOREIGN KEY (id_paciente) REFERENCES pacientes            (id_paciente)
        ON DELETE CASCADE,
    CONSTRAINT fk_pc_contacto
        FOREIGN KEY (id_contacto) REFERENCES contactos_emergencia (id_contacto)
        ON DELETE RESTRICT,
    CONSTRAINT uq_pc_prioridad UNIQUE (id_paciente, prioridad)
);


-- =============================================================================
-- BLOQUE 3: EMPLEADOS Y ROLES
-- =============================================================================

CREATE TABLE empleados (
    id_empleado    INTEGER      PRIMARY KEY,
    nombre         VARCHAR(80)  NOT NULL,
    apellido_p     VARCHAR(80)  NOT NULL,
    apellido_m     VARCHAR(80),
    CURP_pasaporte VARCHAR(20)  NOT NULL,
    fecha_nac      DATE,
    telefono       VARCHAR(20),
    CONSTRAINT uq_empleado_curp UNIQUE (CURP_pasaporte)
);

CREATE TABLE cuidadores (
    id_empleado          INTEGER       PRIMARY KEY,
    certificacion_medica VARCHAR(100),
    especialidad         VARCHAR(100),
    CONSTRAINT fk_cuidador_empleado
        FOREIGN KEY (id_empleado) REFERENCES empleados (id_empleado)
        ON DELETE CASCADE
);

CREATE TABLE cocineros (
    id_empleado INTEGER PRIMARY KEY,
    CONSTRAINT fk_cocinero_empleado
        FOREIGN KEY (id_empleado) REFERENCES empleados (id_empleado)
        ON DELETE CASCADE
);

CREATE TABLE asignacion_cuidador (
    id_asig_cuidador INTEGER  PRIMARY KEY,
    id_cuidador      INTEGER  NOT NULL,
    id_paciente      INTEGER  NOT NULL,
    fecha_inicio     DATE     NOT NULL,
    fecha_fin        DATE,
    CONSTRAINT fk_ac_cuidador
        FOREIGN KEY (id_cuidador)  REFERENCES cuidadores (id_empleado)
        ON DELETE RESTRICT,
    CONSTRAINT fk_ac_paciente
        FOREIGN KEY (id_paciente)  REFERENCES pacientes  (id_paciente)
        ON DELETE RESTRICT,
    CONSTRAINT chk_ac_fechas CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)
);


-- =============================================================================
-- BLOQUE 4: DISPOSITIVOS Y ZONAS
-- tipo y estado ahora referencian catálogos en lugar de CHECK con literales
-- =============================================================================

CREATE TABLE dispositivos (
    id_dispositivo  INTEGER      PRIMARY KEY,
    id_serial       VARCHAR(50)  NOT NULL,
    modelo          VARCHAR(50)  NOT NULL,
    tipo            VARCHAR(10)  NOT NULL,
    estado          VARCHAR(20)  NOT NULL DEFAULT 'Activo',
    ultima_conexion TIMESTAMP,
    CONSTRAINT uq_dispositivo_serial UNIQUE (id_serial),
    CONSTRAINT fk_disp_tipo   FOREIGN KEY (tipo)   REFERENCES cat_tipo_dispositivo   (tipo)   ON UPDATE CASCADE,
    CONSTRAINT fk_disp_estado FOREIGN KEY (estado) REFERENCES cat_estado_dispositivo (estado) ON UPDATE CASCADE
);

CREATE TABLE zonas (
    id_zona         INTEGER       PRIMARY KEY,
    nombre_zona     VARCHAR(100)  NOT NULL,
    latitud_centro  NUMERIC(10,6) NOT NULL,
    longitud_centro NUMERIC(10,6) NOT NULL,
    radio_metros    NUMERIC(8,2)  NOT NULL CHECK (radio_metros > 0),
    CONSTRAINT uq_nombre_zona UNIQUE (nombre_zona)
);

-- gateways y zona_beacons eliminados: la arquitectura BLE ya no usa gateways fijos.
-- Los beacons están fijos en el edificio; el teléfono del cuidador (Chrome/Web Bluetooth)
-- actúa como receptor móvil durante las rondas. No hay asignación per-paciente.

CREATE TABLE asignacion_kit (
    id_monitoreo       INTEGER  PRIMARY KEY,
    id_paciente        INTEGER  NOT NULL,
    id_dispositivo_gps INTEGER  NOT NULL,
    fecha_entrega      DATE,
    CONSTRAINT fk_ak_paciente
        FOREIGN KEY (id_paciente)        REFERENCES pacientes    (id_paciente)
        ON DELETE RESTRICT,
    CONSTRAINT fk_ak_gps
        FOREIGN KEY (id_dispositivo_gps) REFERENCES dispositivos (id_dispositivo)
        ON DELETE RESTRICT,
    CONSTRAINT uq_ak_gps UNIQUE (id_dispositivo_gps)
);


-- =============================================================================
-- BLOQUE 5: EVENTOS Y ALERTAS
-- NUEVO: lecturas_nfc  — separado de detecciones_beacon (corrección semántica)
-- NUEVO: alerta_evento_origen — trazabilidad del evento que disparó la alerta
-- =============================================================================

CREATE TABLE lecturas_gps (
    id_lectura     INTEGER        PRIMARY KEY,
    id_dispositivo INTEGER        NOT NULL,
    fecha_hora     TIMESTAMP      NOT NULL,
    latitud        NUMERIC(10,6)  NOT NULL,
    longitud       NUMERIC(10,6)  NOT NULL,
    altura         NUMERIC(8,2),
    nivel_bateria  INTEGER        CHECK (nivel_bateria BETWEEN 0 AND 100),
    CONSTRAINT fk_lgps_dispositivo
        FOREIGN KEY (id_dispositivo) REFERENCES dispositivos (id_dispositivo)
        ON DELETE RESTRICT,
    CONSTRAINT uq_lgps_instante UNIQUE (id_dispositivo, fecha_hora)
);

-- detecciones_beacon: registra qué beacons detectó el teléfono del cuidador durante rondas.
-- Ya no referencia gateways (eliminados). El caregiver_id viene del endpoint Web Bluetooth.
CREATE TABLE detecciones_beacon (
    id_deteccion   INTEGER    PRIMARY KEY,
    id_dispositivo INTEGER    NOT NULL,
    fecha_hora     TIMESTAMP  NOT NULL,
    rssi           INTEGER    NOT NULL,
    CONSTRAINT fk_db_dispositivo
        FOREIGN KEY (id_dispositivo) REFERENCES dispositivos (id_dispositivo)
        ON DELETE RESTRICT,
    CONSTRAINT uq_db_instante UNIQUE (id_dispositivo, fecha_hora)
);

-- NUEVO: lecturas de chips NFC para adherencia terapéutica
-- Separado de detecciones_beacon: beacon == presencia/ubicación, NFC == medicación
CREATE TABLE lecturas_nfc (
    id_lectura_nfc INTEGER    PRIMARY KEY,
    id_dispositivo INTEGER    NOT NULL,   -- dispositivo tipo NFC
    id_receta      INTEGER    NOT NULL,   -- receta que se está verificando
    fecha_hora     TIMESTAMP  NOT NULL,
    tipo_lectura   VARCHAR(30) NOT NULL DEFAULT 'Administración',
                              -- 'Administración', 'Verificación', 'Rechazo'
    resultado      VARCHAR(20) NOT NULL DEFAULT 'Exitosa',
                              -- 'Exitosa', 'Fallida', 'Sin respuesta'
    CONSTRAINT fk_lnfc_dispositivo
        FOREIGN KEY (id_dispositivo) REFERENCES dispositivos (id_dispositivo)
        ON DELETE RESTRICT,
    CONSTRAINT fk_lnfc_receta
        FOREIGN KEY (id_receta)      REFERENCES recetas       (id_receta)
        ON DELETE RESTRICT,
    CONSTRAINT uq_lnfc_instante UNIQUE (id_dispositivo, id_receta, fecha_hora)
);

CREATE TABLE alertas (
    id_alerta   INTEGER      PRIMARY KEY,
    id_paciente INTEGER      NOT NULL,
    tipo_alerta VARCHAR(30)  NOT NULL,
    fecha_hora  TIMESTAMP    NOT NULL,
    estatus     VARCHAR(20)  NOT NULL DEFAULT 'Activa',
    CONSTRAINT fk_alerta_paciente
        FOREIGN KEY (id_paciente)  REFERENCES pacientes         (id_paciente)
        ON DELETE RESTRICT,
    CONSTRAINT fk_alerta_tipo
        FOREIGN KEY (tipo_alerta)  REFERENCES cat_tipo_alerta   (tipo_alerta)
        ON UPDATE CASCADE,
    CONSTRAINT fk_alerta_estatus
        FOREIGN KEY (estatus)      REFERENCES cat_estado_alerta  (estatus)
        ON UPDATE CASCADE,
    CONSTRAINT uq_alerta_unica UNIQUE (id_paciente, tipo_alerta, fecha_hora)
);

-- NUEVO: vincula cada alerta con el evento IoT que la originó
-- BEACON eliminado como tipo_evento: las detecciones BLE no generan alertas de seguridad.
-- Alertas vienen de GPS (salida de zona, batería baja, caída) o SOS (botón físico) o NFC.
CREATE TABLE alerta_evento_origen (
    id_origen       INTEGER      PRIMARY KEY,
    id_alerta       INTEGER      NOT NULL,
    tipo_evento     VARCHAR(10)  NOT NULL,   -- 'GPS', 'NFC', 'SOS'
    id_lectura_gps  INTEGER,                 -- FK si origen es GPS
    regla_disparada VARCHAR(200),            -- descripción de la regla
    CONSTRAINT fk_aeo_alerta
        FOREIGN KEY (id_alerta)      REFERENCES alertas      (id_alerta)
        ON DELETE CASCADE,
    CONSTRAINT fk_aeo_gps
        FOREIGN KEY (id_lectura_gps) REFERENCES lecturas_gps (id_lectura)
        ON DELETE RESTRICT,
    CONSTRAINT uq_aeo_alerta UNIQUE (id_alerta),
    CONSTRAINT chk_aeo_tipo CHECK (tipo_evento IN ('GPS', 'NFC', 'SOS'))
);


-- =============================================================================
-- BLOQUE 6: RECETAS Y MEDICACIÓN
-- CAMBIO: se elimina PACIENTE_RECETAS — el id_paciente en RECETAS es suficiente
--         para indicar a quién pertenece la prescripción (relación 1:1).
-- =============================================================================

CREATE TABLE recetas (
    id_receta   INTEGER  PRIMARY KEY,
    fecha       DATE     NOT NULL,
    id_paciente INTEGER  NOT NULL,
    CONSTRAINT fk_receta_paciente
        FOREIGN KEY (id_paciente) REFERENCES pacientes (id_paciente)
        ON DELETE RESTRICT
);

CREATE TABLE receta_medicamentos (
    id_detalle       INTEGER      PRIMARY KEY,
    id_receta        INTEGER      NOT NULL,
    GTIN             VARCHAR(20)  NOT NULL,
    dosis            VARCHAR(50)  NOT NULL,
    frecuencia_horas INTEGER      NOT NULL CHECK (frecuencia_horas > 0),
    CONSTRAINT fk_rm_receta
        FOREIGN KEY (id_receta) REFERENCES recetas      (id_receta)
        ON DELETE CASCADE,
    CONSTRAINT fk_rm_medicamento
        FOREIGN KEY (GTIN)      REFERENCES medicamentos (GTIN)
        ON DELETE RESTRICT
);

-- Asigna un dispositivo NFC para gestionar la lectura de una receta
CREATE TABLE receta_nfc (
    id_receta            INTEGER  NOT NULL,
    id_dispositivo       INTEGER  NOT NULL,
    fecha_inicio_gestion DATE     NOT NULL,
    fecha_fin_gestion    DATE,
    CONSTRAINT pk_receta_nfc PRIMARY KEY (id_receta, id_dispositivo),
    CONSTRAINT fk_rn_receta
        FOREIGN KEY (id_receta)       REFERENCES recetas      (id_receta)
        ON DELETE CASCADE,
    CONSTRAINT fk_rn_dispositivo
        FOREIGN KEY (id_dispositivo)  REFERENCES dispositivos (id_dispositivo)
        ON DELETE RESTRICT,
    CONSTRAINT chk_rn_fechas
        CHECK (fecha_fin_gestion IS NULL OR fecha_fin_gestion >= fecha_inicio_gestion)
);


-- =============================================================================
-- BLOQUE 7: SEDES
-- =============================================================================

CREATE TABLE sedes (
    id_sede     INTEGER       PRIMARY KEY,
    nombre_sede VARCHAR(100)  NOT NULL,
    calle       VARCHAR(100)  NOT NULL,
    numero      VARCHAR(10)   NOT NULL,
    municipio   VARCHAR(80)   NOT NULL,
    estado      VARCHAR(80)   NOT NULL,
    CONSTRAINT uq_nombre_sede UNIQUE (nombre_sede)
);

CREATE TABLE sede_zonas (
    id_sede  INTEGER  NOT NULL,
    id_zona  INTEGER  NOT NULL,
    CONSTRAINT pk_sede_zonas PRIMARY KEY (id_sede, id_zona),
    CONSTRAINT fk_sz_sede
        FOREIGN KEY (id_sede) REFERENCES sedes (id_sede),
    CONSTRAINT fk_sz_zona
        FOREIGN KEY (id_zona) REFERENCES zonas (id_zona)
);

CREATE TABLE sede_empleados (
    id_sede_empleado INTEGER    PRIMARY KEY,
    id_sede          INTEGER    NOT NULL,
    id_empleado      INTEGER    NOT NULL,
    fecha_ingreso    DATE       NOT NULL,
    hora_ingreso     TIME       NOT NULL,
    fecha_salida     DATE,
    hora_salida      TIME,
    CONSTRAINT fk_se_sede
        FOREIGN KEY (id_sede)     REFERENCES sedes     (id_sede)
        ON DELETE RESTRICT,
    CONSTRAINT fk_se_empleado
        FOREIGN KEY (id_empleado) REFERENCES empleados (id_empleado)
        ON DELETE RESTRICT,
    CONSTRAINT chk_se_fechas
        CHECK (fecha_salida IS NULL OR fecha_salida >= fecha_ingreso)
);

CREATE TABLE sede_pacientes (
    id_sede_paciente INTEGER    PRIMARY KEY,
    id_sede          INTEGER    NOT NULL,
    id_paciente      INTEGER    NOT NULL,
    fecha_ingreso    DATE       NOT NULL,
    hora_ingreso     TIME       NOT NULL,
    fecha_salida     DATE,
    hora_salida      TIME,
    CONSTRAINT fk_sp_sede
        FOREIGN KEY (id_sede)     REFERENCES sedes     (id_sede)
        ON DELETE RESTRICT,
    CONSTRAINT fk_sp_paciente
        FOREIGN KEY (id_paciente) REFERENCES pacientes (id_paciente)
        ON DELETE RESTRICT,
    CONSTRAINT chk_sp_fechas
        CHECK (fecha_salida IS NULL OR fecha_salida >= fecha_ingreso)
);


-- =============================================================================
-- BLOQUE 8: VISITAS Y ENTREGAS
-- estado en entregas_externas ahora referencia catálogo
-- =============================================================================

CREATE TABLE visitantes (
    id_visitante   INTEGER      PRIMARY KEY,
    nombre         VARCHAR(80)  NOT NULL,
    apellido_p     VARCHAR(80)  NOT NULL,
    apellido_m     VARCHAR(80),
    relacion       VARCHAR(50)  NOT NULL,
    telefono       VARCHAR(20)  NOT NULL,
    CURP_pasaporte VARCHAR(20)
);

CREATE TABLE visitas (
    id_visita     INTEGER    PRIMARY KEY,
    id_paciente   INTEGER    NOT NULL,
    id_visitante  INTEGER    NOT NULL,
    id_sede       INTEGER    NOT NULL,
    fecha_entrada DATE       NOT NULL,
    hora_entrada  TIME       NOT NULL,
    fecha_salida  DATE,
    hora_salida   TIME,
    CONSTRAINT fk_vis_paciente
        FOREIGN KEY (id_paciente)  REFERENCES pacientes  (id_paciente)
        ON DELETE RESTRICT,
    CONSTRAINT fk_vis_visitante
        FOREIGN KEY (id_visitante) REFERENCES visitantes (id_visitante)
        ON DELETE RESTRICT,
    CONSTRAINT fk_vis_sede
        FOREIGN KEY (id_sede)      REFERENCES sedes      (id_sede)
        ON DELETE RESTRICT,
    CONSTRAINT chk_vis_fechas
        CHECK (fecha_salida IS NULL OR fecha_salida >= fecha_entrada)
);

CREATE TABLE entregas_externas (
    id_entrega      INTEGER       PRIMARY KEY,
    id_paciente     INTEGER       NOT NULL,
    id_visitante    INTEGER       NOT NULL,
    id_cuidador     INTEGER,
    descripcion     VARCHAR(255)  NOT NULL,
    estado          VARCHAR(20)   NOT NULL DEFAULT 'Pendiente',
    fecha_recepcion DATE          NOT NULL,
    hora_recepcion  TIME          NOT NULL,
    CONSTRAINT fk_ee_paciente
        FOREIGN KEY (id_paciente)  REFERENCES pacientes          (id_paciente)
        ON DELETE RESTRICT,
    CONSTRAINT fk_ee_visitante
        FOREIGN KEY (id_visitante) REFERENCES visitantes         (id_visitante)
        ON DELETE RESTRICT,
    CONSTRAINT fk_ee_cuidador
        FOREIGN KEY (id_cuidador)  REFERENCES cuidadores         (id_empleado)
        ON DELETE SET NULL,
    CONSTRAINT fk_ee_estado
        FOREIGN KEY (estado)       REFERENCES cat_estado_entrega (estado)
        ON UPDATE CASCADE
);


-- =============================================================================
-- BLOQUE 9: INVENTARIO Y FARMACIA
-- estado en suministros ahora referencia catálogo
-- =============================================================================

CREATE TABLE farmacias_proveedoras (
    id_farmacia  INTEGER       PRIMARY KEY,
    nombre       VARCHAR(100)  NOT NULL,
    telefono     VARCHAR(20),
    email        VARCHAR(100),
    calle        VARCHAR(100),
    numero       VARCHAR(10),
    colonia      VARCHAR(80),
    municipio    VARCHAR(80)   NOT NULL,
    estado       VARCHAR(80)   NOT NULL,
    RFC          VARCHAR(13)   NOT NULL,
    CONSTRAINT uq_farmacia_rfc UNIQUE (RFC)
);

CREATE TABLE inventario_medicinas (
    GTIN         VARCHAR(20)  NOT NULL,
    id_sede      INTEGER      NOT NULL,
    stock_actual INTEGER      NOT NULL DEFAULT 0 CHECK (stock_actual >= 0),
    stock_minimo INTEGER      NOT NULL DEFAULT 0 CHECK (stock_minimo >= 0),
    CONSTRAINT pk_inventario PRIMARY KEY (GTIN, id_sede),
    CONSTRAINT fk_inv_medicamento
        FOREIGN KEY (GTIN)    REFERENCES medicamentos (GTIN),
    CONSTRAINT fk_inv_sede
        FOREIGN KEY (id_sede) REFERENCES sedes        (id_sede)
);

CREATE TABLE suministros (
    id_suministro INTEGER      PRIMARY KEY,
    id_farmacia   INTEGER      NOT NULL,
    id_sede       INTEGER      NOT NULL,
    fecha_entrega DATE         NOT NULL,
    hora_entrega  TIME,
    estado        VARCHAR(20)  NOT NULL DEFAULT 'Pendiente',
    CONSTRAINT fk_sum_farmacia
        FOREIGN KEY (id_farmacia) REFERENCES farmacias_proveedoras  (id_farmacia)
        ON DELETE RESTRICT,
    CONSTRAINT fk_sum_sede
        FOREIGN KEY (id_sede)     REFERENCES sedes                  (id_sede)
        ON DELETE RESTRICT,
    CONSTRAINT fk_sum_estado
        FOREIGN KEY (estado)      REFERENCES cat_estado_suministro  (estado)
        ON UPDATE CASCADE
);

CREATE TABLE suministro_medicinas (
    id_suministro INTEGER      NOT NULL,
    GTIN          VARCHAR(20)  NOT NULL,
    cantidad      INTEGER      NOT NULL CHECK (cantidad > 0),
    CONSTRAINT pk_suministro_medicinas PRIMARY KEY (id_suministro, GTIN),
    CONSTRAINT fk_sm_suministro
        FOREIGN KEY (id_suministro) REFERENCES suministros  (id_suministro)
        ON DELETE CASCADE,
    CONSTRAINT fk_sm_medicamento
        FOREIGN KEY (GTIN)          REFERENCES medicamentos (GTIN)
        ON DELETE RESTRICT
);


-- =============================================================================
-- BLOQUE 10: COMEDOR
-- turno ahora referencia catálogo
-- =============================================================================

CREATE TABLE bitacora_comedor (
    id_bitacora     INTEGER       PRIMARY KEY,
    id_sede         INTEGER       NOT NULL,
    id_cocinero     INTEGER       NOT NULL,
    fecha           DATE          NOT NULL,
    turno           VARCHAR(20)   NOT NULL,
    menu_nombre     VARCHAR(100)  NOT NULL,
    cantidad_platos INTEGER       NOT NULL CHECK (cantidad_platos >= 0),
    incidencias     VARCHAR(255),
    CONSTRAINT fk_bc_sede
        FOREIGN KEY (id_sede)     REFERENCES sedes             (id_sede)
        ON DELETE RESTRICT,
    CONSTRAINT fk_bc_cocinero
        FOREIGN KEY (id_cocinero) REFERENCES cocineros          (id_empleado)
        ON DELETE RESTRICT,
    CONSTRAINT fk_bc_turno
        FOREIGN KEY (turno)       REFERENCES cat_turno_comedor  (turno)
        ON UPDATE CASCADE
);


-- =============================================================================
-- ÍNDICES DE RENDIMIENTO
-- =============================================================================

CREATE INDEX idx_pacientes_estado         ON pacientes             (id_estado);
CREATE INDEX idx_tiene_enf_paciente       ON tiene_enfermedad      (id_paciente);
CREATE INDEX idx_tiene_enf_enfermedad     ON tiene_enfermedad      (id_enfermedad);
CREATE INDEX idx_pac_contactos_paciente   ON paciente_contactos    (id_paciente);
CREATE INDEX idx_asig_cuid_cuidador       ON asignacion_cuidador   (id_cuidador);
CREATE INDEX idx_asig_cuid_paciente       ON asignacion_cuidador   (id_paciente);
CREATE INDEX idx_asig_kit_paciente        ON asignacion_kit        (id_paciente);
CREATE INDEX idx_lgps_dispositivo_fecha   ON lecturas_gps          (id_dispositivo, fecha_hora DESC);
CREATE INDEX idx_db_dispositivo_fecha     ON detecciones_beacon    (id_dispositivo, fecha_hora DESC);
CREATE INDEX idx_lnfc_dispositivo_fecha   ON lecturas_nfc          (id_dispositivo, fecha_hora DESC);
CREATE INDEX idx_lnfc_receta              ON lecturas_nfc          (id_receta);
CREATE INDEX idx_alertas_paciente         ON alertas               (id_paciente);
CREATE INDEX idx_alertas_fecha            ON alertas               (fecha_hora DESC);
CREATE INDEX idx_alertas_estatus          ON alertas               (estatus);
CREATE INDEX idx_aeo_alerta               ON alerta_evento_origen  (id_alerta);
CREATE INDEX idx_recetas_paciente         ON recetas               (id_paciente);
CREATE INDEX idx_receta_med_receta        ON receta_medicamentos   (id_receta);
CREATE INDEX idx_receta_nfc_dispositivo   ON receta_nfc            (id_dispositivo);
CREATE INDEX idx_sede_zonas_zona          ON sede_zonas            (id_zona);
CREATE INDEX idx_sede_emp_empleado        ON sede_empleados        (id_empleado);
CREATE INDEX idx_sede_emp_sede            ON sede_empleados        (id_sede);
CREATE INDEX idx_sede_pac_paciente        ON sede_pacientes        (id_paciente);
CREATE INDEX idx_sede_pac_sede            ON sede_pacientes        (id_sede);
CREATE INDEX idx_visitas_paciente         ON visitas               (id_paciente);
CREATE INDEX idx_visitas_fecha            ON visitas               (fecha_entrada DESC);
CREATE INDEX idx_visitas_sede             ON visitas               (id_sede);
CREATE INDEX idx_entregas_paciente        ON entregas_externas     (id_paciente);
CREATE INDEX idx_inventario_sede          ON inventario_medicinas  (id_sede);
CREATE INDEX idx_suministros_sede         ON suministros           (id_sede);
CREATE INDEX idx_bitacora_sede_fecha      ON bitacora_comedor      (id_sede, fecha DESC);


-- =============================================================================
-- INTEGRIDAD TEMPORAL — evitar solapamiento de periodos activos
-- Partial unique indexes: solo aplican mientras el registro está "abierto"
-- (fecha_fin / fecha_salida IS NULL), permitiendo historial cerrado ilimitado.
-- =============================================================================

-- Un paciente solo puede tener un cuidador activo a la vez
CREATE UNIQUE INDEX uq_cuidador_activo_por_paciente
    ON asignacion_cuidador (id_paciente)
    WHERE fecha_fin IS NULL;

-- Un paciente solo puede estar en una sede activa a la vez
CREATE UNIQUE INDEX uq_sede_activa_por_paciente
    ON sede_pacientes (id_paciente)
    WHERE fecha_salida IS NULL;

-- Un empleado solo puede estar activo en una sede a la vez
CREATE UNIQUE INDEX uq_sede_activa_por_empleado
    ON sede_empleados (id_empleado)
    WHERE fecha_salida IS NULL;

-- Una receta solo puede tener un dispositivo NFC activo gestionándola
CREATE UNIQUE INDEX uq_nfc_activo_por_receta
    ON receta_nfc (id_receta)
    WHERE fecha_fin_gestion IS NULL;

-- Un paciente solo puede tener un kit asignado simultáneamente
CREATE UNIQUE INDEX uq_kit_activo_por_paciente
    ON asignacion_kit (id_paciente);


-- =============================================================================
-- DATOS SEMILLA
-- =============================================================================

-- ── Catálogos ─────────────────────────────────────────────────────────────────

INSERT INTO estados_paciente (id_estado, desc_estado) VALUES
    (1, 'Activo'),
    (2, 'En Hospital'),
    (3, 'Baja');

INSERT INTO cat_tipo_dispositivo (tipo) VALUES
    ('GPS'), ('BEACON'), ('NFC');

INSERT INTO cat_estado_dispositivo (estado) VALUES
    ('Activo'), ('Inactivo'), ('Mantenimiento');

INSERT INTO cat_tipo_alerta (tipo_alerta) VALUES
    ('Salida de Zona'), ('Batería Baja'), ('Botón SOS'), ('Caída');

INSERT INTO cat_estado_alerta (estatus) VALUES
    ('Activa'), ('Atendida');

INSERT INTO cat_estado_suministro (estado) VALUES
    ('Pendiente'), ('Entregado'), ('Cancelado');

INSERT INTO cat_estado_entrega (estado) VALUES
    ('Pendiente'), ('Recibido'), ('Rechazado');

INSERT INTO cat_turno_comedor (turno) VALUES
    ('Desayuno'), ('Comida'), ('Cena');

-- ── Enfermedades y medicamentos ───────────────────────────────────────────────

INSERT INTO enfermedades (id_enfermedad, nombre_enfermedad) VALUES
    (1, 'Alzheimer'),
    (2, 'Demencia Senil'),
    (3, 'Parkinson'),
    (4, 'Hipertensión'),
    (5, 'Diabetes Tipo 2');

INSERT INTO medicamentos (GTIN, nombre_medicamento, descripcion) VALUES
    ('7501234567890', 'Donepezilo 10mg',  'Inhibidor de colinesterasa — Alzheimer leve/moderado'),
    ('7509998765432', 'Memantina 20mg',   'Antagonista NMDA — Alzheimer moderado/grave'),
    ('7508001122334', 'Amlodipino 5mg',   'Bloqueador de canales de calcio — Hipertensión'),
    ('7503456789012', 'Levodopa 250mg',   'Precursor dopaminérgico — Parkinson'),
    ('7506661234567', 'Metformina 850mg', 'Biguanida — Diabetes Tipo 2');

-- ── Pacientes ─────────────────────────────────────────────────────────────────

INSERT INTO pacientes (id_paciente, nombre, apellido_p, apellido_m, fecha_nacimiento, id_estado) VALUES
    (1, 'María',    'García',    'López',   '1942-05-10', 1),
    (2, 'Roberto',  'Pérez',     'Sosa',    '1938-11-22', 1),
    (3, 'Consuelo', 'Ramírez',   'Vega',    '1945-02-14', 2),
    (4, 'Ernesto',  'Villanueva','Morales',  '1940-07-30', 1),
    (5, 'Dolores',  'Cruz',      'Fuentes', '1937-09-05', 1);

INSERT INTO tiene_enfermedad (id_paciente, id_enfermedad, fecha_diag) VALUES
    (1, 1, '2020-03-15'),
    (1, 4, '2019-11-05'),
    (2, 1, '2019-08-01'),
    (2, 2, '2021-07-20'),
    (3, 3, '2021-03-30'),
    (3, 2, '2022-01-10'),
    (4, 1, '2018-06-14'),
    (4, 5, '2017-03-22'),
    (5, 2, '2023-02-28'),
    (5, 4, '2020-08-17');

-- ── Contactos de emergencia ───────────────────────────────────────────────────

INSERT INTO contactos_emergencia
    (id_contacto, nombre, apellido_p, apellido_m, telefono, fecha_nac, CURP_pasaporte, relacion) VALUES
    (1, 'Lucía',   'García',    'Sánchez', '8112345678', '1975-05-12', 'GASL750512MNLRCL09', 'hija'),
    (2, 'Roberto', 'Campos',    'Luna',    '8187654321', '1980-11-20', 'CALR801120HNLMNS03', 'hijo'),
    (3, 'Carmen',  'Vega',      'Torres',  '8113334444', '1978-03-08', 'VETC780308MNLGRR02', 'hija'),
    (4, 'Miguel',  'Villanueva','Ríos',    '8119876543', '1970-12-01', 'VIRM701201HNLLGS08', 'hijo'),
    (5, 'Sandra',  'Cruz',      'Paredes', '8115556666', '1965-06-20', 'CUPS650620MNLRND07', 'hija');

INSERT INTO paciente_contactos (id_paciente, id_contacto, prioridad) VALUES
    (1, 1, 1),
    (2, 2, 1),
    (3, 3, 1),
    (4, 4, 1),
    (5, 5, 1);

-- ── Empleados, cuidadores y cocineros ─────────────────────────────────────────

INSERT INTO empleados
    (id_empleado, nombre, apellido_p, apellido_m, CURP_pasaporte, fecha_nac, telefono) VALUES
    (1, 'Juan',      'Martínez', 'Ruiz',     'MARJ800101HNLRZN03', '1980-01-01', '811-100-0001'),
    (2, 'Ana',       'López',    'Torres',   'LOTA760303MNLPRN06', '1976-03-03', '811-100-0002'),
    (3, 'Luis',      'Hernández','Mora',     'HEML850615HNLRRS05', '1985-06-15', '811-100-0003'),
    (4, 'Patricia',  'Salinas',  'Garza',    'SAGP900210MNLLRT01', '1990-02-10', '811-100-0004'),
    (5, 'Tomás',     'Rivas',    'Cruz',     'RICTM780325HNLVZM02', '1978-03-25', '811-100-0005'),
    (6, 'Esperanza', 'Luna',     'Jiménez',  'LUJE820714MNLNMS04', '1982-07-14', '811-100-0006');

INSERT INTO cuidadores (id_empleado, certificacion_medica, especialidad) VALUES
    (1, 'Enfermería Geriátrica', 'Especialista'),
    (2, 'Geriatría',             'Generalista'),
    (3, 'Auxiliar de Enfermería','Generalista'),
    (4, 'Enfermería Geriátrica', 'Especialista');

INSERT INTO cocineros (id_empleado) VALUES
    (5), (6);

INSERT INTO asignacion_cuidador
    (id_asig_cuidador, id_cuidador, id_paciente, fecha_inicio, fecha_fin) VALUES
    (1, 1, 1, '2023-01-10', NULL),
    (2, 2, 2, '2022-06-01', NULL),
    (3, 2, 3, '2024-02-15', NULL),
    (4, 3, 4, '2023-08-01', NULL),
    (5, 4, 5, '2024-05-20', NULL);

-- ── Dispositivos ──────────────────────────────────────────────────────────────

INSERT INTO dispositivos (id_dispositivo, id_serial, modelo, tipo, estado, ultima_conexion) VALUES
    -- GPS
    (301, 'GPS-SN-001', 'TK103',      'GPS',    'Activo',      '2026-03-30 08:30:00'),
    (302, 'GPS-SN-002', 'TK103',      'GPS',    'Activo',      '2026-03-30 07:15:00'),
    (303, 'GPS-SN-003', 'GT06',       'GPS',    'Activo',      '2026-03-30 14:45:00'),
    (304, 'GPS-SN-004', 'GT06',       'GPS',    'Activo',      '2026-03-29 09:00:00'),
    (305, 'GPS-SN-005', 'TK103',      'GPS',    'Mantenimiento','2026-03-25 11:00:00'),
    -- Beacons
    (401, 'BCN-SN-A',   'BC001',      'BEACON', 'Activo',      '2026-03-30 09:00:00'),
    (402, 'BCN-SN-B',   'BC001',      'BEACON', 'Activo',      '2026-03-30 07:15:00'),
    (403, 'BCN-SN-C',   'BC002',      'BEACON', 'Activo',      '2026-03-30 14:45:00'),
    (404, 'BCN-SN-D',   'BC002',      'BEACON', 'Activo',      '2026-03-29 09:00:00'),
    (405, 'BCN-SN-E',   'BC001',      'BEACON', 'Inactivo',    '2026-03-20 08:00:00'),
    -- NFC
    (501, 'NFC-SN-N01', 'NFCReader1', 'NFC',    'Activo',      '2026-03-30 10:00:00'),
    (502, 'NFC-SN-N02', 'NFCReader1', 'NFC',    'Activo',      '2026-03-30 10:05:00');

-- ── Zonas seguras ─────────────────────────────────────────────────────────────

INSERT INTO zonas (id_zona, nombre_zona, latitud_centro, longitud_centro, radio_metros) VALUES
    (1, 'Jardín Norte',     25.686000, -100.316000, 50),
    (2, 'Ala Oriente',      25.685000, -100.314000, 40),
    (3, 'Patio Sur',        25.684000, -100.318000, 60),
    (4, 'Sala de Terapia',  25.685500, -100.315500, 30),
    (5, 'Comedor Central',  25.685800, -100.316500, 35);

-- gateways y zona_beacons eliminados — no se insertan datos semilla.

-- ── Kits de monitoreo ─────────────────────────────────────────────────────────
-- Cada kit ahora solo incluye el dispositivo GPS; los beacons son fixtures del edificio.

INSERT INTO asignacion_kit
    (id_monitoreo, id_paciente, id_dispositivo_gps, fecha_entrega) VALUES
    (1, 1, 301, '2024-01-10'),
    (2, 2, 302, '2024-01-15'),
    (3, 3, 303, '2024-02-20'),
    (4, 4, 304, '2024-03-01'),
    (5, 5, 305, '2024-05-20');

-- ── Lecturas GPS ──────────────────────────────────────────────────────────────
-- Escenario 1: María (pac 1) sale de Jardín Norte — excede radio de 50 m

INSERT INTO lecturas_gps
    (id_lectura, id_dispositivo, fecha_hora, latitud, longitud, altura, nivel_bateria) VALUES
    (1,  301, '2026-03-30 08:00:00', 25.686050, -100.316020, NULL, 85),
    (2,  301, '2026-03-30 08:15:00', 25.686400, -100.316500, NULL, 84),  -- dentro
    (3,  301, '2026-03-30 08:30:00', 25.686900, -100.317200, NULL, 83),  -- salida de zona
    (4,  302, '2026-03-30 07:10:00', 25.685100, -100.314050, NULL, 60),
    (5,  302, '2026-03-30 07:30:00', 25.685200, -100.314100, NULL, 59),
    (6,  303, '2026-03-30 14:00:00', 25.684050, -100.318010, NULL, 72),
    (7,  304, '2026-03-29 09:00:00', 25.685550, -100.315510, NULL, 90),
    -- Escenario 4: GPS-SN-005 reporta batería crítica
    (8,  305, '2026-03-29 11:00:00', 25.685900, -100.316600, NULL, 8);

-- ── Detecciones beacon ────────────────────────────────────────────────────────
-- Registradas por el teléfono del cuidador vía Web Bluetooth (sin gateway).

INSERT INTO detecciones_beacon
    (id_deteccion, id_dispositivo, fecha_hora, rssi) VALUES
    (1, 401, '2026-03-30 08:00:00', -72),
    (2, 401, '2026-03-30 08:15:00', -68),
    (3, 402, '2026-03-30 07:10:00', -80),
    (4, 402, '2026-03-30 07:30:00', -78),
    (5, 403, '2026-03-30 14:00:00', -55),
    (6, 404, '2026-03-29 09:00:00', -65);

-- ── Alertas ───────────────────────────────────────────────────────────────────
-- Escenario 1 — Salida de zona (María, pac 1)
-- Escenario 4 — Batería baja (Dolores, pac 5)
-- Escenario adicional — Botón SOS y Caída

INSERT INTO alertas (id_alerta, id_paciente, tipo_alerta, fecha_hora, estatus) VALUES
    (1, 1, 'Salida de Zona', '2026-03-30 08:31:00', 'Activa'),
    (2, 2, 'Batería Baja',   '2026-03-28 14:22:00', 'Atendida'),
    (3, 5, 'Batería Baja',   '2026-03-29 11:05:00', 'Activa'),
    (4, 3, 'Botón SOS',      '2026-03-29 03:15:00', 'Atendida'),
    (5, 4, 'Caída',          '2026-03-30 06:50:00', 'Activa');

-- ── Trazabilidad de alertas (NUEVO) ──────────────────────────────────────────
-- Cada alerta vinculada al evento IoT que la originó

-- Fila 4 eliminada: era tipo BEACON (referenciaba id_deteccion=5 y un gateway).
-- La alerta de Botón SOS (id_alerta=4) ahora es de tipo 'SOS' originada por GPS.
INSERT INTO alerta_evento_origen
    (id_origen, id_alerta, tipo_evento, id_lectura_gps, regla_disparada) VALUES
    (1, 1, 'GPS', 3, 'Distancia al centro de zona > radio_metros (50 m)'),
    (2, 2, 'GPS', 5, 'nivel_bateria <= 15 en dispositivo GPS-SN-002'),
    (3, 3, 'GPS', 8, 'nivel_bateria <= 15 en dispositivo GPS-SN-005'),
    (4, 4, 'SOS', NULL, 'Botón SOS activado en dispositivo GPS-SN-003'),
    (5, 5, 'GPS', 7, 'Aceleración brusca detectada — posible caída');

-- ── Recetas y medicación ──────────────────────────────────────────────────────
-- NOTA: id_paciente en recetas es la fuente única de verdad (sin paciente_recetas)

INSERT INTO recetas (id_receta, fecha, id_paciente) VALUES
    (901, '2026-01-10', 1),   -- María
    (902, '2026-01-15', 2),   -- Roberto
    (903, '2026-02-20', 3),   -- Consuelo
    (904, '2026-03-01', 4),   -- Ernesto
    (905, '2026-03-20', 5);   -- Dolores

INSERT INTO receta_medicamentos (id_detalle, id_receta, GTIN, dosis, frecuencia_horas) VALUES
    (1, 901, '7501234567890', '10mg', 24),
    (2, 901, '7508001122334', '5mg',  24),
    (3, 902, '7501234567890', '10mg', 24),
    (4, 902, '7509998765432', '20mg', 12),
    (5, 903, '7503456789012', '250mg', 8),
    (6, 904, '7501234567890', '10mg', 24),
    (7, 904, '7506661234567', '850mg', 8),
    (8, 905, '7509998765432', '20mg', 24);

INSERT INTO receta_nfc (id_receta, id_dispositivo, fecha_inicio_gestion, fecha_fin_gestion) VALUES
    (901, 501, '2026-01-10', NULL),
    (902, 502, '2026-01-15', NULL);

-- ── Lecturas NFC (NUEVO) ──────────────────────────────────────────────────────
-- Escenario 3: adherencia terapéutica de María (receta 901, NFC 501)
-- Escenario 3: cambio de receta — Ernesto (receta 904, NFC sin asignar aún)

INSERT INTO lecturas_nfc
    (id_lectura_nfc, id_dispositivo, id_receta, fecha_hora, tipo_lectura, resultado) VALUES
    (1, 501, 901, '2026-03-28 08:02:00', 'Administración', 'Exitosa'),
    (2, 501, 901, '2026-03-29 08:05:00', 'Administración', 'Exitosa'),
    (3, 501, 901, '2026-03-30 08:10:00', 'Administración', 'Exitosa'),
    (4, 502, 902, '2026-03-28 08:00:00', 'Administración', 'Exitosa'),
    (5, 502, 902, '2026-03-29 08:00:00', 'Verificación',   'Exitosa'),
    -- Rechazo de medicamento — Escenario 3 (inconsistencia NFC)
    (6, 502, 902, '2026-03-30 08:00:00', 'Administración', 'Fallida');

-- ── Sedes ─────────────────────────────────────────────────────────────────────

INSERT INTO sedes (id_sede, nombre_sede, calle, numero, municipio, estado) VALUES
    (1, 'Sede Norte',  'Av. Insurgentes Norte', '2140', 'Monterrey',  'Nuevo León'),
    (2, 'Sede Centro', 'Calle Morelos',         '300',  'Monterrey',  'Nuevo León'),
    (3, 'Sede Sur',    'Blvd. Manuel Ávila',    '500',  'San Pedro',  'Nuevo León');

INSERT INTO sede_zonas (id_sede, id_zona) VALUES
    (1, 1), (1, 4), (1, 5),
    (2, 2),
    (3, 3);

INSERT INTO sede_empleados
    (id_sede_empleado, id_sede, id_empleado, fecha_ingreso, hora_ingreso, fecha_salida, hora_salida) VALUES
    (1, 1, 1, '2024-01-10', '08:00:00', NULL, NULL),
    (2, 1, 2, '2024-01-10', '08:00:00', NULL, NULL),
    (3, 1, 5, '2024-01-10', '07:00:00', NULL, NULL),
    (4, 2, 3, '2024-02-15', '08:00:00', NULL, NULL),
    (5, 3, 4, '2024-03-01', '08:00:00', NULL, NULL),
    (6, 3, 6, '2024-03-01', '07:00:00', NULL, NULL);

-- Escenario 2: Consuelo (pac 3) viene de Sede Norte, fue transferida a Sede Sur
INSERT INTO sede_pacientes
    (id_sede_paciente, id_sede, id_paciente, fecha_ingreso, hora_ingreso, fecha_salida, hora_salida) VALUES
    (1, 1, 1, '2024-01-10', '09:00:00', NULL,         NULL),          -- María — Sede Norte
    (2, 2, 2, '2024-01-15', '10:00:00', NULL,         NULL),          -- Roberto — Sede Centro
    (3, 1, 3, '2024-02-20', '09:00:00', '2025-06-30', '17:00:00'),    -- Consuelo — Sede Norte (salió)
    (4, 3, 3, '2025-07-01', '09:00:00', NULL,         NULL),          -- Consuelo — Sede Sur (actual)
    (5, 2, 4, '2024-03-01', '11:00:00', NULL,         NULL),          -- Ernesto — Sede Centro
    (6, 3, 5, '2024-05-20', '10:00:00', NULL,         NULL);          -- Dolores — Sede Sur

-- ── Visitantes y visitas ──────────────────────────────────────────────────────

INSERT INTO visitantes
    (id_visitante, nombre, apellido_p, apellido_m, relacion, telefono, CURP_pasaporte) VALUES
    (1, 'Lucía',   'García',    'Sánchez', 'hija',   '811-234-5678', 'GASL750512MNLRCL09'),
    (2, 'Roberto', 'Campos',    'Luna',    'hijo',   '811-876-5432', 'CALR801120HNLMNS03'),
    (3, 'Carmen',  'Vega',      'Torres',  'hija',   '811-333-4444', 'VETC780308MNLGRR02'),
    (4, 'Miguel',  'Villanueva','Ríos',    'hijo',   '811-987-6543', 'VIRM701201HNLLGS08'),
    (5, 'Sandra',  'Cruz',      'Paredes', 'hija',   '811-555-6666', 'CUPS650620MNLRND07');

INSERT INTO visitas
    (id_visita, id_paciente, id_visitante, id_sede, fecha_entrada, hora_entrada, fecha_salida, hora_salida) VALUES
    (1, 1, 1, 1, '2026-03-28', '10:00:00', '2026-03-28', '12:30:00'),
    (2, 2, 2, 2, '2026-03-29', '11:00:00', '2026-03-29', '13:00:00'),
    (3, 3, 3, 3, '2026-03-29', '14:00:00', '2026-03-29', '16:00:00'),
    (4, 4, 4, 2, '2026-03-30', '09:30:00', NULL,         NULL),
    (5, 5, 5, 3, '2026-03-30', '10:15:00', '2026-03-30', '11:45:00');

INSERT INTO entregas_externas
    (id_entrega, id_paciente, id_visitante, id_cuidador, descripcion, estado, fecha_recepcion, hora_recepcion) VALUES
    (1, 1, 1, 1, 'Ropa y artículos personales',               'Recibido',  '2026-03-28', '10:05:00'),
    (2, 2, 2, 2, 'Libro y artículos de aseo',                  'Recibido',  '2026-03-29', '11:10:00'),
    (3, 4, 4, 3, 'Medicamento externo (requiere autorización)', 'Pendiente', '2026-03-30', '09:35:00');

-- ── Farmacia e inventario ─────────────────────────────────────────────────────
-- Escenario 5: stock crítico en Donepezilo (ambas sedes con mínimo no cubierto)

INSERT INTO farmacias_proveedoras
    (id_farmacia, nombre, telefono, email, calle, numero, colonia, municipio, estado, RFC) VALUES
    (1, 'Farmacia del Ahorro', '818-123-4567', 'ahorro@farm.mx',
        'Av. Garza Sada', '2501', 'Tecnológico', 'Monterrey', 'Nuevo León', 'FAH900101AA1'),
    (2, 'Benavides',           '818-987-6543', 'info@ben.mx',
        'Av. Constitución', '300', 'Centro',     'San Pedro',  'Nuevo León', 'BEN850615BB2');

INSERT INTO inventario_medicinas (GTIN, id_sede, stock_actual, stock_minimo) VALUES
    -- Sede Norte
    ('7501234567890', 1,  8, 20),   -- Donepezilo CRÍTICO (8 < 20)
    ('7509998765432', 1, 35, 10),
    ('7508001122334', 1, 40, 15),
    ('7503456789012', 1, 12,  5),
    -- Sede Centro
    ('7501234567890', 2,  5, 20),   -- Donepezilo CRÍTICO (5 < 20)
    ('7509998765432', 2, 18, 10),
    ('7506661234567', 2,  3, 10),   -- Metformina CRÍTICO (3 < 10)
    -- Sede Sur
    ('7503456789012', 3, 10,  5),
    ('7509998765432', 3,  7, 10);   -- Memantina CRÍTICO (7 < 10)

-- Escenario 5: órdenes de suministro generadas por stock crítico
INSERT INTO suministros
    (id_suministro, id_farmacia, id_sede, fecha_entrega, hora_entrega, estado) VALUES
    (1, 1, 1, '2026-04-02', '09:00:00', 'Pendiente'),  -- para Sede Norte
    (2, 2, 2, '2026-04-03', '10:00:00', 'Pendiente'),  -- para Sede Centro
    (3, 1, 3, '2026-04-04', '09:30:00', 'Pendiente'),  -- para Sede Sur
    (4, 1, 1, '2026-03-10', '09:00:00', 'Entregado'),
    (5, 2, 2, '2026-03-12', '10:30:00', 'Entregado');

INSERT INTO suministro_medicinas (id_suministro, GTIN, cantidad) VALUES
    (1, '7501234567890', 60),   -- Donepezilo → Sede Norte
    (1, '7508001122334', 40),
    (2, '7501234567890', 60),   -- Donepezilo → Sede Centro
    (2, '7506661234567', 40),   -- Metformina → Sede Centro
    (3, '7509998765432', 30),   -- Memantina → Sede Sur
    (4, '7501234567890', 100),
    (5, '7509998765432',  50);

-- ── Bitácora comedor ──────────────────────────────────────────────────────────

INSERT INTO bitacora_comedor
    (id_bitacora, id_sede, id_cocinero, fecha, turno, menu_nombre, cantidad_platos, incidencias) VALUES
    (1, 1, 5, CURRENT_DATE, 'Desayuno', 'Avena con fruta y jugo de naranja',         3, NULL),
    (2, 1, 5, CURRENT_DATE, 'Comida',   'Caldo de pollo, arroz integral, gelatina',  3, 'Pac. Roberto rechazó el caldo, se sustituyó por sopa.'),
    (3, 2, 5, CURRENT_DATE, 'Desayuno', 'Huevos revueltos, frijoles, tortillas',     2, NULL),
    (4, 3, 6, CURRENT_DATE, 'Desayuno', 'Yogurt con granola y fruta',                2, NULL),
    (5, 3, 6, CURRENT_DATE, 'Comida',   'Sopa de lentejas, pechuga a la plancha',    2, NULL);
