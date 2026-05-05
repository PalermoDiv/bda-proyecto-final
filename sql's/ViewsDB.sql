-- =============================================================================
-- ViewsDB.sql — Vistas de base de datos para AlzMonitor
-- Todas las vistas son de solo lectura. No reemplazan stored procedures DML.
-- Aplicar: psql -U palermingoat -d alzheimer -f ViewsDB.sql
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Pacientes activos con su sede y estado actual
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_pacientes_activos AS
SELECT
    p.id_paciente,
    p.nombre AS nombre_paciente,
    p.apellido_p,
    p.apellido_m,
    p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo,
    p.fecha_nacimiento,
    p.id_estado,
    ep.desc_estado,
    sp.id_sede AS id_sucursal,
    s.nombre_sede AS nombre_sucursal
FROM pacientes p
JOIN estados_paciente ep ON ep.id_estado = p.id_estado
LEFT JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
LEFT JOIN sedes s ON s.id_sede = sp.id_sede
WHERE p.id_estado != 3
ORDER BY p.id_paciente;


-- -----------------------------------------------------------------------------
-- 2. Cuidadores con su sede actual
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_cuidadores AS
SELECT
    e.id_empleado AS id_cuidador,
    e.nombre AS nombre_cuidador,
    e.apellido_p,
    e.apellido_m,
    e.nombre || ' ' || e.apellido_p AS nombre_completo,
    e.telefono,
    se.id_sede AS id_sucursal,
    s.nombre_sede AS nombre_sucursal
FROM cuidadores c
JOIN empleados e ON e.id_empleado = c.id_empleado
LEFT JOIN sede_empleados se ON se.id_empleado = e.id_empleado AND se.fecha_salida IS NULL
LEFT JOIN sedes s ON s.id_sede = se.id_sede
ORDER BY e.id_empleado;


-- -----------------------------------------------------------------------------
-- 3. Dispositivos con batería más reciente y paciente asignado
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_dispositivos AS
SELECT
    d.id_dispositivo,
    d.id_serial AS codigo,
    d.tipo,
    d.modelo,
    d.estado AS estatus,
    (
        SELECT lg.nivel_bateria
        FROM lecturas_gps lg
        WHERE lg.id_dispositivo = d.id_dispositivo
        ORDER BY lg.fecha_hora DESC
        LIMIT 1
    ) AS bateria,
    COALESCE(p.nombre || ' ' || p.apellido_p, '—') AS paciente,
    sp.id_sede AS id_sucursal,
    COALESCE(s.nombre_sede, '—') AS nombre_sucursal
FROM dispositivos d
LEFT JOIN asignacion_kit ak ON ak.id_dispositivo_gps = d.id_dispositivo AND ak.fecha_fin IS NULL
LEFT JOIN pacientes p ON p.id_paciente = ak.id_paciente
LEFT JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
LEFT JOIN sedes s ON s.id_sede = sp.id_sede
ORDER BY d.id_dispositivo;


-- -----------------------------------------------------------------------------
-- 4. Zonas seguras con sede, pacientes activos en esa sede y contacto de alerta
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_zonas AS
SELECT
    z.id_zona,
    z.nombre_zona,
    z.radio_metros,
    z.latitud_centro,
    z.longitud_centro,
    sz.id_sede AS id_sucursal,
    COALESCE(s.nombre_sede, '—') AS nombre_sucursal,
    COALESCE(
        (
            SELECT STRING_AGG(p.nombre || ' ' || p.apellido_p, ', ' ORDER BY p.nombre)
            FROM pacientes p
            JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente
            WHERE sp.id_sede = sz.id_sede
              AND sp.fecha_salida IS NULL
              AND p.id_estado != 3
        ),
        '—'
    ) AS pacientes_en_zona,
    COALESCE(
        (
            SELECT ce.nombre || ' ' || ce.apellido_p || ' · ' || ce.telefono
            FROM paciente_contactos pc
            JOIN contactos_emergencia ce ON ce.id_contacto = pc.id_contacto
            JOIN sede_pacientes sp ON sp.id_paciente = pc.id_paciente
            WHERE sp.id_sede = sz.id_sede
              AND sp.fecha_salida IS NULL
            ORDER BY pc.prioridad ASC
            LIMIT 1
        ),
        '—'
    ) AS notificar_a
FROM zonas z
LEFT JOIN sede_zonas sz ON sz.id_zona = z.id_zona
LEFT JOIN sedes s ON s.id_sede = sz.id_sede
ORDER BY z.id_zona;


-- -----------------------------------------------------------------------------
-- 5. Alertas con paciente, sede, origen del evento y contacto prioritario
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_alertas AS
SELECT
    a.id_alerta,
    a.id_paciente,
    a.tipo_alerta,
    a.estatus,
    a.fecha_hora,
    COALESCE(
        p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m,
        '— Zona: ' || z.nombre_zona,
        '—'
    ) AS paciente,
    COALESCE(s.nombre_sede, sz.nombre_sede, '—') AS nombre_sucursal,
    aeo.tipo_evento,
    aeo.regla_disparada,
    ce.nombre || ' ' || ce.apellido_p AS contacto_prioritario,
    ce.telefono AS telefono_contacto
FROM alertas a
LEFT JOIN pacientes p ON p.id_paciente = a.id_paciente
LEFT JOIN zonas z ON z.id_zona = a.id_zona
LEFT JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
LEFT JOIN sedes s ON s.id_sede = sp.id_sede
LEFT JOIN sede_zonas szr ON szr.id_zona = a.id_zona
LEFT JOIN sedes sz ON sz.id_sede = szr.id_sede
LEFT JOIN alerta_evento_origen aeo ON aeo.id_alerta = a.id_alerta
LEFT JOIN (
    SELECT pc.id_paciente, pc.id_contacto
    FROM paciente_contactos pc
    WHERE pc.prioridad = (
        SELECT MIN(pc2.prioridad)
        FROM paciente_contactos pc2
        WHERE pc2.id_paciente = pc.id_paciente
    )
) pc_top ON pc_top.id_paciente = a.id_paciente
LEFT JOIN contactos_emergencia ce ON ce.id_contacto = pc_top.id_contacto
ORDER BY a.fecha_hora DESC;


-- -----------------------------------------------------------------------------
-- 6. Recetas con paciente, sede, NFC activo y conteo de medicamentos
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_recetas AS
SELECT
    r.id_receta,
    r.estado,
    TO_CHAR(r.fecha, 'DD/MM/YYYY') AS fecha,
    p.id_paciente,
    p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_paciente,
    COALESCE(s.nombre_sede, '—') AS nombre_sede,
    COUNT(DISTINCT rm.id_detalle) AS n_medicamentos,
    d.id_serial AS serial_nfc,
    TO_CHAR(rn.fecha_inicio_gestion, 'DD/MM/YYYY') AS nfc_desde,
    COUNT(ln.id_lectura_nfc) FILTER (WHERE ln.fecha_hora::date = CURRENT_DATE) AS lecturas_hoy,
    COUNT(ln.id_lectura_nfc) FILTER (WHERE ln.fecha_hora::date = CURRENT_DATE AND ln.resultado = 'Exitosa') AS exitosas_hoy
FROM recetas r
JOIN pacientes p ON p.id_paciente = r.id_paciente
LEFT JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
LEFT JOIN sedes s ON s.id_sede = sp.id_sede
LEFT JOIN receta_medicamentos rm ON rm.id_receta = r.id_receta
LEFT JOIN receta_nfc rn ON rn.id_receta = r.id_receta AND rn.fecha_fin_gestion IS NULL
LEFT JOIN dispositivos d ON d.id_dispositivo = rn.id_dispositivo
LEFT JOIN lecturas_nfc ln ON ln.id_receta = r.id_receta
WHERE p.id_estado != 3
GROUP BY r.id_receta, r.estado, r.fecha, p.id_paciente, p.nombre, p.apellido_p,
         p.apellido_m, s.nombre_sede, d.id_serial, rn.fecha_inicio_gestion
ORDER BY r.fecha DESC;


-- -----------------------------------------------------------------------------
-- 7. Turnos de cuidadores con zona y días de cobertura
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_turnos AS
SELECT
    tc.id_turno,
    tc.hora_inicio,
    tc.hora_fin,
    tc.activo,
    tc.lunes, tc.martes, tc.miercoles, tc.jueves,
    tc.viernes, tc.sabado, tc.domingo,
    z.nombre_zona,
    tc.id_zona,
    e.nombre || ' ' || e.apellido_p AS nombre_cuidador,
    tc.id_cuidador
FROM turno_cuidador tc
JOIN zonas z ON z.id_zona = tc.id_zona
JOIN cuidadores c ON c.id_empleado = tc.id_cuidador
JOIN empleados e ON e.id_empleado = c.id_empleado
ORDER BY z.nombre_zona, tc.hora_inicio;


-- -----------------------------------------------------------------------------
-- 8. Detecciones beacon con cuidador y gateway (arquitectura cuidador lleva beacon)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_detecciones_beacon AS
SELECT
    db.id_deteccion,
    db.fecha_hora,
    db.rssi,
    db.id_gateway,
    d.id_serial AS serial_beacon,
    COALESCE(e.nombre || ' ' || e.apellido_p, 'Anónimo') AS nombre_cuidador,
    db.id_cuidador
FROM detecciones_beacon db
JOIN dispositivos d ON d.id_dispositivo = db.id_dispositivo
LEFT JOIN cuidadores c ON c.id_empleado = db.id_cuidador
LEFT JOIN empleados e ON e.id_empleado = c.id_empleado
ORDER BY db.fecha_hora DESC;


-- -----------------------------------------------------------------------------
-- 9. Kit GPS activo por paciente con última lectura de batería
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_kit_gps_activo AS
SELECT
    ak.id_monitoreo,
    ak.id_paciente,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente,
    d.id_dispositivo,
    d.id_serial AS codigo_gps,
    d.modelo,
    TO_CHAR(ak.fecha_entrega, 'YYYY-MM-DD') AS fecha_entrega,
    (
        SELECT lg.nivel_bateria
        FROM lecturas_gps lg
        WHERE lg.id_dispositivo = d.id_dispositivo
        ORDER BY lg.fecha_hora DESC
        LIMIT 1
    ) AS ultima_bateria,
    (
        SELECT TO_CHAR(lg.fecha_hora, 'YYYY-MM-DD HH24:MI')
        FROM lecturas_gps lg
        WHERE lg.id_dispositivo = d.id_dispositivo
        ORDER BY lg.fecha_hora DESC
        LIMIT 1
    ) AS ultima_lectura
