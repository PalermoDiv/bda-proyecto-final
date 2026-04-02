-- =============================================================================
-- finalqueries.sql — AlzMonitor
-- Queries de producción basadas en ProyectoFinalDDL.sql
-- Correcciones aplicadas según retroalimentación del profesor:
--   · Q3/Q10  : DISTINCT ON en lugar de subconsulta MAX(fecha_hora) ambigua
--   · Q5      : ORDER BY total_salidas_zona DESC (mayor riesgo primero)
--   · Q10     : acos() protegido con LEAST/GREATEST contra errores de dominio
--   · Q11/Q12 : adherencia reescrita sobre lecturas_nfc, sin paciente_recetas
--   · Nuevas  : tendencias, MTTA, tiempo fuera de zona, SLA, comparativo sedes
-- =============================================================================


-- =============================================================================
-- SECCIÓN 1: MONITOREO EN TIEMPO REAL
-- =============================================================================

-- 1. Pacientes con alertas activas — incluye sede y tipo de evento origen
SELECT p.id_paciente,
       p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo,
       a.id_alerta,
       a.tipo_alerta,
       a.fecha_hora,
       aeo.tipo_evento,
       aeo.regla_disparada,
       s.nombre_sede
FROM pacientes p
JOIN alertas a          ON p.id_paciente  = a.id_paciente
LEFT JOIN alerta_evento_origen aeo ON aeo.id_alerta = a.id_alerta
LEFT JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                           AND sp.fecha_salida IS NULL
LEFT JOIN sedes s        ON sp.id_sede = s.id_sede
WHERE a.estatus = 'Activa'
ORDER BY a.fecha_hora DESC;


-- 2. Pacientes con más de una alerta activa simultánea
SELECT p.id_paciente,
       p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo,
       s.nombre_sede,
       STRING_AGG(a.tipo_alerta, ', ' ORDER BY a.tipo_alerta) AS tipos_alerta,
       COUNT(a.id_alerta) AS total_alertas_activas
FROM pacientes p
JOIN alertas a ON p.id_paciente = a.id_paciente
LEFT JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                           AND sp.fecha_salida IS NULL
LEFT JOIN sedes s ON sp.id_sede = s.id_sede
WHERE a.estatus = 'Activa'
GROUP BY p.id_paciente, p.nombre, p.apellido_p, p.apellido_m, s.nombre_sede
HAVING COUNT(a.id_alerta) > 1
ORDER BY total_alertas_activas DESC;


-- 3. Última ubicación de cada paciente
--    DISTINCT ON elimina la ambigüedad del MAX(fecha_hora): en empate de timestamp
--    desempata por id_lectura DESC (lectura más tardía registrada en la BD).
SELECT DISTINCT ON (p.id_paciente)
       p.id_paciente,
       p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo,
       lg.latitud,
       lg.longitud,
       lg.fecha_hora         AS ultima_lectura,
       lg.nivel_bateria      AS bateria_pct,
       s.nombre_sede
FROM pacientes p
JOIN asignacion_kit ak  ON p.id_paciente          = ak.id_paciente
JOIN lecturas_gps lg    ON ak.id_dispositivo_gps  = lg.id_dispositivo
LEFT JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                           AND sp.fecha_salida IS NULL
LEFT JOIN sedes s       ON sp.id_sede = s.id_sede
WHERE p.id_estado != 3
ORDER BY p.id_paciente,
         lg.fecha_hora  DESC,
         lg.id_lectura  DESC;


-- 4. Pacientes actualmente fuera de zona (alerta activa de salida)
SELECT p.id_paciente,
       p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo,
       a.fecha_hora AS hora_salida_zona,
       s.nombre_sede,
       aeo.regla_disparada
FROM pacientes p
JOIN alertas a ON p.id_paciente = a.id_paciente
LEFT JOIN alerta_evento_origen aeo ON aeo.id_alerta = a.id_alerta
LEFT JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                           AND sp.fecha_salida IS NULL
LEFT JOIN sedes s ON sp.id_sede = s.id_sede
WHERE a.tipo_alerta = 'Salida de Zona'
  AND a.estatus     = 'Activa'
ORDER BY a.fecha_hora DESC;


