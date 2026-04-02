CREATE DATABASE alzheimer_db;

-- =============================================================================
-- BLOQUE 1: CATÁLOGOS BASE
-- =============================================================================

-- 1. ESTADOS_PACIENTE
CREATE TABLE estados_paciente (
    id_estado    INTEGER      PRIMARY KEY,
    desc_estado  VARCHAR(50)  NOT NULL,
    CONSTRAINT uq_desc_estado UNIQUE (desc_estado)
);

-- 2. ENFERMEDADES
CREATE TABLE enfermedades (
    id_enfermedad     INTEGER       PRIMARY KEY,
    nombre_enfermedad VARCHAR(100)  NOT NULL,
    CONSTRAINT uq_nombre_enfermedad UNIQUE (nombre_enfermedad)
);

-- 3. MEDICAMENTOS
CREATE TABLE medicamentos (
    GTIN               VARCHAR(20)   PRIMARY KEY,
    nombre_medicamento VARCHAR(100)  NOT NULL,
    descripcion        VARCHAR(255),
    CONSTRAINT uq_nombre_medicamento UNIQUE (nombre_medicamento)
);


-- =============================================================================
-- BLOQUE 2: PACIENTES Y SUS RELACIONES
-- =============================================================================

-- 4. PACIENTES
CREATE TABLE pacientes (
    id_paciente      INTEGER      PRIMARY KEY,
    nombre           VARCHAR(80)  NOT NULL,
    apellido_p       VARCHAR(80)  NOT NULL,
    apellido_m       VARCHAR(80)  NOT NULL,
    fecha_nacimiento DATE         NOT NULL,
    id_estado        INTEGER      NOT NULL,
    CONSTRAINT fk_paciente_estado
        FOREIGN KEY (id_estado) REFERENCES estados_paciente (id_estado)
);

-- 5. TIENE_ENFERMEDAD
CREATE TABLE tiene_enfermedad (
    id_paciente   INTEGER  NOT NULL,
    id_enfermedad INTEGER  NOT NULL,
    fecha_diag    DATE     NOT NULL,
    CONSTRAINT pk_tiene_enfermedad PRIMARY KEY (id_paciente, id_enfermedad),
    CONSTRAINT fk_te_paciente
        FOREIGN KEY (id_paciente)   REFERENCES pacientes    (id_paciente),
    CONSTRAINT fk_te_enfermedad
        FOREIGN KEY (id_enfermedad) REFERENCES enfermedades (id_enfermedad)
);

-- 6. CONTACTOS_EMERGENCIA
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

-- 7. PACIENTE_CONTACTOS
CREATE TABLE paciente_contactos (
    id_paciente  INTEGER  NOT NULL,
    id_contacto  INTEGER  NOT NULL,
    prioridad    INTEGER  NOT NULL CHECK (prioridad > 0),
    CONSTRAINT pk_paciente_contactos PRIMARY KEY (id_paciente, id_contacto),
    CONSTRAINT fk_pc_paciente
        FOREIGN KEY (id_paciente) REFERENCES pacientes            (id_paciente),
    CONSTRAINT fk_pc_contacto
        FOREIGN KEY (id_contacto) REFERENCES contactos_emergencia (id_contacto),
    CONSTRAINT uq_pc_prioridad UNIQUE (id_paciente, prioridad)
);


-- =============================================================================
-- BLOQUE 3: EMPLEADOS Y ROLES
-- =============================================================================

-- 8. EMPLEADOS  (supertipo)
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

-- 9. CUIDADORES  (subtipo de empleados)
CREATE TABLE cuidadores (
    id_empleado          INTEGER       PRIMARY KEY,
    certificacion_medica VARCHAR(100),
    especialidad         VARCHAR(100),
    CONSTRAINT fk_cuidador_empleado
        FOREIGN KEY (id_empleado) REFERENCES empleados (id_empleado)
);

-- 10. COCINEROS  (subtipo de empleados)
CREATE TABLE cocineros (
    id_empleado INTEGER PRIMARY KEY,
    CONSTRAINT fk_cocinero_empleado
        FOREIGN KEY (id_empleado) REFERENCES empleados (id_empleado)
);

-- 11. ASIGNACION_CUIDADOR
CREATE TABLE asignacion_cuidador (
    id_asig_cuidador  INTEGER  PRIMARY KEY,
    id_cuidador       INTEGER  NOT NULL,
    id_paciente       INTEGER  NOT NULL,
    fecha_inicio      DATE     NOT NULL,
    fecha_fin         DATE,
    CONSTRAINT fk_ac_cuidador
        FOREIGN KEY (id_cuidador)  REFERENCES cuidadores (id_empleado),
    CONSTRAINT fk_ac_paciente
        FOREIGN KEY (id_paciente)  REFERENCES pacientes  (id_paciente),
    CONSTRAINT chk_ac_fechas CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)
);