FROM asignacion_kit ak
JOIN pacientes p ON p.id_paciente = ak.id_paciente
JOIN dispositivos d ON d.id_dispositivo = ak.id_dispositivo_gps
WHERE ak.fecha_fin IS NULL;


-- -----------------------------------------------------------------------------
-- 10. Inventario de farmacia por sede con alerta de stock crítico
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_inventario_farmacia AS
SELECT
    im.gtin,
    im.id_sede,
    s.nombre_sede,
    m.nombre_medicamento,
    im.stock_actual,
    im.stock_minimo,
    im.stock_actual <= im.stock_minimo AS stock_critico
FROM inventario_medicinas im
JOIN sedes s ON s.id_sede = im.id_sede
JOIN medicamentos m ON m.gtin = im.gtin
ORDER BY im.id_sede, stock_critico DESC, m.nombre_medicamento;


-- -----------------------------------------------------------------------------
-- 11. Suministros con farmacia proveedora, sede y medicamentos del pedido
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_suministros AS
SELECT
    su.id_suministro,
    TO_CHAR(su.fecha_entrega, 'YYYY-MM-DD') AS fecha_entrega,
    su.estado,
    fp.nombre AS farmacia,
    fp.id_farmacia,
    s.id_sede,
    s.nombre_sede,
    COALESCE(STRING_AGG(m.nombre_medicamento, ' · ' ORDER BY m.nombre_medicamento), '—') AS medicamentos
FROM suministros su
JOIN farmacias_proveedoras fp ON fp.id_farmacia = su.id_farmacia
JOIN sedes s ON s.id_sede = su.id_sede
LEFT JOIN suministro_medicinas sm ON sm.id_suministro = su.id_suministro
LEFT JOIN medicamentos m ON m.gtin = sm.gtin
GROUP BY su.id_suministro, su.fecha_entrega, su.estado, fp.nombre, fp.id_farmacia, s.id_sede, s.nombre_sede
ORDER BY su.id_suministro DESC;


-- -----------------------------------------------------------------------------
-- 12. Visitas con paciente, visitante y sede (filtrar por fecha en Python)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_visitas AS
SELECT
    v.id_visita,
    v.id_paciente,
    TO_CHAR(v.fecha_entrada, 'YYYY-MM-DD') AS fecha_entrada,
    v.hora_entrada,
    v.fecha_salida,
    v.hora_salida,
    p.nombre || ' ' || p.apellido_p AS paciente,
    vt.nombre || ' ' || vt.apellido_p AS visitante,
    vt.relacion,
    v.id_sede AS id_sucursal,
    s.nombre_sede AS nombre_sucursal
FROM visitas v
JOIN pacientes p ON p.id_paciente = v.id_paciente
JOIN visitantes vt ON vt.id_visitante = v.id_visitante
JOIN sedes s ON s.id_sede = v.id_sede
ORDER BY v.fecha_entrada DESC, v.hora_entrada DESC;


-- -----------------------------------------------------------------------------
-- 13. Entregas externas con paciente y visitante que las trajo
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_entregas_externas AS
SELECT
    ee.id_entrega,
    ee.id_paciente,
    ee.descripcion,
    ee.estado,
    TO_CHAR(ee.fecha_recepcion, 'YYYY-MM-DD') AS fecha,
    ee.hora_recepcion,
    p.nombre || ' ' || p.apellido_p AS paciente,
    vt.nombre || ' ' || vt.apellido_p AS visitante
FROM entregas_externas ee
JOIN pacientes p ON p.id_paciente = ee.id_paciente
JOIN visitantes vt ON vt.id_visitante = ee.id_visitante
ORDER BY ee.fecha_recepcion DESC;


-- -----------------------------------------------------------------------------
-- 14. Medicamentos por receta con estadísticas de adherencia NFC (30 días)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_receta_medicamentos AS
SELECT
    rm.id_detalle,
    rm.id_receta,
    rm.gtin,
    m.nombre_medicamento,
    rm.dosis,
    rm.frecuencia_horas,
    COUNT(ln.id_lectura_nfc) AS total_lecturas,
    COUNT(ln.id_lectura_nfc) FILTER (WHERE ln.resultado = 'Exitosa') AS exitosas,
    COUNT(ln.id_lectura_nfc) FILTER (
        WHERE ln.resultado = 'Exitosa'
          AND ln.fecha_hora >= CURRENT_DATE - INTERVAL '30 days'
    ) AS exitosas_30d
FROM receta_medicamentos rm
JOIN medicamentos m ON m.gtin = rm.gtin
LEFT JOIN receta_nfc rn ON rn.id_receta = rm.id_receta AND rn.fecha_fin_gestion IS NULL
LEFT JOIN lecturas_nfc ln ON ln.id_receta = rm.id_receta AND ln.id_dispositivo = rn.id_dispositivo
GROUP BY rm.id_detalle, rm.id_receta, rm.gtin, m.nombre_medicamento, rm.dosis, rm.frecuencia_horas
ORDER BY rm.id_receta, m.nombre_medicamento;


-- -----------------------------------------------------------------------------
-- 15. NFC activo por receta con serial del dispositivo
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_nfc_activo AS
SELECT
    rn.id_receta,
    rn.id_dispositivo,
    d.id_serial,
    TO_CHAR(rn.fecha_inicio_gestion, 'DD/MM/YYYY') AS desde,
    rn.fecha_fin_gestion
FROM receta_nfc rn
JOIN dispositivos d ON d.id_dispositivo = rn.id_dispositivo
WHERE rn.fecha_fin_gestion IS NULL;


-- -----------------------------------------------------------------------------
-- 16. Asignaciones beacon activas con cuidador
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_asignacion_beacon AS
SELECT
    ab.id_asignacion,
    ab.id_dispositivo,
    d.id_serial AS serial_beacon,
    d.modelo,
    ab.id_cuidador,
    e.nombre || ' ' || e.apellido_p AS nombre_cuidador,
    e.telefono,
    TO_CHAR(ab.fecha_inicio, 'YYYY-MM-DD') AS fecha_inicio
FROM asignacion_beacon ab
JOIN dispositivos d ON d.id_dispositivo = ab.id_dispositivo
JOIN empleados e ON e.id_empleado = ab.id_cuidador
WHERE ab.fecha_fin IS NULL
ORDER BY ab.id_asignacion;


-- -----------------------------------------------------------------------------
-- 17. Cuidadores actualmente asignados a cada paciente activo
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_cuidadores_asignados AS
SELECT
    ac.id_paciente,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente,
    e.nombre AS nombre_cuidador,
    e.apellido_p,
    e.apellido_m,
    e.telefono AS telefono_cuid,
    TO_CHAR(ac.fecha_inicio, 'YYYY-MM-DD') AS fecha_asig_cuidador
FROM asignacion_cuidador ac
JOIN pacientes p ON p.id_paciente = ac.id_paciente
JOIN cuidadores c ON c.id_empleado = ac.id_cuidador
JOIN empleados e ON e.id_empleado = c.id_empleado
WHERE ac.fecha_fin IS NULL
ORDER BY ac.id_paciente;


-- -----------------------------------------------------------------------------
-- 18. Medicamentos activos por paciente desde recetas vigentes
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_medicamentos_por_paciente AS
SELECT
    r.id_paciente,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente,
    r.id_receta,
    m.nombre_medicamento AS medicamento,
    rm.dosis,
    rm.frecuencia_horas
FROM recetas r
JOIN receta_medicamentos rm ON rm.id_receta = r.id_receta
JOIN medicamentos m ON m.gtin = rm.gtin
JOIN pacientes p ON p.id_paciente = r.id_paciente
WHERE r.estado = 'Activa'
ORDER BY r.id_paciente, m.nombre_medicamento;


-- -----------------------------------------------------------------------------
-- 19. Contactos de emergencia con prioridad por paciente
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_contactos_emergencia AS
SELECT
    pc.id_paciente,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente,
    pc.prioridad,
    ce.id_contacto,
    ce.nombre,
    ce.apellido_p,
    ce.nombre || ' ' || ce.apellido_p AS nombre_completo,
    ce.telefono,
    ce.relacion
FROM paciente_contactos pc
JOIN pacientes p ON p.id_paciente = pc.id_paciente
JOIN contactos_emergencia ce ON ce.id_contacto = pc.id_contacto
ORDER BY pc.id_paciente, pc.prioridad;


-- -----------------------------------------------------------------------------
-- 20. Últimas lecturas GPS por paciente activo (una fila por paciente)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_ultima_lectura_gps AS
SELECT DISTINCT ON (ak.id_paciente)
    ak.id_paciente,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente,
    lg.id_lectura,
    lg.latitud,
    lg.longitud,
    lg.nivel_bateria,
    lg.altura,
    lg.fecha_hora AS ts,
    TO_CHAR(lg.fecha_hora, 'YYYY-MM-DD') AS fecha,
    TO_CHAR(lg.fecha_hora, 'HH24:MI') AS hora,
    d.id_serial AS serial_gps
FROM asignacion_kit ak
JOIN pacientes p ON p.id_paciente = ak.id_paciente
JOIN lecturas_gps lg ON lg.id_dispositivo = ak.id_dispositivo_gps
JOIN dispositivos d ON d.id_dispositivo = ak.id_dispositivo_gps
WHERE ak.fecha_fin IS NULL
ORDER BY ak.id_paciente, lg.fecha_hora DESC;


-- -----------------------------------------------------------------------------
-- 21. Enfermedades por paciente con fecha de diagnóstico
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_enfermedades_paciente AS
SELECT
    te.id_paciente,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente,
    e.id_enfermedad,
    e.nombre_enfermedad,
    TO_CHAR(te.fecha_diag, 'YYYY-MM-DD') AS fecha_diagnostico
FROM tiene_enfermedad te
JOIN pacientes p ON p.id_paciente = te.id_paciente
JOIN enfermedades e ON e.id_enfermedad = te.id_enfermedad
ORDER BY te.id_paciente, te.fecha_diag DESC;


-- -----------------------------------------------------------------------------
-- 22. Adherencia NFC últimos 30 días por receta activa
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_adherencia_nfc_30d AS
SELECT
    r.id_receta,
    r.id_paciente,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente,
    COUNT(ln.id_lectura_nfc) AS total_lecturas_30d,
    COUNT(ln.id_lectura_nfc) FILTER (WHERE ln.resultado = 'Exitosa') AS exitosas_30d,
    CASE
        WHEN COUNT(ln.id_lectura_nfc) = 0 THEN 0
        ELSE ROUND(
            100.0 * COUNT(ln.id_lectura_nfc) FILTER (WHERE ln.resultado = 'Exitosa')
            / COUNT(ln.id_lectura_nfc)
        )
    END AS porcentaje_adherencia