-- 5. Batería crítica — dispositivos GPS con nivel <= 20%
SELECT DISTINCT ON (d.id_dispositivo)
       d.id_dispositivo,
       d.id_serial,
       d.modelo,
       lg.nivel_bateria AS bateria_pct,
       lg.fecha_hora    AS ultima_lectura,
       p.nombre || ' ' || p.apellido_p AS paciente,
       s.nombre_sede
FROM dispositivos d
JOIN lecturas_gps lg    ON d.id_dispositivo       = lg.id_dispositivo
LEFT JOIN asignacion_kit ak ON d.id_dispositivo   = ak.id_dispositivo_gps
LEFT JOIN pacientes p   ON ak.id_paciente          = p.id_paciente
LEFT JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                           AND sp.fecha_salida IS NULL
LEFT JOIN sedes s       ON sp.id_sede = s.id_sede
WHERE d.tipo = 'GPS'
  AND lg.nivel_bateria IS NOT NULL
ORDER BY d.id_dispositivo,
         lg.fecha_hora DESC,
         lg.id_lectura DESC
-- filtrar después del DISTINCT ON usando subquery
HAVING FALSE; -- placeholder: ver query completa abajo

-- Versión correcta con subquery:
SELECT *
FROM (
    SELECT DISTINCT ON (d.id_dispositivo)
           d.id_dispositivo,
           d.id_serial,
           lg.nivel_bateria AS bateria_pct,
           lg.fecha_hora    AS ultima_lectura,
           p.nombre || ' ' || p.apellido_p AS paciente,
           s.nombre_sede
    FROM dispositivos d
    JOIN lecturas_gps lg    ON d.id_dispositivo      = lg.id_dispositivo
    LEFT JOIN asignacion_kit ak ON d.id_dispositivo  = ak.id_dispositivo_gps
    LEFT JOIN pacientes p   ON ak.id_paciente         = p.id_paciente
    LEFT JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                               AND sp.fecha_salida IS NULL
    LEFT JOIN sedes s       ON sp.id_sede = s.id_sede
    WHERE d.tipo = 'GPS'
    ORDER BY d.id_dispositivo,
             lg.fecha_hora DESC,
             lg.id_lectura DESC
) AS ultima_bat
WHERE bateria_pct <= 20
ORDER BY bateria_pct ASC;


-- =============================================================================
-- SECCIÓN 2: RIESGO Y SEGURIDAD
-- =============================================================================

-- 6. Ranking de pacientes por número de salidas de zona — MAYOR RIESGO PRIMERO
--    (corregido: era ORDER BY ASC)
SELECT p.id_paciente,
       p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo,
       s.nombre_sede,
       COUNT(a.id_alerta)                                      AS total_salidas_zona,
       COUNT(a.id_alerta) FILTER (WHERE a.estatus = 'Activa')  AS salidas_activas,
       MAX(a.fecha_hora)                                        AS ultima_salida
FROM pacientes p
JOIN alertas a ON p.id_paciente = a.id_paciente
LEFT JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                           AND sp.fecha_salida IS NULL
LEFT JOIN sedes s ON sp.id_sede = s.id_sede
WHERE a.tipo_alerta = 'Salida de Zona'
GROUP BY p.id_paciente, p.nombre, p.apellido_p, p.apellido_m, s.nombre_sede
ORDER BY total_salidas_zona DESC;


-- 7. Distancia de cada paciente respecto a su zona segura (última lectura GPS)
--    acos() protegido con LEAST(1, GREATEST(-1, ...)) para evitar error de dominio
--    cuando floating point produce valores marginalmente fuera de [-1, 1].
SELECT p.id_paciente,
       p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo,
       z.nombre_zona,
       ROUND(ultima.latitud::NUMERIC,  6) AS lat_actual,
       ROUND(ultima.longitud::NUMERIC, 6) AS lon_actual,
       z.radio_metros,
       ROUND((
           6371000 * ACOS(
               LEAST(1.0, GREATEST(-1.0,
                   COS(RADIANS(z.latitud_centro))  * COS(RADIANS(ultima.latitud)) *
                   COS(RADIANS(ultima.longitud) - RADIANS(z.longitud_centro)) +
                   SIN(RADIANS(z.latitud_centro))  * SIN(RADIANS(ultima.latitud))
               ))
           )
       )::NUMERIC, 2) AS distancia_metros,
       ROUND((
           6371000 * ACOS(
               LEAST(1.0, GREATEST(-1.0,
                   COS(RADIANS(z.latitud_centro))  * COS(RADIANS(ultima.latitud)) *
                   COS(RADIANS(ultima.longitud) - RADIANS(z.longitud_centro)) +
                   SIN(RADIANS(z.latitud_centro))  * SIN(RADIANS(ultima.latitud))
               ))
           ) - z.radio_metros
       )::NUMERIC, 2) AS exceso_metros,
       ultima.ultima_lectura