-- =============================================================================
-- BLOQUE 4: DISPOSITIVOS Y ZONAS
-- =============================================================================

-- 12. DISPOSITIVOS  (supertipo: GPS, Beacon, NFC)
CREATE TABLE dispositivos (
    id_dispositivo  INTEGER      PRIMARY KEY,
    id_serial       VARCHAR(50)  NOT NULL,
    modelo          VARCHAR(50)  NOT NULL,
    tipo            VARCHAR(10)  NOT NULL,
    estado          VARCHAR(20)  NOT NULL DEFAULT 'Activo',
    ultima_conexion TIMESTAMP,
    CONSTRAINT uq_dispositivo_serial UNIQUE (id_serial),
    CONSTRAINT chk_tipo_dispositivo  CHECK  (tipo IN ('GPS', 'BEACON', 'NFC')),
    CONSTRAINT chk_estado_dispositivo CHECK (estado IN ('Activo', 'Inactivo', 'Mantenimiento'))
);

-- 13. ZONAS
CREATE TABLE zonas (
    id_zona         INTEGER       PRIMARY KEY,
    nombre_zona     VARCHAR(100)  NOT NULL,
    latitud_centro  NUMERIC(10,6) NOT NULL,
    longitud_centro NUMERIC(10,6) NOT NULL,
    radio_metros    NUMERIC(8,2)  NOT NULL CHECK (radio_metros > 0),
    CONSTRAINT uq_nombre_zona UNIQUE (nombre_zona)
);

-- 14. GATEWAYS
CREATE TABLE gateways (
    id_gateway  INTEGER      PRIMARY KEY,
    modelo      VARCHAR(50)  NOT NULL,
    id_zona     INTEGER      NOT NULL,
    CONSTRAINT fk_gw_zona
        FOREIGN KEY (id_zona) REFERENCES zonas (id_zona)
);

-- 15. ZONA_BEACONS
CREATE TABLE zona_beacons (
    id_zona              INTEGER      NOT NULL,
    id_dispositivo       INTEGER      NOT NULL,
    descripcion_ubicacion VARCHAR(100),
    CONSTRAINT pk_zona_beacons PRIMARY KEY (id_zona, id_dispositivo),
    CONSTRAINT fk_zb_zona
        FOREIGN KEY (id_zona)         REFERENCES zonas       (id_zona),
    CONSTRAINT fk_zb_dispositivo
        FOREIGN KEY (id_dispositivo)  REFERENCES dispositivos (id_dispositivo)
);

-- 16. ASIGNACION_KIT
CREATE TABLE asignacion_kit (
    id_monitoreo          INTEGER  PRIMARY KEY,
    id_paciente           INTEGER  NOT NULL,
    id_dispositivo_gps    INTEGER  NOT NULL,
    id_dispositivo_beacon INTEGER  NOT NULL,
    fecha_entrega         DATE,
    CONSTRAINT fk_ak_paciente
        FOREIGN KEY (id_paciente)           REFERENCES pacientes    (id_paciente),
    CONSTRAINT fk_ak_gps
        FOREIGN KEY (id_dispositivo_gps)    REFERENCES dispositivos (id_dispositivo),
    CONSTRAINT fk_ak_beacon
        FOREIGN KEY (id_dispositivo_beacon) REFERENCES dispositivos (id_dispositivo),
    CONSTRAINT uq_ak_gps    UNIQUE (id_dispositivo_gps),
    CONSTRAINT uq_ak_beacon UNIQUE (id_dispositivo_beacon),
    CONSTRAINT chk_ak_disp_distintos CHECK (id_dispositivo_gps <> id_dispositivo_beacon)
);


-- =============================================================================
-- BLOQUE 5: EVENTOS Y ALERTAS
-- =============================================================================

-- 17. LECTURAS_GPS
CREATE TABLE lecturas_gps (
    id_lectura     INTEGER        PRIMARY KEY,
    id_dispositivo INTEGER        NOT NULL,
    fecha_hora     TIMESTAMP      NOT NULL,
    latitud        NUMERIC(10,6)  NOT NULL,
    longitud       NUMERIC(10,6)  NOT NULL,
    altura         NUMERIC(8,2),
    nivel_bateria  INTEGER        CHECK (nivel_bateria BETWEEN 0 AND 100),
    CONSTRAINT fk_lgps_dispositivo
        FOREIGN KEY (id_dispositivo) REFERENCES dispositivos (id_dispositivo),
    CONSTRAINT uq_lgps_instante UNIQUE (id_dispositivo, fecha_hora)
);

-- 18. DETECCIONES_BEACON
CREATE TABLE detecciones_beacon (
    id_deteccion   INTEGER    PRIMARY KEY,
    id_dispositivo INTEGER    NOT NULL,
    id_gateway     INTEGER    NOT NULL,
    fecha_hora     TIMESTAMP  NOT NULL,
    rssi           INTEGER    NOT NULL,
    CONSTRAINT fk_db_dispositivo
        FOREIGN KEY (id_dispositivo) REFERENCES dispositivos (id_dispositivo),
    CONSTRAINT fk_db_gateway
        FOREIGN KEY (id_gateway)     REFERENCES gateways     (id_gateway),
    CONSTRAINT uq_db_instante UNIQUE (id_dispositivo, id_gateway, fecha_hora)
);