FROM recetas r
JOIN pacientes p ON p.id_paciente = r.id_paciente
LEFT JOIN lecturas_nfc ln ON ln.id_receta = r.id_receta
    AND ln.fecha_hora >= CURRENT_DATE - INTERVAL '30 days'
WHERE r.estado = 'Activa'
  AND p.id_estado != 3
GROUP BY r.id_receta, r.id_paciente, p.nombre, p.apellido_p
ORDER BY porcentaje_adherencia ASC;


-- -----------------------------------------------------------------------------
-- 23. Pacientes activos sin kit GPS asignado
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_pacientes_sin_gps AS
SELECT
    p.id_paciente,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente,
    ep.desc_estado,
    COALESCE(s.nombre_sede, '—') AS nombre_sede
FROM pacientes p
JOIN estados_paciente ep ON ep.id_estado = p.id_estado
LEFT JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
LEFT JOIN sedes s ON s.id_sede = sp.id_sede
LEFT JOIN asignacion_kit ak ON ak.id_paciente = p.id_paciente AND ak.fecha_fin IS NULL
WHERE p.id_estado != 3
  AND ak.id_monitoreo IS NULL
ORDER BY p.id_paciente;


-- -----------------------------------------------------------------------------
-- 24. Historial completo de sedes por paciente
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_historial_sedes_paciente AS
SELECT
    sp.id_paciente,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente,
    s.nombre_sede,
    sp.id_sede,
    TO_CHAR(sp.fecha_ingreso, 'YYYY-MM-DD') AS fecha_entrada,
    TO_CHAR(sp.fecha_salida, 'YYYY-MM-DD') AS fecha_salida,
    CASE WHEN sp.fecha_salida IS NULL THEN TRUE ELSE FALSE END AS sede_actual
FROM sede_pacientes sp
JOIN pacientes p ON p.id_paciente = sp.id_paciente
JOIN sedes s ON s.id_sede = sp.id_sede
ORDER BY sp.id_paciente, sp.fecha_ingreso DESC;


-- -----------------------------------------------------------------------------
-- 25. Alertas activas (sin atender) con paciente y contacto prioritario
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_alertas_activas AS
SELECT
    a.id_alerta,
    a.tipo_alerta,
    a.fecha_hora,
    COALESCE(p.nombre || ' ' || p.apellido_p, '— Zona —') AS paciente,
    COALESCE(s.nombre_sede, '—') AS nombre_sede,
    aeo.tipo_evento,
    aeo.regla_disparada,
    ce.nombre || ' ' || ce.apellido_p AS contacto_prioritario,
    ce.telefono
FROM alertas a
LEFT JOIN pacientes p ON p.id_paciente = a.id_paciente
LEFT JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
LEFT JOIN sedes s ON s.id_sede = sp.id_sede
LEFT JOIN alerta_evento_origen aeo ON aeo.id_alerta = a.id_alerta
LEFT JOIN (
    SELECT pc.id_paciente, pc.id_contacto
    FROM paciente_contactos pc
    WHERE pc.prioridad = (
        SELECT MIN(pc2.prioridad) FROM paciente_contactos pc2
        WHERE pc2.id_paciente = pc.id_paciente
    )
) pc_top ON pc_top.id_paciente = a.id_paciente
LEFT JOIN contactos_emergencia ce ON ce.id_contacto = pc_top.id_contacto
WHERE a.estatus = 'Activa'
ORDER BY a.fecha_hora DESC;


-- -----------------------------------------------------------------------------
-- 26. Lecturas GPS de las últimas 24 horas con paciente
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_lecturas_gps_recientes AS
SELECT
    lg.id_lectura,
    lg.id_dispositivo,
    lg.latitud,
    lg.longitud,
    lg.nivel_bateria,
    lg.altura,
    lg.fecha_hora,
    TO_CHAR(lg.fecha_hora, 'HH24:MI') AS hora,
    d.id_serial AS serial_gps,
    COALESCE(p.nombre || ' ' || p.apellido_p, '—') AS nombre_paciente,
    ak.id_paciente
FROM lecturas_gps lg
JOIN dispositivos d ON d.id_dispositivo = lg.id_dispositivo
LEFT JOIN asignacion_kit ak ON ak.id_dispositivo_gps = lg.id_dispositivo AND ak.fecha_fin IS NULL
LEFT JOIN pacientes p ON p.id_paciente = ak.id_paciente
WHERE lg.fecha_hora >= NOW() - INTERVAL '24 hours'
ORDER BY lg.fecha_hora DESC;


-- -----------------------------------------------------------------------------
-- 27. Cuidadores sin beacon asignado actualmente
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_cuidadores_sin_beacon AS
SELECT
    c.id_empleado AS id_cuidador,
    e.nombre || ' ' || e.apellido_p AS nombre_cuidador,
    e.telefono,
    COALESCE(s.nombre_sede, '—') AS nombre_sede
FROM cuidadores c
JOIN empleados e ON e.id_empleado = c.id_empleado
LEFT JOIN sede_empleados se ON se.id_empleado = e.id_empleado AND se.fecha_salida IS NULL
LEFT JOIN sedes s ON s.id_sede = se.id_sede
LEFT JOIN asignacion_beacon ab ON ab.id_cuidador = c.id_empleado AND ab.fecha_fin IS NULL
WHERE ab.id_asignacion IS NULL
ORDER BY e.id_empleado;


-- -----------------------------------------------------------------------------
-- 28. Resumen de alertas por tipo (últimos 30 días)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_resumen_alertas_por_tipo AS
SELECT
    a.tipo_alerta,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE a.estatus = 'Activa') AS activas,
    COUNT(*) FILTER (WHERE a.estatus = 'Atendida') AS atendidas,
    COUNT(*) FILTER (WHERE a.fecha_hora >= CURRENT_DATE - INTERVAL '30 days') AS ultimos_30d
FROM alertas a
GROUP BY a.tipo_alerta
ORDER BY total DESC;


-- -----------------------------------------------------------------------------
-- 29. Visitas de los últimos 7 días con paciente y visitante
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_visitas_recientes AS
SELECT
    v.id_visita,
    v.id_paciente,
    TO_CHAR(v.fecha_entrada, 'YYYY-MM-DD') AS fecha_entrada,
    v.hora_entrada,
    v.hora_salida,
    p.nombre || ' ' || p.apellido_p AS paciente,
    vt.nombre || ' ' || vt.apellido_p AS visitante,
    vt.relacion,
    s.nombre_sede AS nombre_sucursal
FROM visitas v
JOIN pacientes p ON p.id_paciente = v.id_paciente
JOIN visitantes vt ON vt.id_visitante = v.id_visitante
JOIN sedes s ON s.id_sede = v.id_sede
WHERE v.fecha_entrada >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY v.fecha_entrada DESC, v.hora_entrada DESC;


-- -----------------------------------------------------------------------------
-- 30. Pacientes que han estado en más de una sede (historial de transferencias)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_pacientes_transferidos AS
SELECT
    p.id_paciente,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente,
    COUNT(sp.id_sede) AS total_sedes,
    STRING_AGG(s.nombre_sede, ' → ' ORDER BY sp.fecha_ingreso) AS recorrido_sedes,
    TO_CHAR(MIN(sp.fecha_ingreso), 'YYYY-MM-DD') AS primer_ingreso
FROM sede_pacientes sp
JOIN pacientes p ON p.id_paciente = sp.id_paciente
JOIN sedes s ON s.id_sede = sp.id_sede
GROUP BY p.id_paciente, p.nombre, p.apellido_p
HAVING COUNT(sp.id_sede) > 1
ORDER BY total_sedes DESC, p.id_paciente;


-- -----------------------------------------------------------------------------
-- 31. Estadísticas por sede: pacientes, cuidadores, dispositivos, alertas activas
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_stats_por_sede AS
SELECT
    s.id_sede,
    s.nombre_sede,
    s.calle || ' ' || s.numero || ', ' || s.municipio AS direccion,
    COUNT(DISTINCT CASE WHEN sp.fecha_salida IS NULL AND p.id_estado != 3 THEN p.id_paciente END) AS total_pacientes,
    COUNT(DISTINCT CASE WHEN se.fecha_salida IS NULL THEN c.id_empleado END) AS total_cuidadores,
    COUNT(DISTINCT CASE WHEN sp2.fecha_salida IS NULL AND ak.fecha_fin IS NULL THEN ak.id_dispositivo_gps END) AS total_dispositivos,
    COUNT(DISTINCT CASE WHEN sp3.fecha_salida IS NULL AND a.estatus = 'Activa' THEN a.id_alerta END) AS alertas_activas
FROM sedes s
LEFT JOIN sede_pacientes sp ON sp.id_sede = s.id_sede AND sp.fecha_salida IS NULL
LEFT JOIN pacientes p ON p.id_paciente = sp.id_paciente
LEFT JOIN sede_empleados se ON se.id_sede = s.id_sede AND se.fecha_salida IS NULL
LEFT JOIN cuidadores c ON c.id_empleado = se.id_empleado
LEFT JOIN sede_pacientes sp2 ON sp2.id_sede = s.id_sede AND sp2.fecha_salida IS NULL
LEFT JOIN asignacion_kit ak ON ak.id_paciente = sp2.id_paciente AND ak.fecha_fin IS NULL
LEFT JOIN sede_pacientes sp3 ON sp3.id_sede = s.id_sede AND sp3.fecha_salida IS NULL
LEFT JOIN alertas a ON a.id_paciente = sp3.id_paciente
GROUP BY s.id_sede, s.nombre_sede, s.calle, s.numero, s.municipio
ORDER BY s.id_sede;


-- -----------------------------------------------------------------------------
-- 32. Órdenes de suministro pendientes con farmacia y sede
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_suministros_pendientes AS
SELECT
    su.id_suministro,
    TO_CHAR(su.fecha_entrega, 'YYYY-MM-DD') AS fecha_entrega,
    su.estado,
    fp.nombre AS farmacia,
    s.nombre_sede
FROM suministros su
JOIN farmacias_proveedoras fp ON fp.id_farmacia = su.id_farmacia
JOIN sedes s ON s.id_sede = su.id_sede
WHERE su.estado = 'Pendiente'
ORDER BY su.fecha_entrega;


-- -----------------------------------------------------------------------------
-- 33. Medicamentos con stock crítico (stock_actual < stock_minimo)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_medicamentos_criticos AS
SELECT
    im.gtin,
    m.nombre_medicamento,
    im.id_sede,
    s.nombre_sede,
    im.stock_actual,
    im.stock_minimo,
    im.stock_minimo - im.stock_actual AS unidades_faltantes