FROM pacientes p
JOIN asignacion_kit ak ON p.id_paciente = ak.id_paciente
JOIN (
    -- DISTINCT ON garantiza exactamente una fila por dispositivo, desempata por id_lectura
    SELECT DISTINCT ON (id_dispositivo)
           id_dispositivo, latitud, longitud, fecha_hora AS ultima_lectura
    FROM lecturas_gps
    ORDER BY id_dispositivo, fecha_hora DESC, id_lectura DESC
) AS ultima ON ultima.id_dispositivo = ak.id_dispositivo_gps
JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                      AND sp.fecha_salida IS NULL
JOIN sede_zonas sz      ON sp.id_sede   = sz.id_sede
JOIN zonas z            ON sz.id_zona   = z.id_zona
WHERE p.id_estado != 3
ORDER BY exceso_metros DESC NULLS LAST;


-- 8. Trayectoria histórica de un paciente (reemplazar :id_paciente por el ID)
SELECT lg.id_lectura,
       lg.latitud,
       lg.longitud,
       lg.nivel_bateria,
       lg.fecha_hora,
       d.id_serial AS dispositivo
FROM lecturas_gps lg
JOIN asignacion_kit ak ON lg.id_dispositivo = ak.id_dispositivo_gps
JOIN dispositivos d    ON lg.id_dispositivo = d.id_dispositivo
WHERE ak.id_paciente = :id_paciente   -- parámetro
ORDER BY lg.fecha_hora ASC;


-- =============================================================================
-- SECCIÓN 3: ADHERENCIA TERAPÉUTICA
-- =============================================================================

-- 9. Adherencia terapéutica por paciente — usa lecturas_nfc (no detecciones_beacon)
--    Elimina referencia a paciente_recetas (tabla eliminada del esquema).
SELECT
    p.id_paciente,
    p.nombre || ' ' || p.apellido_p                                              AS nombre_paciente,
    m.nombre_medicamento,
    rm.dosis,
    rm.frecuencia_horas,
    COUNT(ln.id_lectura_nfc)                                                     AS total_lecturas_mes,
    COUNT(ln.id_lectura_nfc) FILTER (WHERE ln.resultado = 'Exitosa')             AS lecturas_exitosas,
    COUNT(ln.id_lectura_nfc) FILTER (WHERE ln.resultado != 'Exitosa')            AS lecturas_fallidas,
    ROUND(
        100.0 * COUNT(ln.id_lectura_nfc) FILTER (WHERE ln.resultado = 'Exitosa')
        / NULLIF(COUNT(ln.id_lectura_nfc), 0)
    , 1)                                                                         AS pct_adherencia
FROM pacientes p
JOIN recetas r              ON r.id_paciente    = p.id_paciente
JOIN receta_medicamentos rm ON rm.id_receta     = r.id_receta
JOIN medicamentos m         ON m.GTIN           = rm.GTIN
JOIN receta_nfc rn          ON rn.id_receta     = r.id_receta
                           AND rn.fecha_fin_gestion IS NULL
LEFT JOIN lecturas_nfc ln   ON ln.id_dispositivo = rn.id_dispositivo
                           AND ln.id_receta       = r.id_receta
                           AND ln.fecha_hora      >= CURRENT_DATE - INTERVAL '30 days'
WHERE p.id_estado != 3
GROUP BY p.id_paciente, p.nombre, p.apellido_p,
         m.nombre_medicamento, rm.dosis, rm.frecuencia_horas
ORDER BY pct_adherencia ASC NULLS FIRST;