-- 19. ALERTAS
CREATE TABLE alertas (
    id_alerta   INTEGER      PRIMARY KEY,
    id_paciente INTEGER      NOT NULL,
    tipo_alerta VARCHAR(50)  NOT NULL,
    fecha_hora  TIMESTAMP    NOT NULL,
    estatus     VARCHAR(20)  NOT NULL DEFAULT 'Activa',
    CONSTRAINT fk_alerta_paciente
        FOREIGN KEY (id_paciente) REFERENCES pacientes (id_paciente),
    CONSTRAINT chk_tipo_alerta    CHECK (tipo_alerta IN ('Salida de Zona', 'Batería Baja', 'Botón SOS', 'Caída')),
    CONSTRAINT chk_estatus_alerta CHECK (estatus      IN ('Activa', 'Atendida')),
    CONSTRAINT uq_alerta_unica    UNIQUE (id_paciente, tipo_alerta, fecha_hora)
);


-- =============================================================================
-- BLOQUE 6: RECETAS Y MEDICACIÓN
-- =============================================================================

-- 20. RECETAS
CREATE TABLE recetas (
    id_receta   INTEGER  PRIMARY KEY,
    fecha       DATE     NOT NULL,
    id_paciente INTEGER  NOT NULL,
    CONSTRAINT fk_receta_paciente
        FOREIGN KEY (id_paciente) REFERENCES pacientes (id_paciente)
);

-- 21. RECETA_MEDICAMENTOS
CREATE TABLE receta_medicamentos (
    id_detalle       INTEGER      PRIMARY KEY,
    id_receta        INTEGER      NOT NULL,
    GTIN             VARCHAR(20)  NOT NULL,
    dosis            VARCHAR(50)  NOT NULL,
    frecuencia_horas INTEGER      NOT NULL CHECK (frecuencia_horas > 0),
    CONSTRAINT fk_rm_receta
        FOREIGN KEY (id_receta) REFERENCES recetas      (id_receta),
    CONSTRAINT fk_rm_medicamento
        FOREIGN KEY (GTIN)      REFERENCES medicamentos (GTIN)
);

-- 22. PACIENTE_RECETAS
CREATE TABLE paciente_recetas (
    id_paciente              INTEGER  NOT NULL,
    id_receta                INTEGER  NOT NULL,
    fecha_inicio_prescripcion DATE    NOT NULL,
    fecha_fin_prescripcion    DATE,
    CONSTRAINT pk_paciente_recetas PRIMARY KEY (id_paciente, id_receta),
    CONSTRAINT fk_pr_paciente
        FOREIGN KEY (id_paciente) REFERENCES pacientes (id_paciente),
    CONSTRAINT fk_pr_receta
        FOREIGN KEY (id_receta)   REFERENCES recetas   (id_receta),
    CONSTRAINT chk_pr_fechas CHECK (fecha_fin_prescripcion IS NULL OR fecha_fin_prescripcion >= fecha_inicio_prescripcion)
);

-- 23. RECETA_NFC
CREATE TABLE receta_nfc (
    id_receta          INTEGER  NOT NULL,
    id_dispositivo     INTEGER  NOT NULL,
    fecha_inicio_gestion DATE   NOT NULL,
    fecha_fin_gestion   DATE,
    CONSTRAINT pk_receta_nfc PRIMARY KEY (id_receta, id_dispositivo),
    CONSTRAINT fk_rn_receta
        FOREIGN KEY (id_receta)       REFERENCES recetas      (id_receta),
    CONSTRAINT fk_rn_dispositivo
        FOREIGN KEY (id_dispositivo)  REFERENCES dispositivos (id_dispositivo),
    CONSTRAINT chk_rn_fechas CHECK (fecha_fin_gestion IS NULL OR fecha_fin_gestion >= fecha_inicio_gestion)
);


-- =============================================================================
-- BLOQUE 7: SEDES
-- =============================================================================

-- 24. SEDES
CREATE TABLE sedes (
    id_sede     INTEGER       PRIMARY KEY,
    nombre_sede VARCHAR(100)  NOT NULL,
    calle       VARCHAR(100)  NOT NULL,
    numero      VARCHAR(10)   NOT NULL,
    municipio   VARCHAR(80)   NOT NULL,
    estado      VARCHAR(80)   NOT NULL,
    CONSTRAINT uq_nombre_sede UNIQUE (nombre_sede)
);