FROM inventario_medicinas im
JOIN medicamentos m ON m.gtin = im.gtin
JOIN sedes s ON s.id_sede = im.id_sede
WHERE im.stock_actual < im.stock_minimo
ORDER BY unidades_faltantes DESC;


-- -----------------------------------------------------------------------------
-- 34. Dispositivos NFC disponibles (no vinculados a ninguna receta activa)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_nfc_disponibles AS
SELECT
    d.id_dispositivo,
    d.id_serial,
    d.modelo,
    d.estado
FROM dispositivos d
WHERE d.tipo = 'NFC'
  AND d.estado = 'Activo'
  AND NOT EXISTS (
      SELECT 1 FROM receta_nfc rn
      WHERE rn.id_dispositivo = d.id_dispositivo
        AND rn.fecha_fin_gestion IS NULL
  )
ORDER BY d.id_serial;


-- -----------------------------------------------------------------------------
-- 35. Dispositivos GPS disponibles (no asignados a ningún kit activo)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_gps_disponibles AS
SELECT
    d.id_dispositivo,
    d.id_serial,
    d.modelo,
    d.estado
FROM dispositivos d
WHERE d.tipo = 'GPS'
  AND d.estado = 'Activo'
  AND NOT EXISTS (
      SELECT 1 FROM asignacion_kit ak
      WHERE ak.id_dispositivo_gps = d.id_dispositivo
        AND ak.fecha_fin IS NULL
  )
ORDER BY d.id_serial;


-- -----------------------------------------------------------------------------
-- 37. Líneas de suministro con medicamento y stock actual por sede
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_lineas_suministro AS
SELECT
    sm.id_suministro,
    su.id_sede,
    s.nombre_sede,
    sm.gtin,
    m.nombre_medicamento,
    sm.cantidad AS cantidad_pedida,
    im.stock_actual,
    im.stock_minimo
FROM suministro_medicinas sm
JOIN suministros su ON su.id_suministro = sm.id_suministro
JOIN sedes s ON s.id_sede = su.id_sede
JOIN medicamentos m ON m.gtin = sm.gtin
LEFT JOIN inventario_medicinas im ON im.gtin = sm.gtin AND im.id_sede = su.id_sede
ORDER BY sm.id_suministro, m.nombre_medicamento;


-- -----------------------------------------------------------------------------
-- 38. Lecturas NFC recientes (últimas 48 horas) con receta y paciente
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_lecturas_nfc_recientes AS
SELECT
    ln.id_lectura_nfc,
    ln.id_receta,
    ln.id_dispositivo,
    d.id_serial AS serial_nfc,
    TO_CHAR(ln.fecha_hora, 'DD/MM/YYYY HH24:MI') AS fecha_hora,
    ln.tipo_lectura,
    ln.resultado,
    p.id_paciente,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente
FROM lecturas_nfc ln
JOIN dispositivos d ON d.id_dispositivo = ln.id_dispositivo
JOIN recetas r ON r.id_receta = ln.id_receta
JOIN pacientes p ON p.id_paciente = r.id_paciente
WHERE ln.fecha_hora >= NOW() - INTERVAL '48 hours'
ORDER BY ln.fecha_hora DESC;


-- -----------------------------------------------------------------------------
-- 39. Cuidadores actualmente en turno por sede (basado en hora y día actual)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_cuidadores_en_turno AS
SELECT
    e.id_empleado AS id_cuidador,
    e.nombre || ' ' || e.apellido_p AS nombre_cuidador,
    e.telefono,
    tc.hora_inicio,
    tc.hora_fin,
    z.nombre_zona,
    sz.id_sede,
    s.nombre_sede
FROM turno_cuidador tc
JOIN cuidadores c ON c.id_empleado = tc.id_cuidador
JOIN empleados e ON e.id_empleado = c.id_empleado
JOIN zonas z ON z.id_zona = tc.id_zona
JOIN sede_zonas sz ON sz.id_zona = z.id_zona
JOIN sedes s ON s.id_sede = sz.id_sede
WHERE tc.activo = TRUE
  AND tc.hora_inicio <= CURRENT_TIME
  AND tc.hora_fin > CURRENT_TIME
  AND CASE EXTRACT(DOW FROM CURRENT_DATE)
      WHEN 1 THEN tc.lunes
      WHEN 2 THEN tc.martes
      WHEN 3 THEN tc.miercoles
      WHEN 4 THEN tc.jueves
      WHEN 5 THEN tc.viernes
      WHEN 6 THEN tc.sabado
      WHEN 0 THEN tc.domingo
  END = TRUE
ORDER BY sz.id_sede, e.nombre;


-- -----------------------------------------------------------------------------
-- 40. Bitácora del comedor con cocinero y sede (filtrar por fecha en Python)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_bitacora_comedor AS
SELECT
    bc.id_bitacora,
    bc.id_sede,
    s.nombre_sede,
    bc.turno,
    bc.menu_nombre,
    bc.cantidad_platos,
    bc.incidencias,
    TO_CHAR(bc.fecha, 'YYYY-MM-DD') AS fecha,
    e.nombre || ' ' || e.apellido_p AS cocinero
FROM bitacora_comedor bc
JOIN cocineros co ON co.id_empleado = bc.id_cocinero
JOIN empleados e ON e.id_empleado = co.id_empleado
JOIN sedes s ON s.id_sede = bc.id_sede
ORDER BY bc.fecha DESC, bc.turno;


-- -----------------------------------------------------------------------------
-- 41. Pacientes vinculados a cada contacto de emergencia (portal familiar index)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_pacientes_por_contacto AS
SELECT
    pc.id_contacto,
    pc.prioridad,
    p.id_paciente,
    p.nombre        AS nombre_paciente,
    p.apellido_p    AS apellido_p_pac,
    p.apellido_m    AS apellido_m_pac,
    ep.desc_estado,
    s.nombre_sede
FROM paciente_contactos pc
JOIN pacientes p ON p.id_paciente = pc.id_paciente
JOIN estados_paciente ep ON ep.id_estado = p.id_estado
LEFT JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
LEFT JOIN sedes s ON s.id_sede = sp.id_sede
WHERE p.id_estado != 3
ORDER BY pc.id_contacto, pc.prioridad, p.nombre;


-- -----------------------------------------------------------------------------
-- 42. Zonas seguras de la sede actual de cada paciente (mapa portal familiar)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_zonas_por_paciente AS
SELECT
    sp.id_paciente,
    z.id_zona,
    z.nombre_zona,
    z.latitud_centro,
    z.longitud_centro,
    z.radio_metros
FROM sede_pacientes sp
JOIN sede_zonas sz ON sz.id_sede = sp.id_sede
JOIN zonas z ON z.id_zona = sz.id_zona
WHERE sp.fecha_salida IS NULL
ORDER BY sp.id_paciente, z.nombre_zona;


-- -----------------------------------------------------------------------------
-- 43. Alertas críticas activas por paciente (Salida de Zona o Botón SOS)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_alertas_criticas_activas AS
SELECT
    a.id_alerta,
    a.id_paciente,
    a.tipo_alerta,
    a.fecha_hora,
    TO_CHAR(a.fecha_hora, 'YYYY-MM-DD') AS fecha,
    TO_CHAR(a.fecha_hora, 'HH24:MI')    AS hora,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente
FROM alertas a
JOIN pacientes p ON p.id_paciente = a.id_paciente
WHERE a.estatus = 'Activa'
  AND a.tipo_alerta IN ('Salida de Zona', 'Botón SOS')
ORDER BY a.fecha_hora DESC;


-- -----------------------------------------------------------------------------
-- 44. Historial de alertas atendidas últimos 30 días por paciente
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_alertas_historial_30d AS
SELECT
    a.id_alerta,
    a.id_paciente,
    a.tipo_alerta,
    TO_CHAR(a.fecha_hora, 'YYYY-MM-DD') AS fecha,
    TO_CHAR(a.fecha_hora, 'HH24:MI')    AS hora,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente
FROM alertas a
JOIN pacientes p ON p.id_paciente = a.id_paciente
WHERE a.estatus = 'Atendida'
  AND a.fecha_hora >= NOW() - INTERVAL '30 days'
ORDER BY a.id_paciente, a.fecha_hora DESC;


-- -----------------------------------------------------------------------------
-- 45. Medicamentos activos con estado de toma hoy via NFC (portal familiar)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_medicamentos_adherencia_hoy AS
SELECT
    r.id_paciente,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente,
    m.nombre_medicamento,
    rm.dosis,
    rm.frecuencia_horas,
    EXISTS (
        SELECT 1 FROM lecturas_nfc ln
        WHERE ln.id_receta = r.id_receta
          AND ln.fecha_hora::DATE = CURRENT_DATE
          AND ln.resultado = 'Exitosa'
    ) AS tomada_hoy
FROM recetas r
JOIN receta_medicamentos rm ON rm.id_receta = r.id_receta
JOIN medicamentos m ON m.gtin = rm.gtin
JOIN pacientes p ON p.id_paciente = r.id_paciente
WHERE r.estado = 'Activa'
  AND p.id_estado != 3
ORDER BY r.id_paciente, m.nombre_medicamento;


-- -----------------------------------------------------------------------------
-- 46. Entregas externas pendientes con paciente y sede
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_entregas_pendientes AS
SELECT
    ee.id_entrega,
    ee.id_paciente,
    ee.descripcion,
    TO_CHAR(ee.fecha_recepcion, 'YYYY-MM-DD') AS fecha,
    ee.hora_recepcion,
    p.nombre || ' ' || p.apellido_p AS paciente,
    vt.nombre || ' ' || vt.apellido_p AS visitante,
    sp.id_sede,
    s.nombre_sede
FROM entregas_externas ee
JOIN pacientes p ON p.id_paciente = ee.id_paciente
JOIN visitantes vt ON vt.id_visitante = ee.id_visitante
JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
JOIN sedes s ON s.id_sede = sp.id_sede
WHERE ee.estado = 'Pendiente'
ORDER BY ee.fecha_recepcion DESC;


-- -----------------------------------------------------------------------------
-- 47. Visitas de hoy con paciente, visitante y sede
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_visitas_hoy AS
SELECT
    v.id_visita,
    v.id_paciente,
    v.fecha_entrada,
    v.hora_entrada,
    v.hora_salida,
    v.fecha_salida,
    p.nombre || ' ' || p.apellido_p AS paciente,
    vt.nombre || ' ' || vt.apellido_p AS visitante,
    vt.relacion,
    v.id_sede,
    s.nombre_sede