-- 10. Dispositivos NFC activos por sede con total de usos reales (lecturas_nfc)
SELECT
    s.nombre_sede,
    d.id_serial         AS serial_nfc,
    d.modelo,
    d.estado,
    p.nombre || ' ' || p.apellido_p AS paciente_asignado,
    COUNT(ln.id_lectura_nfc)                                          AS total_usos,
    COUNT(ln.id_lectura_nfc) FILTER (WHERE ln.resultado = 'Exitosa') AS usos_exitosos
FROM dispositivos d
JOIN receta_nfc rn     ON rn.id_dispositivo  = d.id_dispositivo
                      AND rn.fecha_fin_gestion IS NULL
JOIN recetas r         ON r.id_receta        = rn.id_receta
JOIN pacientes p       ON p.id_paciente      = r.id_paciente
JOIN sede_pacientes sp ON sp.id_paciente     = p.id_paciente
                      AND sp.fecha_salida IS NULL
JOIN sedes s           ON s.id_sede          = sp.id_sede
LEFT JOIN lecturas_nfc ln ON ln.id_dispositivo = d.id_dispositivo
WHERE d.tipo = 'NFC'
GROUP BY s.nombre_sede, d.id_serial, d.modelo, d.estado,
         p.nombre, p.apellido_p
ORDER BY s.nombre_sede, total_usos DESC;


-- =============================================================================
-- SECCIÓN 4: CLÍNICO — EXPEDIENTES
-- =============================================================================

-- 11. Pacientes con sus enfermedades y fecha de diagnóstico
SELECT p.id_paciente,
       p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo,
       e.nombre_enfermedad,
       te.fecha_diag,
       ep.desc_estado,
       s.nombre_sede
FROM pacientes p
JOIN tiene_enfermedad te ON p.id_paciente   = te.id_paciente
JOIN enfermedades e      ON te.id_enfermedad = e.id_enfermedad
JOIN estados_paciente ep ON p.id_estado      = ep.id_estado
LEFT JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                           AND sp.fecha_salida IS NULL
LEFT JOIN sedes s ON sp.id_sede = s.id_sede
WHERE p.id_estado != 3
ORDER BY e.nombre_enfermedad, p.apellido_p;


-- 12. Relación paciente-cuidador activa (fecha_fin IS NULL)
SELECT p.id_paciente,
       p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_paciente,
       e.id_empleado   AS id_cuidador,
       e.nombre || ' ' || e.apellido_p || ' ' || e.apellido_m AS nombre_cuidador,
       e.telefono      AS telefono_cuidador,
       ac.fecha_inicio AS asignado_desde,
       s.nombre_sede
FROM pacientes p
JOIN asignacion_cuidador ac ON p.id_paciente  = ac.id_paciente
                           AND ac.fecha_fin IS NULL
JOIN cuidadores c           ON ac.id_cuidador = c.id_empleado
JOIN empleados e            ON c.id_empleado  = e.id_empleado
LEFT JOIN sede_pacientes sp ON p.id_paciente  = sp.id_paciente
                           AND sp.fecha_salida IS NULL
LEFT JOIN sedes s           ON sp.id_sede = s.id_sede
WHERE p.id_estado != 3
ORDER BY s.nombre_sede, p.apellido_p;


-- 13. Frecuencia de tipos de alerta con porcentaje del total
SELECT tipo_alerta,
       COUNT(*)                                      AS total,
       COUNT(*) FILTER (WHERE estatus = 'Activa')    AS activas,
       COUNT(*) FILTER (WHERE estatus = 'Atendida')  AS atendidas,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_del_total
FROM alertas
GROUP BY tipo_alerta
ORDER BY total DESC;


-- =============================================================================
-- SECCIÓN 5: ANALÍTICA Y TENDENCIAS
-- =============================================================================

-- 14. Tendencia diaria de alertas — últimos 30 días
SELECT DATE_TRUNC('day', fecha_hora)::DATE   AS dia,
       COUNT(*)                              AS total_alertas,
       COUNT(*) FILTER (WHERE tipo_alerta = 'Salida de Zona') AS salidas_zona,
       COUNT(*) FILTER (WHERE tipo_alerta = 'Batería Baja')   AS bateria_baja,
       COUNT(*) FILTER (WHERE tipo_alerta = 'Botón SOS')      AS sos,
       COUNT(*) FILTER (WHERE tipo_alerta = 'Caída')          AS caidas