-- 25. SEDE_ZONAS
CREATE TABLE sede_zonas (
    id_sede  INTEGER  NOT NULL,
    id_zona  INTEGER  NOT NULL,
    CONSTRAINT pk_sede_zonas PRIMARY KEY (id_sede, id_zona),
    CONSTRAINT fk_sz_sede
        FOREIGN KEY (id_sede) REFERENCES sedes (id_sede),
    CONSTRAINT fk_sz_zona
        FOREIGN KEY (id_zona) REFERENCES zonas (id_zona)
);

-- 26. SEDE_EMPLEADOS
CREATE TABLE sede_empleados (
    id_sede_empleado  INTEGER    PRIMARY KEY,
    id_sede           INTEGER    NOT NULL,
    id_empleado       INTEGER    NOT NULL,
    fecha_ingreso     DATE       NOT NULL,
    hora_ingreso      TIME       NOT NULL,
    fecha_salida      DATE,
    hora_salida       TIME,
    CONSTRAINT fk_se_sede
        FOREIGN KEY (id_sede)     REFERENCES sedes     (id_sede),
    CONSTRAINT fk_se_empleado
        FOREIGN KEY (id_empleado) REFERENCES empleados (id_empleado),
    CONSTRAINT chk_se_fechas CHECK (fecha_salida IS NULL OR fecha_salida >= fecha_ingreso)
);

-- 27. SEDE_PACIENTES
CREATE TABLE sede_pacientes (
    id_sede_paciente  INTEGER    PRIMARY KEY,
    id_sede           INTEGER    NOT NULL,
    id_paciente       INTEGER    NOT NULL,
    fecha_ingreso     DATE       NOT NULL,
    hora_ingreso      TIME       NOT NULL,
    fecha_salida      DATE,
    hora_salida       TIME,
    CONSTRAINT fk_sp_sede
        FOREIGN KEY (id_sede)     REFERENCES sedes     (id_sede),
    CONSTRAINT fk_sp_paciente
        FOREIGN KEY (id_paciente) REFERENCES pacientes (id_paciente),
    CONSTRAINT chk_sp_fechas CHECK (fecha_salida IS NULL OR fecha_salida >= fecha_ingreso)
);


-- =============================================================================
-- BLOQUE 8: VISITAS Y ENTREGAS
-- =============================================================================

-- 28. VISITANTES
CREATE TABLE visitantes (
    id_visitante   INTEGER      PRIMARY KEY,
    nombre         VARCHAR(80)  NOT NULL,
    apellido_p     VARCHAR(80)  NOT NULL,
    apellido_m     VARCHAR(80),
    relacion       VARCHAR(50)  NOT NULL,
    telefono       VARCHAR(20)  NOT NULL,
    CURP_pasaporte VARCHAR(20)
);

-- 29. VISITAS
CREATE TABLE visitas (
    id_visita      INTEGER    PRIMARY KEY,
    id_paciente    INTEGER    NOT NULL,
    id_visitante   INTEGER    NOT NULL,
    id_sede        INTEGER    NOT NULL,
    fecha_entrada  DATE       NOT NULL,
    hora_entrada   TIME       NOT NULL,
    fecha_salida   DATE,
    hora_salida    TIME,
    CONSTRAINT fk_vis_paciente
        FOREIGN KEY (id_paciente)  REFERENCES pacientes  (id_paciente),
    CONSTRAINT fk_vis_visitante
        FOREIGN KEY (id_visitante) REFERENCES visitantes (id_visitante),
    CONSTRAINT fk_vis_sede
        FOREIGN KEY (id_sede)      REFERENCES sedes      (id_sede),
    CONSTRAINT chk_vis_fechas CHECK (fecha_salida IS NULL OR fecha_salida >= fecha_entrada)
);

-- 30. ENTREGAS_EXTERNAS
CREATE TABLE entregas_externas (
    id_entrega      INTEGER       PRIMARY KEY,
    id_paciente     INTEGER       NOT NULL,
    id_visitante    INTEGER       NOT NULL,
    id_cuidador     INTEGER,
    descripcion     VARCHAR(255)  NOT NULL,
    estado          VARCHAR(30)   NOT NULL DEFAULT 'Pendiente',
    fecha_recepcion DATE          NOT NULL,
    hora_recepcion  TIME          NOT NULL,
    CONSTRAINT fk_ee_paciente
        FOREIGN KEY (id_paciente)  REFERENCES pacientes  (id_paciente),
    CONSTRAINT fk_ee_visitante
        FOREIGN KEY (id_visitante) REFERENCES visitantes (id_visitante),
    CONSTRAINT fk_ee_cuidador
        FOREIGN KEY (id_cuidador)  REFERENCES cuidadores (id_empleado),
    CONSTRAINT chk_ee_estado CHECK (estado IN ('Pendiente', 'Recibido', 'Rechazado'))
);


-- =============================================================================
-- BLOQUE 9: INVENTARIO Y FARMACIA
-- =============================================================================

-- 31. FARMACIAS_PROVEEDORAS
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