FROM visitas v
JOIN pacientes p ON p.id_paciente = v.id_paciente
JOIN visitantes vt ON vt.id_visitante = v.id_visitante
JOIN sedes s ON s.id_sede = v.id_sede
WHERE v.fecha_entrada = CURRENT_DATE
ORDER BY v.hora_entrada DESC;


-- -----------------------------------------------------------------------------
-- 48. Última actividad por paciente: max timestamp de GPS, NFC y alertas
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_ultima_actividad_paciente AS
SELECT
    p.id_paciente,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente,
    MAX(ev.ts) AS ultima_actividad
FROM pacientes p
LEFT JOIN (
    SELECT ak.id_paciente, lg.fecha_hora AS ts
    FROM lecturas_gps lg
    JOIN asignacion_kit ak ON ak.id_dispositivo_gps = lg.id_dispositivo AND ak.fecha_fin IS NULL
    UNION ALL
    SELECT r.id_paciente, ln.fecha_hora AS ts
    FROM lecturas_nfc ln
    JOIN recetas r ON r.id_receta = ln.id_receta
    UNION ALL
    SELECT a.id_paciente, a.fecha_hora AS ts
    FROM alertas a
    WHERE a.id_paciente IS NOT NULL
) ev ON ev.id_paciente = p.id_paciente
WHERE p.id_estado != 3
GROUP BY p.id_paciente, p.nombre, p.apellido_p
ORDER BY ultima_actividad DESC NULLS LAST;


-- -----------------------------------------------------------------------------
-- 49. Alertas por sede: pacientes activos de esa sede (portal clínico)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_alertas_por_sede AS
SELECT
    a.id_alerta,
    a.tipo_alerta,
    a.estatus,
    TO_CHAR(a.fecha_hora, 'YYYY-MM-DD') AS fecha,
    TO_CHAR(a.fecha_hora, 'HH24:MI')    AS hora,
    a.id_paciente,
    p.nombre || ' ' || p.apellido_p AS paciente,
    sp.id_sede,
    s.nombre_sede
FROM alertas a
JOIN pacientes p ON p.id_paciente = a.id_paciente
JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
JOIN sedes s ON s.id_sede = sp.id_sede
ORDER BY sp.id_sede, a.fecha_hora DESC;


-- -----------------------------------------------------------------------------
-- 50. Expediente clínico por paciente: enfermedades, cuidadores y medicamentos activos
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_expediente_clinico AS
SELECT
    p.id_paciente,
    p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo,
    ep.desc_estado,
    COALESCE(s.nombre_sede, '—') AS nombre_sede,
    STRING_AGG(DISTINCT e.nombre_enfermedad, ', ' ORDER BY e.nombre_enfermedad) AS enfermedades,
    STRING_AGG(DISTINCT emp.nombre || ' ' || emp.apellido_p, ', ') AS cuidadores_activos,
    STRING_AGG(DISTINCT m.nombre_medicamento, ', ' ORDER BY m.nombre_medicamento) AS medicamentos_activos
FROM pacientes p
JOIN estados_paciente ep ON ep.id_estado = p.id_estado
LEFT JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
LEFT JOIN sedes s ON s.id_sede = sp.id_sede
LEFT JOIN tiene_enfermedad te ON te.id_paciente = p.id_paciente
LEFT JOIN enfermedades e ON e.id_enfermedad = te.id_enfermedad
LEFT JOIN asignacion_cuidador ac ON ac.id_paciente = p.id_paciente AND ac.fecha_fin IS NULL
LEFT JOIN cuidadores c ON c.id_empleado = ac.id_cuidador
LEFT JOIN empleados emp ON emp.id_empleado = c.id_empleado
LEFT JOIN recetas r ON r.id_paciente = p.id_paciente AND r.estado = 'Activa'
LEFT JOIN receta_medicamentos rm ON rm.id_receta = r.id_receta
LEFT JOIN medicamentos m ON m.gtin = rm.gtin
WHERE p.id_estado != 3
GROUP BY p.id_paciente, p.nombre, p.apellido_p, p.apellido_m,
         ep.desc_estado, s.nombre_sede
ORDER BY p.id_paciente;


-- -----------------------------------------------------------------------------
-- 50. Alertas por día — últimos 14 días (dashboard column chart)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_alertas_por_dia_14d AS
SELECT
    fecha_hora::date                              AS dia,
    TO_CHAR(fecha_hora::date, 'DD/MM')           AS dia_label,
    COUNT(*)                                      AS total
FROM alertas
WHERE fecha_hora >= CURRENT_DATE - INTERVAL '13 days'
GROUP BY fecha_hora::date
ORDER BY fecha_hora::date;


-- -----------------------------------------------------------------------------
-- 51. Stock completo de farmacia — todas las sedes (dashboard bar chart)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_stock_farmacia_completo AS
SELECT
    im.gtin,
    m.nombre_medicamento,
    im.id_sede,
    s.nombre_sede,
    im.stock_actual,
    im.stock_minimo,
    CASE WHEN im.stock_actual < im.stock_minimo THEN true ELSE false END AS es_critico
FROM inventario_medicinas im
JOIN medicamentos m ON m.gtin      = im.gtin
JOIN sedes        s ON s.id_sede   = im.id_sede
ORDER BY s.nombre_sede, m.nombre_medicamento;


-- -----------------------------------------------------------------------------
-- 52. Adherencia NFC últimos 30 días agrupada por paciente (recetas chart)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_adherencia_nfc_por_paciente AS
SELECT
    p.id_paciente,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente,
    COUNT(ln.id_lectura_nfc)                                              AS total,
    COUNT(ln.id_lectura_nfc) FILTER (WHERE ln.resultado = 'Exitosa')     AS exitosas
FROM recetas r
JOIN pacientes p ON p.id_paciente = r.id_paciente
LEFT JOIN lecturas_nfc ln
    ON ln.id_receta  = r.id_receta
    AND ln.fecha_hora >= NOW() - INTERVAL '30 days'
WHERE p.id_estado != 3
GROUP BY p.id_paciente, p.nombre, p.apellido_p
HAVING COUNT(ln.id_lectura_nfc) > 0
ORDER BY COUNT(ln.id_lectura_nfc) FILTER (WHERE ln.resultado = 'Exitosa')::float / NULLIF(COUNT(ln.id_lectura_nfc), 0) DESC;


-- -----------------------------------------------------------------------------
-- 53. Historial de batería GPS por paciente (portal familiar sparkline)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_bateria_historial_gps AS
SELECT
    ak.id_paciente,
    lg.id_lectura,
    lg.fecha_hora,
    TO_CHAR(lg.fecha_hora, 'DD/MM HH24:MI') AS label,
    lg.nivel_bateria
FROM lecturas_gps lg
JOIN asignacion_kit ak ON ak.id_dispositivo_gps = lg.id_dispositivo
                      AND ak.fecha_fin IS NULL
WHERE lg.nivel_bateria IS NOT NULL
ORDER BY ak.id_paciente, lg.fecha_hora DESC;


-- -----------------------------------------------------------------------------
-- 54. Log de lecturas GPS por paciente (historial admin)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_lecturas_gps_paciente AS
SELECT
    ak.id_paciente,
    lg.id_lectura,
    TO_CHAR(lg.fecha_hora, 'YYYY-MM-DD') AS fecha,
    TO_CHAR(lg.fecha_hora, 'HH24:MI:SS') AS hora,
    lg.latitud,
    lg.longitud,
    lg.nivel_bateria,
    lg.fecha_hora
FROM lecturas_gps lg
JOIN asignacion_kit ak ON ak.id_dispositivo_gps = lg.id_dispositivo
                      AND ak.fecha_fin IS NULL
ORDER BY ak.id_paciente, lg.fecha_hora DESC;


-- =============================================================================
-- VISTAS 55–113 — catálogos, lookup, stats, clinica, portal, IoT, SPs IDs
-- =============================================================================

-- 55 Catálogo de sedes
CREATE OR REPLACE VIEW v_sedes AS
SELECT id_sede, nombre_sede, calle, numero, municipio,
       calle || ' ' || numero || ', ' || municipio AS direccion
FROM sedes ORDER BY id_sede;

-- 56 Catálogo de estados de paciente
CREATE OR REPLACE VIEW v_estados_paciente AS
SELECT id_estado, desc_estado FROM estados_paciente ORDER BY id_estado;

-- 57 Catálogo de tipos de alerta
CREATE OR REPLACE VIEW v_cat_tipo_alerta AS
SELECT tipo_alerta FROM cat_tipo_alerta ORDER BY tipo_alerta;

-- 58 Catálogo de estados de suministro
CREATE OR REPLACE VIEW v_cat_estado_suministro AS
SELECT estado FROM cat_estado_suministro ORDER BY estado;

-- 59 Catálogo de farmacias proveedoras
CREATE OR REPLACE VIEW v_farmacias_proveedoras AS
SELECT id_farmacia, nombre, telefono FROM farmacias_proveedoras ORDER BY id_farmacia;

-- 60 Catálogo de medicamentos
CREATE OR REPLACE VIEW v_medicamentos_catalogo AS
SELECT gtin, nombre_medicamento FROM medicamentos ORDER BY nombre_medicamento;

-- 61 Visitantes para dropdown en formularios
CREATE OR REPLACE VIEW v_visitantes_lista AS
SELECT id_visitante, nombre || ' ' || apellido_p AS nombre, relacion
FROM visitantes ORDER BY nombre;

-- 62 Zonas para dropdown en formularios
CREATE OR REPLACE VIEW v_zonas_lista AS
SELECT id_zona, nombre_zona FROM zonas ORDER BY nombre_zona;

-- 63 Cuidadores para dropdown en formularios
CREATE OR REPLACE VIEW v_cuidadores_dropdown AS
SELECT c.id_empleado AS id_cuidador,
       e.nombre || ' ' || e.apellido_p AS nombre
FROM cuidadores c
JOIN empleados e ON e.id_empleado = c.id_empleado
ORDER BY e.nombre;

-- 64 UPDATE v_pacientes_activos — añade aliases _pac que esperan los templates
CREATE OR REPLACE VIEW v_pacientes_activos AS
SELECT
    p.id_paciente,
    p.nombre                                               AS nombre_paciente,
    p.apellido_p                                           AS apellido_p_pac,
    p.apellido_m                                           AS apellido_m_pac,
    p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo,
    p.fecha_nacimiento,
    p.id_estado,
    ep.desc_estado,
    sp.id_sede AS id_sucursal,
    s.nombre_sede AS nombre_sucursal
FROM pacientes p
JOIN estados_paciente ep ON ep.id_estado = p.id_estado
LEFT JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
LEFT JOIN sedes s ON s.id_sede = sp.id_sede
WHERE p.id_estado != 3
ORDER BY p.id_paciente;