FROM alertas
WHERE fecha_hora >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE_TRUNC('day', fecha_hora)
ORDER BY dia;


-- 15. Tendencia semanal de alertas — últimas 12 semanas
SELECT DATE_TRUNC('week', fecha_hora)::DATE  AS semana_inicio,
       COUNT(*)                              AS total_alertas,
       COUNT(*) FILTER (WHERE estatus = 'Activa')   AS pendientes,
       COUNT(*) FILTER (WHERE estatus = 'Atendida') AS resueltas,
       ROUND(
           100.0 * COUNT(*) FILTER (WHERE estatus = 'Atendida')
           / NULLIF(COUNT(*), 0)
       , 1)                                  AS pct_resolucion
FROM alertas
WHERE fecha_hora >= CURRENT_DATE - INTERVAL '12 weeks'
GROUP BY DATE_TRUNC('week', fecha_hora)
ORDER BY semana_inicio;


-- 16. Distribución de alertas por tipo y sede
SELECT s.nombre_sede,
       a.tipo_alerta,
       COUNT(*)                                       AS total,
       COUNT(*) FILTER (WHERE a.estatus = 'Activa')   AS activas,
       MAX(a.fecha_hora)                               AS ultima_ocurrencia
FROM alertas a
JOIN sede_pacientes sp ON a.id_paciente  = sp.id_paciente
                      AND sp.fecha_salida IS NULL
JOIN sedes s           ON sp.id_sede = s.id_sede
GROUP BY s.nombre_sede, a.tipo_alerta
ORDER BY s.nombre_sede, total DESC;


-- 17. MTTA — Tiempo Medio de Atención de Alertas por sede y tipo
--     NOTA: requiere columna fecha_atencion TIMESTAMP en tabla alertas.
--     ALTER TABLE alertas ADD COLUMN fecha_atencion TIMESTAMP;
--     Se registra cuando el personal marca la alerta como 'Atendida'.
SELECT s.nombre_sede,
       a.tipo_alerta,
       COUNT(*)                                                          AS total_atendidas,
       ROUND(AVG(
           EXTRACT(EPOCH FROM (a.fecha_atencion - a.fecha_hora)) / 60.0
       )::NUMERIC, 1)                                                    AS mtta_promedio_min,
       ROUND(MIN(
           EXTRACT(EPOCH FROM (a.fecha_atencion - a.fecha_hora)) / 60.0
       )::NUMERIC, 1)                                                    AS mtta_min_min,
       ROUND(MAX(
           EXTRACT(EPOCH FROM (a.fecha_atencion - a.fecha_hora)) / 60.0
       )::NUMERIC, 1)                                                    AS mtta_max_min
FROM alertas a
JOIN sede_pacientes sp ON a.id_paciente  = sp.id_paciente
                      AND sp.fecha_salida IS NULL
JOIN sedes s           ON sp.id_sede = s.id_sede
WHERE a.estatus       = 'Atendida'
  AND a.fecha_atencion IS NOT NULL
GROUP BY s.nombre_sede, a.tipo_alerta
ORDER BY s.nombre_sede, mtta_promedio_min DESC;


-- 18. SLA de alertas por sede — % atendidas en menos de 30 minutos
--     (requiere fecha_atencion en alertas — ver nota query 17)
SELECT s.nombre_sede,
       COUNT(*)                                                                   AS total_atendidas,
       COUNT(*) FILTER (
           WHERE EXTRACT(EPOCH FROM (a.fecha_atencion - a.fecha_hora)) / 60.0 <= 30
       )                                                                          AS dentro_sla,
       ROUND(
           100.0 * COUNT(*) FILTER (
               WHERE EXTRACT(EPOCH FROM (a.fecha_atencion - a.fecha_hora)) / 60.0 <= 30
           ) / NULLIF(COUNT(*), 0)
       , 1)                                                                       AS pct_sla
FROM alertas a
JOIN sede_pacientes sp ON a.id_paciente  = sp.id_paciente
                      AND sp.fecha_salida IS NULL
JOIN sedes s           ON sp.id_sede = s.id_sede
WHERE a.estatus        = 'Atendida'
  AND a.fecha_atencion IS NOT NULL