-- 32. INVENTARIO_MEDICINAS
CREATE TABLE inventario_medicinas (
    GTIN          VARCHAR(20)  NOT NULL,
    id_sede       INTEGER      NOT NULL,
    stock_actual  INTEGER      NOT NULL DEFAULT 0 CHECK (stock_actual >= 0),
    stock_minimo  INTEGER      NOT NULL DEFAULT 0 CHECK (stock_minimo >= 0),
    CONSTRAINT pk_inventario PRIMARY KEY (GTIN, id_sede),
    CONSTRAINT fk_inv_medicamento
        FOREIGN KEY (GTIN)    REFERENCES medicamentos (GTIN),
    CONSTRAINT fk_inv_sede
        FOREIGN KEY (id_sede) REFERENCES sedes        (id_sede)
);

-- 33. SUMINISTROS
CREATE TABLE suministros (
    id_suministro  INTEGER      PRIMARY KEY,
    id_farmacia    INTEGER      NOT NULL,
    id_sede        INTEGER      NOT NULL,
    fecha_entrega  DATE         NOT NULL,
    hora_entrega   TIME,
    estado         VARCHAR(30)  NOT NULL DEFAULT 'Pendiente',
    CONSTRAINT fk_sum_farmacia
        FOREIGN KEY (id_farmacia) REFERENCES farmacias_proveedoras (id_farmacia),
    CONSTRAINT fk_sum_sede
        FOREIGN KEY (id_sede)     REFERENCES sedes                 (id_sede),
    CONSTRAINT chk_sum_estado CHECK (estado IN ('Pendiente', 'Entregado', 'Cancelado'))
);

-- 34. SUMINISTRO_MEDICINAS
CREATE TABLE suministro_medicinas (
    id_suministro  INTEGER      NOT NULL,
    GTIN           VARCHAR(20)  NOT NULL,
    cantidad       INTEGER      NOT NULL CHECK (cantidad > 0),
    CONSTRAINT pk_suministro_medicinas PRIMARY KEY (id_suministro, GTIN),
    CONSTRAINT fk_sm_suministro
        FOREIGN KEY (id_suministro) REFERENCES suministros  (id_suministro),
    CONSTRAINT fk_sm_medicamento
        FOREIGN KEY (GTIN)          REFERENCES medicamentos (GTIN)
);


-- =============================================================================
-- BLOQUE 10: COMEDOR
-- =============================================================================

-- 35. BITACORA_COMEDOR
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
        FOREIGN KEY (id_sede)     REFERENCES sedes     (id_sede),
    CONSTRAINT fk_bc_cocinero
        FOREIGN KEY (id_cocinero) REFERENCES cocineros (id_empleado),
    CONSTRAINT chk_bc_turno CHECK (turno IN ('Desayuno', 'Comida', 'Cena'))
);


-- =============================================================================
-- ÍNDICES DE RENDIMIENTO
-- =============================================================================

-- Pacientes
CREATE INDEX idx_pacientes_estado             ON pacientes             (id_estado);

-- Enfermedades
CREATE INDEX idx_tiene_enf_paciente           ON tiene_enfermedad      (id_paciente);
CREATE INDEX idx_tiene_enf_enfermedad         ON tiene_enfermedad      (id_enfermedad);

-- Contactos
CREATE INDEX idx_pac_contactos_paciente       ON paciente_contactos    (id_paciente);

-- Empleados / roles
CREATE INDEX idx_asig_cuid_cuidador           ON asignacion_cuidador   (id_cuidador);
CREATE INDEX idx_asig_cuid_paciente           ON asignacion_cuidador   (id_paciente);

-- Dispositivos
CREATE INDEX idx_asig_kit_paciente            ON asignacion_kit        (id_paciente);
CREATE INDEX idx_zona_beacons_zona            ON zona_beacons          (id_zona);
CREATE INDEX idx_zona_beacons_dispositivo     ON zona_beacons          (id_dispositivo);

-- Lecturas / detecciones
CREATE INDEX idx_lgps_dispositivo_fecha       ON lecturas_gps          (id_dispositivo, fecha_hora DESC);
CREATE INDEX idx_db_dispositivo_fecha         ON detecciones_beacon    (id_dispositivo, fecha_hora DESC);
CREATE INDEX idx_db_gateway                   ON detecciones_beacon    (id_gateway);

-- Alertas
CREATE INDEX idx_alertas_paciente             ON alertas               (id_paciente);
CREATE INDEX idx_alertas_fecha                ON alertas               (fecha_hora DESC);
CREATE INDEX idx_alertas_estatus              ON alertas               (estatus);

-- Recetas
CREATE INDEX idx_recetas_paciente             ON recetas               (id_paciente);
CREATE INDEX idx_receta_med_receta            ON receta_medicamentos   (id_receta);
CREATE INDEX idx_receta_med_gtin              ON receta_medicamentos   (GTIN);
CREATE INDEX idx_receta_nfc_dispositivo       ON receta_nfc            (id_dispositivo);