-- 65 UPDATE v_cuidadores — añade aliases _cuid que esperan los templates + CURP
CREATE OR REPLACE VIEW v_cuidadores AS
SELECT
    e.id_empleado               AS id_cuidador,
    e.nombre                    AS nombre_cuidador,
    e.apellido_p                AS apellido_p_cuid,
    e.apellido_m                AS apellido_m_cuid,
    e.nombre || ' ' || e.apellido_p AS nombre_completo,
    e.telefono                  AS telefono_cuid,
    e.CURP_pasaporte            AS curp_pasaporte,
    se.id_sede                  AS id_sucursal,
    s.nombre_sede               AS nombre_sucursal
FROM cuidadores c
JOIN empleados e ON e.id_empleado = c.id_empleado
LEFT JOIN sede_empleados se ON se.id_empleado = e.id_empleado AND se.fecha_salida IS NULL
LEFT JOIN sedes s ON s.id_sede = se.id_sede
ORDER BY e.id_empleado;

-- 66 Estadísticas globales en una sola fila (dashboard)
CREATE OR REPLACE VIEW v_dashboard_stats AS
SELECT
    (SELECT COUNT(*) FROM pacientes WHERE id_estado != 3)          AS pacientes,
    (SELECT COUNT(*) FROM cuidadores)                               AS cuidadores,
    (SELECT COUNT(*) FROM dispositivos WHERE estado = 'Activo')     AS dispositivos,
    (SELECT COUNT(*) FROM alertas    WHERE estatus = 'Activa')      AS alertas_activas;

-- 67 Últimas 10 alertas para el dashboard
CREATE OR REPLACE VIEW v_alertas_recientes AS
SELECT a.id_alerta, a.tipo_alerta,
       a.estatus    AS estatus_alerta,
       a.fecha_hora AS fecha_hora_lectura,
       COALESCE(p.nombre || ' ' || p.apellido_p, '— Zona —') AS paciente,
       sp.id_sede   AS id_sucursal,
       s.nombre_sede AS nombre_sucursal
FROM alertas a
LEFT JOIN pacientes p ON p.id_paciente = a.id_paciente
LEFT JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
LEFT JOIN sedes s ON s.id_sede = sp.id_sede
ORDER BY a.fecha_hora DESC
LIMIT 10;

-- 68 Alertas críticas activas para el banner del contexto (incluye Caída)
CREATE OR REPLACE VIEW v_alertas_banner AS
SELECT a.id_alerta, a.fecha_hora, a.tipo_alerta,
       COALESCE(p.nombre || ' ' || p.apellido_p, 'Zona') AS nombre_paciente
FROM alertas a
LEFT JOIN pacientes p ON p.id_paciente = a.id_paciente
WHERE a.estatus = 'Activa'
  AND a.tipo_alerta IN ('Salida de Zona', 'Botón SOS', 'Caída')
ORDER BY a.fecha_hora DESC;

-- 69 Estadísticas rápidas para la página de reportes
CREATE OR REPLACE VIEW v_reportes_stats AS
SELECT
    (SELECT COUNT(*) FROM alertas WHERE estatus = 'Activa')                              AS alertas_activas,
    (SELECT COUNT(*) FROM lecturas_nfc WHERE fecha_hora::date = CURRENT_DATE)            AS lecturas_nfc_hoy,
    (SELECT COUNT(*) FROM pacientes WHERE id_estado != 3)                                AS pacientes_activos;

-- 70 Todos los pacientes (incluye baja) para formulario de edición
CREATE OR REPLACE VIEW v_pacientes_todos AS
SELECT p.id_paciente,
       p.nombre      AS nombre_paciente,
       p.apellido_p  AS apellido_p_pac,
       p.apellido_m  AS apellido_m_pac,
       p.fecha_nacimiento, p.id_estado, ep.desc_estado
FROM pacientes p
JOIN estados_paciente ep ON ep.id_estado = p.id_estado
ORDER BY p.id_paciente;

-- 71 Detalle completo de una orden de suministro
CREATE OR REPLACE VIEW v_suministro_detalle AS
SELECT su.id_suministro,
       TO_CHAR(su.fecha_entrega, 'YYYY-MM-DD') AS fecha_entrega,
       su.hora_entrega, su.estado,
       fp.id_farmacia, fp.nombre AS farmacia, fp.telefono AS farmacia_tel,
       s.id_sede, s.nombre_sede
FROM suministros su
JOIN farmacias_proveedoras fp ON fp.id_farmacia = su.id_farmacia
JOIN sedes s ON s.id_sede = su.id_sede
ORDER BY su.id_suministro DESC;

-- 72 Detalle de receta con paciente y sede
CREATE OR REPLACE VIEW v_receta_detalle AS
SELECT r.id_receta, r.estado,
       TO_CHAR(r.fecha, 'DD/MM/YYYY') AS fecha,
       p.id_paciente,
       p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_paciente,
       COALESCE(s.nombre_sede, '—') AS nombre_sede
FROM recetas r
JOIN pacientes p ON p.id_paciente = r.id_paciente
LEFT JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
LEFT JOIN sedes s ON s.id_sede = sp.id_sede
ORDER BY r.id_receta DESC;

-- 73 Asignación NFC activa por paciente (historial)
CREATE OR REPLACE VIEW v_nfc_asignacion_paciente AS
SELECT an.id_asignacion, an.id_paciente, an.id_dispositivo,
       d.id_serial AS serial_nfc,
       TO_CHAR(an.fecha_inicio, 'YYYY-MM-DD') AS fecha_inicio
FROM asignacion_nfc an
JOIN dispositivos d ON d.id_dispositivo = an.id_dispositivo
WHERE an.fecha_fin IS NULL
ORDER BY an.id_paciente;

-- 74 Sede activa de cada paciente (para verificación de transferencia)
CREATE OR REPLACE VIEW v_sede_activa_paciente AS
SELECT id_sede_paciente, id_paciente, id_sede
FROM sede_pacientes
WHERE fecha_salida IS NULL
ORDER BY id_paciente;

-- 75 Catálogo de enfermedades (base para SP de enfermedades disponibles)
CREATE OR REPLACE VIEW v_enfermedades_catalogo AS
SELECT id_enfermedad, nombre_enfermedad FROM enfermedades ORDER BY nombre_enfermedad;

-- 76 Historial de lecturas NFC por receta (base, filtrar por id_receta en SP)
CREATE OR REPLACE VIEW v_lecturas_nfc_receta AS
SELECT ln.id_lectura_nfc, ln.id_receta,
       TO_CHAR(ln.fecha_hora, 'DD/MM/YYYY HH24:MI') AS fecha_hora,
       ln.tipo_lectura, ln.resultado
FROM lecturas_nfc ln
ORDER BY ln.id_receta, ln.fecha_hora DESC;

-- 77 Visitas históricas (anteriores a hoy) para página de visitas admin
CREATE OR REPLACE VIEW v_visitas_historial AS
SELECT v.id_visita, v.id_paciente,
       TO_CHAR(v.fecha_entrada, 'YYYY-MM-DD') AS fecha_entrada,
       v.hora_entrada, v.fecha_salida, v.hora_salida,
       p.nombre || ' ' || p.apellido_p AS paciente,
       vt.nombre || ' ' || vt.apellido_p AS visitante,
       vt.relacion,
       v.id_sede AS id_sucursal,
       s.nombre_sede AS nombre_sucursal
FROM visitas v
JOIN pacientes p ON p.id_paciente = v.id_paciente
JOIN visitantes vt ON vt.id_visitante = v.id_visitante
JOIN sedes s ON s.id_sede = v.id_sede
WHERE v.fecha_entrada < CURRENT_DATE
ORDER BY v.fecha_entrada DESC
LIMIT 50;

-- 78 Detecciones beacon recientes (log de rondas, LIMIT 200)
CREATE OR REPLACE VIEW v_rondas_recientes AS
SELECT db.id_deteccion, db.fecha_hora, db.rssi, db.id_gateway,
       d.id_serial AS serial_beacon,
       COALESCE(e.nombre || ' ' || e.apellido_p, 'Anónimo') AS nombre_cuidador
FROM detecciones_beacon db
JOIN dispositivos d ON d.id_dispositivo = db.id_dispositivo
LEFT JOIN cuidadores c ON c.id_empleado = db.id_cuidador
LEFT JOIN empleados e ON e.id_empleado = c.id_empleado
ORDER BY db.fecha_hora DESC
LIMIT 200;

-- 79 Todas las asignaciones beacon (incl. históricas con fecha_fin)
CREATE OR REPLACE VIEW v_asignacion_beacon_todas AS
SELECT ab.id_asignacion, ab.fecha_inicio, ab.fecha_fin,
       d.id_serial, d.modelo,
       e.nombre || ' ' || e.apellido_p AS nombre_cuidador
FROM asignacion_beacon ab
JOIN dispositivos d ON d.id_dispositivo = ab.id_dispositivo
JOIN empleados e ON e.id_empleado = ab.id_cuidador
ORDER BY ab.fecha_fin IS NULL DESC, ab.fecha_inicio DESC;

-- 80 Beacons disponibles para asignar (no tienen asignación activa)
CREATE OR REPLACE VIEW v_beacons_disponibles_asig AS
SELECT d.id_dispositivo, d.id_serial, d.modelo
FROM dispositivos d
WHERE d.tipo = 'BEACON'
  AND d.id_dispositivo NOT IN (
      SELECT id_dispositivo FROM asignacion_beacon WHERE fecha_fin IS NULL
  )
ORDER BY d.id_serial;

-- 81 Pacientes con sus datos para el dashboard del portal clínico
CREATE OR REPLACE VIEW v_clinica_pacientes AS
SELECT sp.id_sede, p.id_paciente,
       p.nombre AS nombre_paciente, p.apellido_p AS apellido_p_pac,
       p.apellido_m AS apellido_m_pac, p.fecha_nacimiento, ep.desc_estado
FROM pacientes p
JOIN estados_paciente ep ON ep.id_estado = p.id_estado
JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
WHERE p.id_estado != 3
ORDER BY sp.id_sede, p.nombre;

-- 82 Asignaciones de cuidadores con id_sede del paciente (clinica)
CREATE OR REPLACE VIEW v_clinica_asignaciones AS
SELECT sp.id_sede, ac.id_paciente,
       e.nombre AS nombre_cuidador, e.apellido_p, e.apellido_m,
       e.telefono AS telefono_cuid,
       TO_CHAR(ac.fecha_inicio, 'YYYY-MM-DD') AS fecha_asig_cuidador