GROUP BY s.nombre_sede
ORDER BY pct_sla DESC;


-- 19. Comparativo de pacientes activos, alertas y dispositivos por sede
SELECT s.id_sede,
       s.nombre_sede,
       COUNT(DISTINCT sp.id_paciente)                             AS pacientes_activos,
       COUNT(DISTINCT CASE WHEN a.estatus = 'Activa'
                           THEN a.id_alerta END)                  AS alertas_activas,
       COUNT(DISTINCT ak.id_dispositivo_gps)                      AS kits_asignados,
       ROUND(
           COUNT(DISTINCT CASE WHEN a.estatus = 'Activa'
                               THEN a.id_alerta END)::NUMERIC
           / NULLIF(COUNT(DISTINCT sp.id_paciente), 0)
       , 2)                                                        AS ratio_alertas_paciente
FROM sedes s
LEFT JOIN sede_pacientes sp ON s.id_sede     = sp.id_sede
                           AND sp.fecha_salida IS NULL
LEFT JOIN pacientes p       ON sp.id_paciente = p.id_paciente
                           AND p.id_estado != 3
LEFT JOIN alertas a         ON p.id_paciente  = a.id_paciente
LEFT JOIN asignacion_kit ak ON p.id_paciente  = ak.id_paciente
GROUP BY s.id_sede, s.nombre_sede
ORDER BY s.id_sede;


-- =============================================================================
-- SECCIÓN 6: FARMACIA E INVENTARIO
-- =============================================================================

-- 20. Stock crítico de medicamentos por sede (stock_actual < stock_minimo)
SELECT s.nombre_sede,
       m.nombre_medicamento,
       im.stock_actual,
       im.stock_minimo,
       im.stock_minimo - im.stock_actual AS unidades_faltantes
FROM inventario_medicinas im
JOIN medicamentos m ON im.GTIN    = m.GTIN
JOIN sedes s        ON im.id_sede = s.id_sede
WHERE im.stock_actual < im.stock_minimo
ORDER BY unidades_faltantes DESC;


-- 21. Suministros pendientes con días restantes para entrega
SELECT su.id_suministro,
       s.nombre_sede,
       fp.nombre        AS farmacia,
       su.fecha_entrega,
       su.estado,
       su.fecha_entrega - CURRENT_DATE AS dias_para_entrega
FROM suministros su
JOIN farmacias_proveedoras fp ON su.id_farmacia = fp.id_farmacia
JOIN sedes s                  ON su.id_sede     = s.id_sede
WHERE su.estado = 'Pendiente'
ORDER BY su.fecha_entrega ASC;


-- =============================================================================
-- SECCIÓN 7: OPERACIONES DIARIAS
-- =============================================================================

-- 22. Visitas del día con estado de salida
SELECT v.id_visita,
       s.nombre_sede,
       p.nombre  || ' ' || p.apellido_p  AS paciente,
       vt.nombre || ' ' || vt.apellido_p AS visitante,
       vt.relacion,
       v.hora_entrada,
       COALESCE(v.hora_salida::TEXT, 'En visita') AS hora_salida
FROM visitas v
JOIN pacientes p   ON v.id_paciente  = p.id_paciente
JOIN visitantes vt ON v.id_visitante = vt.id_visitante
JOIN sedes s       ON v.id_sede      = s.id_sede
WHERE v.fecha_entrada = CURRENT_DATE
ORDER BY s.nombre_sede, v.hora_entrada;


-- 23. Entregas externas pendientes de revisión
SELECT ee.id_entrega,
       p.nombre  || ' ' || p.apellido_p  AS paciente,
       vt.nombre || ' ' || vt.apellido_p AS remitente,
       ee.descripcion,
       ee.fecha_recepcion,
       ee.hora_recepcion,
       s.nombre_sede
FROM entregas_externas ee
JOIN pacientes p   ON ee.id_paciente  = p.id_paciente
JOIN visitantes vt ON ee.id_visitante = vt.id_visitante
JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                      AND sp.fecha_salida IS NULL
JOIN sedes s       ON sp.id_sede = s.id_sede
WHERE ee.estado = 'Pendiente'
ORDER BY ee.fecha_recepcion DESC, ee.hora_recepcion DESC;