-- Sedes
CREATE INDEX idx_sede_zonas_zona              ON sede_zonas            (id_zona);
CREATE INDEX idx_sede_emp_empleado            ON sede_empleados        (id_empleado);
CREATE INDEX idx_sede_emp_sede                ON sede_empleados        (id_sede);
CREATE INDEX idx_sede_pac_paciente            ON sede_pacientes        (id_paciente);
CREATE INDEX idx_sede_pac_sede                ON sede_pacientes        (id_sede);

-- Visitas / entregas
CREATE INDEX idx_visitas_paciente             ON visitas               (id_paciente);
CREATE INDEX idx_visitas_fecha                ON visitas               (fecha_entrada DESC);
CREATE INDEX idx_visitas_sede                 ON visitas               (id_sede);
CREATE INDEX idx_entregas_paciente            ON entregas_externas     (id_paciente);

-- Inventario / suministros
CREATE INDEX idx_inventario_sede              ON inventario_medicinas  (id_sede);
CREATE INDEX idx_suministros_sede             ON suministros           (id_sede);
CREATE INDEX idx_suministros_farmacia         ON suministros           (id_farmacia);
CREATE INDEX idx_sum_med_gtin                 ON suministro_medicinas  (GTIN);

-- Comedor
CREATE INDEX idx_bitacora_sede_fecha          ON bitacora_comedor      (id_sede, fecha DESC);
CREATE INDEX idx_bitacora_cocinero            ON bitacora_comedor      (id_cocinero);


-- =============================================================================
-- DATOS SEMILLA (INSERT)
-- =============================================================================

-- Estados paciente
INSERT INTO estados_paciente (id_estado, desc_estado) VALUES
    (1, 'Activo'),
    (2, 'En Hospital'),
    (3, 'Baja');

-- Enfermedades
INSERT INTO enfermedades (id_enfermedad, nombre_enfermedad) VALUES
    (1, 'Alzheimer'),
    (2, 'Demencia Senil'),
    (3, 'Parkinson'),
    (4, 'Hipertensión');

-- Medicamentos
INSERT INTO medicamentos (GTIN, nombre_medicamento, descripcion) VALUES
    ('7501234567890', 'Donepezilo',  'Inhibidor de la colinesterasa para Alzheimer'),
    ('7509998765432', 'Memantina',   'Antagonista NMDA para Alzheimer moderado-grave'),
    ('7508001122334', 'Amlodipino',  'Bloqueador de canales de calcio para hipertensión');

-- Pacientes
INSERT INTO pacientes (id_paciente, nombre, apellido_p, apellido_m, fecha_nacimiento, id_estado) VALUES
    (1, 'María',    'García',  'López', '1942-05-10', 1),
    (2, 'Roberto',  'Pérez',   'Sosa',  '1938-11-22', 1),
    (3, 'Consuelo', 'Ramírez', 'Vega',  '1945-02-14', 2);

-- Enfermedades por paciente
INSERT INTO tiene_enfermedad (id_paciente, id_enfermedad, fecha_diag) VALUES
    (1, 1, '2020-03-15'),
    (1, 2, '2021-07-20'),
    (1, 4, '2019-11-05'),
    (2, 1, '2019-08-01'),
    (2, 2, '2021-07-20'),
    (3, 3, '2021-03-30'),
    (3, 2, '2021-07-20');

-- Contactos de emergencia
INSERT INTO contactos_emergencia (id_contacto, nombre, apellido_p, apellido_m, telefono, fecha_nac, CURP_pasaporte, relacion) VALUES
    (1, 'Maria',   'García', 'Sánchez', '8112345678', '1975-05-12', 'GAPM750512H', 'hija'),
    (2, 'Roberto', 'Campos', 'Luna',    '8187654321', '1980-11-20', 'CASR801120H', 'hijo');

-- Paciente — contactos
INSERT INTO paciente_contactos (id_paciente, id_contacto, prioridad) VALUES
    (1, 1, 1),
    (1, 2, 2);

-- Empleados
INSERT INTO empleados (id_empleado, nombre, apellido_p, apellido_m, CURP_pasaporte, fecha_nac, telefono) VALUES
    (1, 'Juan', 'Martínez', 'Ruiz',   'MARL800101H', '1980-01-01', '555-1234'),
    (2, 'Ana',  'López',    'Torres', 'LOTA760303M', '1976-03-03', '555-5678'),
    (3, 'Luis', 'Hernández','Mora',   'HEML850615H', '1985-06-15', '555-9012');

-- Cuidadores (subtipo)
INSERT INTO cuidadores (id_empleado, certificacion_medica, especialidad) VALUES
    (1, 'Enfermería Geriátrica', 'Especialista'),
    (2, 'Geriatría',             'Generalista');

-- Cocineros (subtipo)
INSERT INTO cocineros (id_empleado) VALUES
    (3);