FROM asignacion_cuidador ac
JOIN cuidadores c ON c.id_empleado = ac.id_cuidador
JOIN empleados e ON e.id_empleado = c.id_empleado
JOIN sede_pacientes sp ON sp.id_paciente = ac.id_paciente AND sp.fecha_salida IS NULL
WHERE ac.fecha_fin IS NULL
ORDER BY sp.id_sede, ac.id_paciente;

-- 83 Medicamentos activos con id_sede del paciente (clinica)
CREATE OR REPLACE VIEW v_clinica_meds AS
SELECT sp.id_sede, r.id_paciente, r.id_receta,
       m.nombre_medicamento AS medicamento, rm.dosis, rm.frecuencia_horas
FROM recetas r
JOIN receta_medicamentos rm ON rm.id_receta = r.id_receta
JOIN medicamentos m ON m.gtin = rm.gtin
JOIN sede_pacientes sp ON sp.id_paciente = r.id_paciente AND sp.fecha_salida IS NULL
WHERE r.estado = 'Activa'
ORDER BY sp.id_sede, r.id_paciente, m.nombre_medicamento;

-- 84 Enfermedades diagnosticadas con id_sede del paciente (clinica expedientes)
CREATE OR REPLACE VIEW v_clinica_enfermedades AS
SELECT sp.id_sede, te.id_paciente,
       e.nombre_enfermedad,
       TO_CHAR(te.fecha_diag, 'YYYY-MM-DD') AS fecha_diag
FROM tiene_enfermedad te
JOIN enfermedades e ON e.id_enfermedad = te.id_enfermedad
JOIN sede_pacientes sp ON sp.id_paciente = te.id_paciente AND sp.fecha_salida IS NULL
ORDER BY sp.id_sede, te.id_paciente;

-- 85 Alertas como incidentes con id_sede del paciente (clinica)
CREATE OR REPLACE VIEW v_clinica_incidentes AS
SELECT sp.id_sede,
       a.id_alerta AS id,
       TO_CHAR(a.fecha_hora, 'YYYY-MM-DD') AS fecha,
       TO_CHAR(a.fecha_hora, 'HH24:MI')    AS hora,
       a.id_paciente,
       p.nombre || ' ' || p.apellido_p AS paciente,
       a.tipo_alerta AS tipo,
       a.estatus     AS gravedad,
       NULL::TEXT    AS descripcion,
       NULL::TEXT    AS accion_tomada
FROM alertas a
JOIN pacientes p ON p.id_paciente = a.id_paciente
JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
ORDER BY sp.id_sede, a.fecha_hora DESC;

-- 86 Alertas médicas ACTIVAS con id_sede del paciente (clinica banner)
CREATE OR REPLACE VIEW v_clinica_alertas_activas AS
SELECT sp.id_sede,
       a.tipo_alerta AS tipo,
       p.nombre || ' ' || p.apellido_p AS paciente,
       TO_CHAR(a.fecha_hora, 'HH24:MI')    AS hora,
       TO_CHAR(a.fecha_hora, 'YYYY-MM-DD') AS fecha,
       a.estatus AS estado
FROM alertas a
JOIN pacientes p ON p.id_paciente = a.id_paciente
JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
WHERE a.estatus = 'Activa'
ORDER BY sp.id_sede, a.fecha_hora DESC;

-- 87 Bitácora del comedor de HOY con id_sede
CREATE OR REPLACE VIEW v_clinica_comedor_hoy AS
SELECT bc.id_bitacora AS id, bc.id_sede, bc.turno,
       bc.menu_nombre, bc.cantidad_platos, bc.incidencias,
       TO_CHAR(bc.fecha, 'YYYY-MM-DD') AS fecha,
       e.nombre || ' ' || e.apellido_p AS cocinero
FROM bitacora_comedor bc
JOIN cocineros co ON co.id_empleado = bc.id_cocinero
JOIN empleados e ON e.id_empleado = co.id_empleado
WHERE bc.fecha = CURRENT_DATE
ORDER BY bc.id_sede, bc.turno;

-- 88 Estado GPS más reciente por paciente, agrupado por sede (lateral join)
CREATE OR REPLACE VIEW v_clinica_gps_estado AS
SELECT sp.id_sede, p.id_paciente, p.nombre, p.apellido_p,
       lg.latitud, lg.longitud, lg.nivel_bateria,
       lg.fecha_hora AS ultima_lectura
FROM pacientes p
JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
LEFT JOIN asignacion_kit ak ON p.id_paciente = ak.id_paciente AND ak.fecha_fin IS NULL
LEFT JOIN LATERAL (
    SELECT latitud, longitud, nivel_bateria, fecha_hora
    FROM lecturas_gps
    WHERE id_dispositivo = ak.id_dispositivo_gps
    ORDER BY fecha_hora DESC LIMIT 1
) lg ON true
WHERE p.id_estado != 3
ORDER BY sp.id_sede, p.nombre;

-- 89 Zonas seguras de cada sede (para mapa clínico)
CREATE OR REPLACE VIEW v_clinica_zonas_mapa AS
SELECT sz.id_sede, z.id_zona, z.nombre_zona,
       z.latitud_centro, z.longitud_centro, z.radio_metros
FROM zonas z
JOIN sede_zonas sz ON sz.id_zona = z.id_zona
ORDER BY sz.id_sede, z.id_zona;

-- 89b Cobertura de zonas — turnos activos ahora mismo por sede (usa CASE DOW, sin f-string)
CREATE OR REPLACE VIEW v_clinica_cobertura_zonas AS
SELECT sz.id_sede, z.id_zona, z.nombre_zona,
       e.nombre || ' ' || e.apellido_p AS nombre_cuidador,
       tc.hora_inicio, tc.hora_fin
FROM turno_cuidador tc
JOIN zonas z       ON tc.id_zona      = z.id_zona
JOIN sede_zonas sz ON sz.id_zona      = z.id_zona
JOIN cuidadores c  ON tc.id_cuidador  = c.id_empleado
JOIN empleados  e  ON c.id_empleado   = e.id_empleado
WHERE tc.activo = TRUE
  AND tc.hora_inicio <= CURRENT_TIME
  AND tc.hora_fin    >  CURRENT_TIME
  AND CASE EXTRACT(DOW FROM CURRENT_DATE)
      WHEN 1 THEN tc.lunes   WHEN 2 THEN tc.martes  WHEN 3 THEN tc.miercoles
      WHEN 4 THEN tc.jueves  WHEN 5 THEN tc.viernes WHEN 6 THEN tc.sabado
      WHEN 0 THEN tc.domingo END = TRUE
ORDER BY sz.id_sede, z.nombre_zona, e.nombre;


-- 90 Pacientes en cada sede con alerta activa de Salida de Zona
CREATE OR REPLACE VIEW v_clinica_alertas_salida_zona AS
SELECT DISTINCT sp.id_sede, a.id_paciente
FROM alertas a
JOIN sede_pacientes sp ON sp.id_paciente = a.id_paciente AND sp.fecha_salida IS NULL
WHERE a.estatus = 'Activa' AND a.tipo_alerta = 'Salida de Zona';

-- 91 Medicamentos activos en cada sede (para tabla de adherencia clinica)
CREATE OR REPLACE VIEW v_clinica_meds_nfc_hoy AS
SELECT sp.id_sede, p.id_paciente, r.id_receta,
       p.nombre || ' ' || p.apellido_p AS nombre_paciente,
       m.nombre_medicamento, rm.dosis
FROM pacientes p
JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
JOIN recetas r ON r.id_paciente = p.id_paciente AND r.estado = 'Activa'
JOIN receta_medicamentos rm ON rm.id_receta = r.id_receta
JOIN medicamentos m ON m.gtin = rm.gtin
WHERE p.id_estado != 3
ORDER BY sp.id_sede, p.nombre, m.nombre_medicamento;

-- 92 Lecturas NFC exitosas de hoy, última por receta, con id_sede (para nfc_hoy dict)
CREATE OR REPLACE VIEW v_clinica_nfc_hoy AS
SELECT DISTINCT ON (ln.id_receta)
       sp.id_sede, ln.id_receta,
       TO_CHAR(ln.fecha_hora, 'HH24:MI') AS hora_toma
FROM lecturas_nfc ln
JOIN recetas r ON r.id_receta = ln.id_receta
JOIN sede_pacientes sp ON sp.id_paciente = r.id_paciente AND sp.fecha_salida IS NULL
WHERE ln.fecha_hora::date = CURRENT_DATE AND ln.resultado = 'Exitosa'
ORDER BY ln.id_receta, ln.fecha_hora DESC;

-- 93 Conteo de cuidadores en turno ahora mismo, por sede
CREATE OR REPLACE VIEW v_staff_en_turno AS
SELECT sz.id_sede, COUNT(DISTINCT tc.id_cuidador) AS staff_count
FROM turno_cuidador tc
JOIN sede_zonas sz ON sz.id_zona = tc.id_zona
WHERE tc.activo = TRUE
  AND tc.hora_inicio <= CURRENT_TIME
  AND tc.hora_fin    >  CURRENT_TIME
  AND CASE EXTRACT(DOW FROM CURRENT_DATE)
      WHEN 1 THEN tc.lunes   WHEN 2 THEN tc.martes  WHEN 3 THEN tc.miercoles
      WHEN 4 THEN tc.jueves  WHEN 5 THEN tc.viernes WHEN 6 THEN tc.sabado
      WHEN 0 THEN tc.domingo END = TRUE
GROUP BY sz.id_sede;

-- 94 Dispositivos GPS activos asignados a pacientes (simulador GPS)
CREATE OR REPLACE VIEW v_dispositivos_gps_activos AS
SELECT d.id_dispositivo, d.id_serial, d.modelo,
       p.nombre || ' ' || p.apellido_p AS paciente,
       ak.id_paciente
FROM dispositivos d
JOIN asignacion_kit ak ON ak.id_dispositivo_gps = d.id_dispositivo AND ak.fecha_fin IS NULL
JOIN pacientes p ON p.id_paciente = ak.id_paciente
WHERE d.tipo = 'GPS' AND d.estado = 'Activo' AND p.id_estado != 3
ORDER BY p.nombre;

-- 95 Zonas seguras con nombre de sede (mapa de referencia simulador GPS)
CREATE OR REPLACE VIEW v_zonas_ref AS
SELECT z.id_zona, z.nombre_zona, z.latitud_centro, z.longitud_centro,
       z.radio_metros, s.nombre_sede
FROM zonas z
LEFT JOIN sede_zonas sz ON sz.id_zona = z.id_zona
LEFT JOIN sedes s ON s.id_sede = sz.id_sede
ORDER BY z.id_zona;

-- 96 Últimas 3 alertas (feedback del simulador GPS)
CREATE OR REPLACE VIEW v_alertas_sim_recientes AS
SELECT id_alerta, tipo_alerta, estatus
FROM alertas
ORDER BY id_alerta DESC
LIMIT 3;

-- 97 Último id_lectura GPS (para obtener id tras inserción simulada)
CREATE OR REPLACE VIEW v_last_id_lectura_gps AS
SELECT MAX(id_lectura) AS id_lectura FROM lecturas_gps;

-- 98 Datos de contacto para login del portal familiar
CREATE OR REPLACE VIEW v_contacto_login AS
SELECT id_contacto, nombre, apellido_p,
       LOWER(email) AS email, pin_acceso
FROM contactos_emergencia;

-- 99 Alerta crítica activa más reciente por paciente (portal familiar)
CREATE OR REPLACE VIEW v_alerta_critica_por_paciente AS
SELECT DISTINCT ON (a.id_paciente)
       a.id_paciente, a.tipo_alerta, a.fecha_hora
FROM alertas a
WHERE a.estatus = 'Activa'
  AND a.tipo_alerta IN ('Salida de Zona', 'Botón SOS')
ORDER BY a.id_paciente, a.fecha_hora DESC;

-- 100 Timestamp de última actividad por paciente (GPS, NFC o alerta)
CREATE OR REPLACE VIEW v_ultima_actividad_ts AS
SELECT ev.id_paciente, MAX(ev.ts) AS ultima_actividad
FROM (
    SELECT ak.id_paciente, lg.fecha_hora AS ts
    FROM lecturas_gps lg
    JOIN asignacion_kit ak ON ak.id_dispositivo_gps = lg.id_dispositivo AND ak.fecha_fin IS NULL
    UNION ALL
    SELECT r.id_paciente, ln.fecha_hora AS ts
    FROM lecturas_nfc ln
    JOIN recetas r ON r.id_receta = ln.id_receta
    UNION ALL
    SELECT a.id_paciente, a.fecha_hora AS ts
    FROM alertas a WHERE a.id_paciente IS NOT NULL
) ev
GROUP BY ev.id_paciente;

-- 101 Última ronda de cuidador por paciente (vía sede compartida)
CREATE OR REPLACE VIEW v_ultima_ronda_por_paciente AS
SELECT sp.id_paciente, MAX(db2.fecha_hora) AS ultima_ronda
FROM detecciones_beacon db2
JOIN asignacion_beacon ab ON ab.id_dispositivo = db2.id_dispositivo AND ab.fecha_fin IS NULL
JOIN sede_empleados se    ON se.id_empleado = ab.id_cuidador
JOIN sede_pacientes sp    ON sp.id_sede = se.id_sede AND sp.fecha_salida IS NULL
GROUP BY sp.id_paciente;

-- 102 Dosis NFC exitosas de hoy por paciente (portal familiar)
CREATE OR REPLACE VIEW v_dosis_nfc_hoy AS
SELECT r.id_paciente, COUNT(ln.id_lectura_nfc) AS dosis_hoy
FROM lecturas_nfc ln
JOIN recetas r ON r.id_receta = ln.id_receta
WHERE ln.fecha_hora::DATE = CURRENT_DATE AND ln.resultado = 'Exitosa'
GROUP BY r.id_paciente;

-- 103 Visitas recientes por paciente (portal familiar, sin límite — limitar en SP)
CREATE OR REPLACE VIEW v_visitas_portal AS
SELECT v.id_paciente,
       TO_CHAR(v.fecha_entrada, 'YYYY-MM-DD') AS fecha,
       v.hora_entrada, v.hora_salida,
       vt.nombre || ' ' || vt.apellido_p AS visitante,
       vt.relacion
FROM visitas v
JOIN visitantes vt ON vt.id_visitante = v.id_visitante
ORDER BY v.id_paciente, v.fecha_entrada DESC, v.hora_entrada DESC;

-- 104 Vínculo contacto-paciente (verificación de seguridad portal familiar)
CREATE OR REPLACE VIEW v_contacto_verificacion AS
SELECT id_paciente, id_contacto FROM paciente_contactos;

-- 105 Alertas activas por paciente (portal familiar)
CREATE OR REPLACE VIEW v_alertas_activas_paciente AS
SELECT a.id_paciente, a.tipo_alerta,
       TO_CHAR(a.fecha_hora, 'YYYY-MM-DD') AS fecha,
       TO_CHAR(a.fecha_hora, 'HH24:MI')    AS hora
FROM alertas a
WHERE a.estatus = 'Activa'
ORDER BY a.id_paciente, a.fecha_hora DESC;

-- 106 Lookup de dispositivo por serial e tipo (APIs IoT)
CREATE OR REPLACE VIEW v_dispositivo_serial AS
SELECT id_dispositivo, id_serial, tipo, modelo, estado FROM dispositivos;

-- 107 Enlace activo receta↔dispositivo NFC (API NFC)
CREATE OR REPLACE VIEW v_receta_nfc_activa AS
SELECT id_receta, id_dispositivo FROM receta_nfc WHERE fecha_fin_gestion IS NULL;

-- 108 Asignación activa beacon↔cuidador con nombre (API beacon)
CREATE OR REPLACE VIEW v_asignacion_beacon_cuidador AS
SELECT ab.id_dispositivo, ab.id_cuidador,
       e.nombre || ' ' || e.apellido_p AS nombre
FROM asignacion_beacon ab
JOIN empleados e ON e.id_empleado = ab.id_cuidador
WHERE ab.fecha_fin IS NULL;

-- 109 Última detección por dispositivo beacon (API beacon, post-insert)
CREATE OR REPLACE VIEW v_ultima_deteccion_por_beacon AS
SELECT DISTINCT ON (id_dispositivo)
       id_dispositivo, id_deteccion, fecha_hora
FROM detecciones_beacon
ORDER BY id_dispositivo, fecha_hora DESC;

-- 110 Paciente vinculado a dispositivo NFC activo (API NFC test)
CREATE OR REPLACE VIEW v_paciente_por_nfc AS
SELECT an.id_dispositivo, d.id_serial, p.id_paciente, p.nombre, p.apellido_p
FROM asignacion_nfc an
JOIN dispositivos d ON d.id_dispositivo = an.id_dispositivo
JOIN pacientes p ON p.id_paciente = an.id_paciente
WHERE an.fecha_fin IS NULL;

-- 111 Siguiente id_receta
CREATE OR REPLACE VIEW v_next_id_receta AS
SELECT COALESCE(MAX(id_receta), 0) + 1 AS next_id FROM recetas;

-- 112 Siguiente id_detalle de receta
CREATE OR REPLACE VIEW v_next_id_detalle_receta AS
SELECT COALESCE(MAX(id_detalle), 0) + 1 AS next_id FROM receta_medicamentos;

-- 113 Siguiente id_lectura_nfc
CREATE OR REPLACE VIEW v_next_id_lectura_nfc AS
SELECT COALESCE(MAX(id_lectura_nfc), 0) + 1 AS next_id FROM lecturas_nfc;


-- -----------------------------------------------------------------------------
-- Confirmación
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '✓ v_pacientes_activos';
    RAISE NOTICE '✓ v_cuidadores';
    RAISE NOTICE '✓ v_dispositivos';
    RAISE NOTICE '✓ v_zonas';
    RAISE NOTICE '✓ v_alertas';
    RAISE NOTICE '✓ v_recetas';
    RAISE NOTICE '✓ v_turnos';
    RAISE NOTICE '✓ v_detecciones_beacon';
    RAISE NOTICE '✓ v_kit_gps_activo';
    RAISE NOTICE '✓ v_inventario_farmacia';
    RAISE NOTICE '✓ v_suministros';
    RAISE NOTICE '✓ v_visitas';
    RAISE NOTICE '✓ v_entregas_externas';
    RAISE NOTICE '✓ v_receta_medicamentos';
    RAISE NOTICE '✓ v_nfc_activo';
    RAISE NOTICE '✓ v_asignacion_beacon';
    RAISE NOTICE '✓ v_cuidadores_asignados';
    RAISE NOTICE '✓ v_medicamentos_por_paciente';
    RAISE NOTICE '✓ v_contactos_emergencia';
    RAISE NOTICE '✓ v_ultima_lectura_gps';
    RAISE NOTICE '✓ v_enfermedades_paciente';
    RAISE NOTICE '✓ v_adherencia_nfc_30d';
    RAISE NOTICE '✓ v_pacientes_sin_gps';
    RAISE NOTICE '✓ v_historial_sedes_paciente';
    RAISE NOTICE '✓ v_alertas_activas';
    RAISE NOTICE '✓ v_lecturas_gps_recientes';
    RAISE NOTICE '✓ v_cuidadores_sin_beacon';
    RAISE NOTICE '✓ v_resumen_alertas_por_tipo';
    RAISE NOTICE '✓ v_visitas_recientes';
    RAISE NOTICE '✓ v_pacientes_transferidos';
    RAISE NOTICE '✓ v_stats_por_sede';
    RAISE NOTICE '✓ v_suministros_pendientes';
    RAISE NOTICE '✓ v_medicamentos_criticos';
    RAISE NOTICE '✓ v_nfc_disponibles';
    RAISE NOTICE '✓ v_gps_disponibles';
    RAISE NOTICE '✓ v_lineas_suministro';
    RAISE NOTICE '✓ v_lecturas_nfc_recientes';
    RAISE NOTICE '✓ v_cuidadores_en_turno';
    RAISE NOTICE '✓ v_bitacora_comedor';
    RAISE NOTICE '✓ v_pacientes_por_contacto';
    RAISE NOTICE '✓ v_zonas_por_paciente';
    RAISE NOTICE '✓ v_alertas_criticas_activas';
    RAISE NOTICE '✓ v_alertas_historial_30d';
    RAISE NOTICE '✓ v_medicamentos_adherencia_hoy';
    RAISE NOTICE '✓ v_entregas_pendientes';
    RAISE NOTICE '✓ v_visitas_hoy';
    RAISE NOTICE '✓ v_ultima_actividad_paciente';
    RAISE NOTICE '✓ v_alertas_por_sede';
    RAISE NOTICE '✓ v_expediente_clinico';
    RAISE NOTICE '✓ v_alertas_por_dia_14d';
    RAISE NOTICE '✓ v_stock_farmacia_completo';
    RAISE NOTICE '✓ v_adherencia_nfc_por_paciente';
    RAISE NOTICE '✓ v_bateria_historial_gps';
    RAISE NOTICE '✓ v_lecturas_gps_paciente';
    RAISE NOTICE '54 vistas aplicadas correctamente.';
END;
$$;