-- Asignación cuidador — paciente
INSERT INTO asignacion_cuidador (id_asig_cuidador, id_cuidador, id_paciente, fecha_inicio, fecha_fin) VALUES
    (1, 1, 1, '2023-01-10', NULL),
    (2, 2, 2, '2022-06-01', NULL),
    (3, 2, 3, '2024-02-15', NULL);

-- Dispositivos
INSERT INTO dispositivos (id_dispositivo, id_serial, modelo, tipo, estado, ultima_conexion) VALUES
    (301, 'GPS-SN-001', 'TK103',      'GPS',    'Activo', '2024-06-01 08:30:00'),
    (302, 'GPS-SN-002', 'TK103',      'GPS',    'Activo', '2024-06-02 07:15:00'),
    (303, 'GPS-SN-003', 'GT06',       'GPS',    'Activo', '2024-06-03 14:45:00'),
    (401, 'BCN-SN-A',   'BC001',      'BEACON', 'Activo', '2024-06-01 09:00:00'),
    (402, 'BCN-SN-B',   'BC001',      'BEACON', 'Activo', '2024-06-02 07:15:00'),
    (403, 'BCN-SN-C',   'BC002',      'BEACON', 'Activo', '2024-06-03 14:45:00'),
    (501, 'NFC-SN-N01', 'NFCReader1', 'NFC',    'Activo', '2026-03-15 10:00:00');

-- Zonas
INSERT INTO zonas (id_zona, nombre_zona, latitud_centro, longitud_centro, radio_metros) VALUES
    (1, 'Jardín Norte', 19.432600, -99.133200, 50),
    (2, 'Ala Oriente',  19.431000, -99.130000, 40),
    (3, 'Patio Sur',    19.430000, -99.135000, 60);

-- Gateways
INSERT INTO gateways (id_gateway, modelo, id_zona) VALUES
    (601, 'GW-Model-X', 1),
    (602, 'GW-Model-Y', 2),
    (603, 'GW-Model-Z', 3);

-- Zona — beacons
INSERT INTO zona_beacons (id_zona, id_dispositivo, descripcion_ubicacion) VALUES
    (1, 401, 'Entrada principal'),
    (2, 402, 'Corredor 3'),
    (3, 403, 'Puerta trasera');

-- Kit de monitoreo
INSERT INTO asignacion_kit (id_monitoreo, id_paciente, id_dispositivo_gps, id_dispositivo_beacon, fecha_entrega) VALUES
    (1, 1, 301, 401, NULL),
    (2, 2, 302, 402, NULL),
    (3, 3, 303, 403, NULL);

-- Lecturas GPS
INSERT INTO lecturas_gps (id_lectura, id_dispositivo, fecha_hora, latitud, longitud, altura, nivel_bateria) VALUES
    (1, 301, '2024-06-01 08:30:00', 19.432700, -99.133100, NULL, NULL),
    (2, 301, '2024-06-01 09:00:00', 19.433000, -99.133500, NULL, NULL),
    (3, 302, '2024-06-02 07:15:00', 19.431100, -99.130100, NULL, NULL),
    (4, 303, '2024-06-03 14:45:00', 19.429000, -99.136000, NULL, NULL);

-- Detecciones beacon
INSERT INTO detecciones_beacon (id_deteccion, id_dispositivo, id_gateway, fecha_hora, rssi) VALUES
    (1, 401, 601, '2024-06-01 08:30:00', -72),
    (2, 401, 601, '2024-06-01 09:00:00', -68),
    (3, 402, 602, '2024-06-02 07:15:00', -80),
    (4, 403, 603, '2024-06-03 14:45:00', -55);

-- Alertas
INSERT INTO alertas (id_alerta, id_paciente, tipo_alerta, fecha_hora, estatus) VALUES
    (1, 1, 'Salida de Zona', '2024-06-01 08:30:00', 'Activa'),
    (2, 1, 'Batería Baja',   '2024-06-01 09:00:00', 'Atendida'),
    (3, 2, 'Batería Baja',   '2024-06-02 07:15:00', 'Atendida'),
    (4, 3, 'Botón SOS',      '2024-06-03 14:45:00', 'Activa');

-- Sedes
INSERT INTO sedes (id_sede, nombre_sede, calle, numero, municipio, estado) VALUES
    (1, 'Sede Norte',  'Av. Principal', '100', 'Monterrey', 'Nuevo León'),
    (2, 'Sede Centro', 'Calle 5',       '200', 'Monterrey', 'Nuevo León'),
    (3, 'Sede Sur',    'Blvd. Sur',     '300', 'San Pedro', 'Nuevo León');

-- Sede — zonas
INSERT INTO sede_zonas (id_sede, id_zona) VALUES
    (1, 1),
    (2, 2),
    (3, 3);

-- Sede — empleados
INSERT INTO sede_empleados (id_sede_empleado, id_sede, id_empleado, fecha_ingreso, hora_ingreso, fecha_salida, hora_salida) VALUES
    (1, 1, 1, '2024-01-10', '08:00:00', NULL, NULL),
    (2, 1, 3, '2024-02-15', '08:00:00', NULL, NULL),
    (3, 2, 2, '2024-01-15', '08:00:00', NULL, NULL);

-- Sede — pacientes
INSERT INTO sede_pacientes (id_sede_paciente, id_sede, id_paciente, fecha_ingreso, hora_ingreso, fecha_salida, hora_salida) VALUES
    (1, 1, 1, '2024-01-10', '09:00:00', NULL, NULL),
    (2, 2, 2, '2024-01-15', '10:00:00', NULL, NULL),
    (3, 3, 3, '2024-02-20', '09:00:00', NULL, NULL);

-- Recetas
INSERT INTO recetas (id_receta, fecha, id_paciente) VALUES
    (901, '2026-03-20', 1),
    (902, '2026-03-22', 2);

-- Receta — medicamentos
INSERT INTO receta_medicamentos (id_detalle, id_receta, GTIN, dosis, frecuencia_horas) VALUES
    (1, 901, '7501234567890', '10mg', 24),
    (2, 901, '7509998765432', '5mg',  12),
    (3, 902, '7501234567890', '10mg', 24),
    (4, 902, '7508001122334', '5mg',  24);

-- Paciente — recetas (prescripciones)
INSERT INTO paciente_recetas (id_paciente, id_receta, fecha_inicio_prescripcion, fecha_fin_prescripcion) VALUES
    (1, 901, '2026-03-20', NULL),
    (2, 902, '2026-03-22', NULL);

-- Receta — NFC
INSERT INTO receta_nfc (id_receta, id_dispositivo, fecha_inicio_gestion, fecha_fin_gestion) VALUES
    (901, 501, '2026-03-20', NULL);

-- Visitantes
INSERT INTO visitantes (id_visitante, nombre, apellido_p, apellido_m, relacion, telefono, CURP_pasaporte) VALUES
    (1, 'Carlos', 'López',    'Vega', 'hijo',  '8114567890', 'LOVC901010H'),
    (2, 'Sofía',  'Martínez', 'Díaz', 'hija',  '8119876543', 'MADS950320M');

-- Visitas
INSERT INTO visitas (id_visita, id_paciente, id_visitante, id_sede, fecha_entrada, hora_entrada, fecha_salida, hora_salida) VALUES
    (1, 1, 1, 1, '2026-03-15', '10:00:00', '2026-03-15', '12:00:00'),
    (2, 2, 2, 2, '2026-03-16', '11:00:00', '2026-03-16', '13:00:00');

-- Entregas externas
INSERT INTO entregas_externas (id_entrega, id_paciente, id_visitante, id_cuidador, descripcion, estado, fecha_recepcion, hora_recepcion) VALUES
    (1, 1, 1, 1, 'Ropa y artículos personales', 'Recibido', '2026-03-15', '10:05:00');

-- Farmacias proveedoras
INSERT INTO farmacias_proveedoras (id_farmacia, nombre, telefono, email, calle, numero, colonia, municipio, estado, RFC) VALUES
    (1, 'Farmacia del Ahorro', '8181234567', 'ahorro@farm.mx',  'Av. Garza Sada', '2501', 'Tecnológico', 'Monterrey', 'Nuevo León', 'FAH900101AA1'),
    (2, 'Benavides',           '8189876543', 'info@ben.mx',     'Av. Constitución','300', 'Centro',      'San Pedro', 'Nuevo León', 'BEN850615BB2');

-- Inventario medicinas
INSERT INTO inventario_medicinas (GTIN, id_sede, stock_actual, stock_minimo) VALUES
    ('7501234567890', 1, 50, 10),
    ('7509998765432', 1, 30,  5),
    ('7508001122334', 1, 40, 10),
    ('7501234567890', 2, 20, 10);

-- Suministros
INSERT INTO suministros (id_suministro, id_farmacia, id_sede, fecha_entrega, hora_entrega, estado) VALUES
    (1, 1, 1, '2026-03-10', '09:00:00', 'Entregado'),
    (2, 2, 2, '2026-03-12', '10:30:00', 'Entregado');

-- Suministro — medicinas
INSERT INTO suministro_medicinas (id_suministro, GTIN, cantidad) VALUES
    (1, '7501234567890', 100),
    (1, '7509998765432',  50),
    (2, '7501234567890',  80),
    (2, '7508001122334',  60);

-- Bitácora comedor
INSERT INTO bitacora_comedor (id_bitacora, id_sede, id_cocinero, fecha, turno, menu_nombre, cantidad_platos, incidencias) VALUES
    (1, 1, 3, '2026-03-20', 'Comida', 'Pollo asado con verduras', 25, NULL),
    (2, 1, 3, '2026-03-20', 'Cena',   'Sopa de verduras',         22, NULL),
    (3, 2, 3, '2026-03-20', 'Comida', 'Res con arroz',            18, NULL);