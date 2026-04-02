-- =====================================================
-- DISEÑO DE QUERIES — AlzMonitor
-- Sistema de Monitoreo de Pacientes con Alzheimer
-- =====================================================


-- 1. Pacientes con alertas activas
SELECT p.id_paciente,
       p.nombre, p.apellido_p,
       a.tipo_alerta, a.fecha_hora
FROM pacientes p
JOIN alertas a ON p.id_paciente = a.id_paciente
WHERE a.estatus = 'Activa';


-- 2. Pacientes con múltiples alertas activas
SELECT p.id_paciente,
       p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo,
       STRING_AGG(a.tipo_alerta, ', ') AS tipos_alerta,
       COUNT(a.id_alerta) AS total_alertas_activas
FROM pacientes p
JOIN alertas a ON p.id_paciente = a.id_paciente
WHERE a.estatus = 'Activa'
GROUP BY p.id_paciente, p.nombre, p.apellido_p, p.apellido_m
HAVING COUNT(a.id_alerta) > 1;


-- 3. Ubicación más reciente de cada paciente
SELECT p.id_paciente,
       p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo,
       lg.latitud, lg.longitud, lg.fecha_hora
FROM pacientes p
JOIN asignacion_kit ak ON p.id_paciente = ak.id_paciente
JOIN lecturas_gps lg ON ak.id_dispositivo_gps = lg.id_dispositivo
WHERE lg.fecha_hora = (
    SELECT MAX(lg2.fecha_hora)
    FROM lecturas_gps lg2
    WHERE lg2.id_dispositivo = lg.id_dispositivo
);


-- 4. Frecuencia de tipos de alerta
SELECT tipo_alerta, COUNT(*) AS total_alertas
FROM alertas
GROUP BY tipo_alerta;


-- 5. Ranking de pacientes por salidas de zona
SELECT p.id_paciente,
       p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo,
       COUNT(a.id_alerta) AS total_salidas_zona
FROM pacientes p
JOIN alertas a ON p.id_paciente = a.id_paciente
WHERE a.tipo_alerta = 'Salida de Zona'
GROUP BY p.id_paciente, p.nombre, p.apellido_p, p.apellido_m
ORDER BY total_salidas_zona ASC;


-- 6. Pacientes con Alzheimer
SELECT p.id_paciente,
       p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo,
       e.nombre_enfermedad
FROM pacientes p
JOIN tiene_enfermedad te ON p.id_paciente = te.id_paciente
JOIN enfermedades e ON te.id_enfermedad = e.id_enfermedad
WHERE e.nombre_enfermedad = 'Alzheimer';


-- 7. Relación paciente-cuidador
SELECT p.id_paciente,
       p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_paciente,
       e.id_empleado AS id_cuidador,
       e.nombre || ' ' || e.apellido_p || ' ' || e.apellido_m AS nombre_cuidador
FROM pacientes p
JOIN asignacion_cuidador ac ON p.id_paciente = ac.id_paciente
JOIN cuidadores c ON ac.id_cuidador = c.id_empleado
JOIN empleados e ON c.id_empleado = e.id_empleado;


-- 8. Trayectoria histórica de un paciente
SELECT lg.latitud, lg.longitud, lg.fecha_hora
FROM lecturas_gps lg
JOIN asignacion_kit ak ON lg.id_dispositivo = ak.id_dispositivo_gps
WHERE ak.id_paciente = 1
ORDER BY lg.fecha_hora;


-- 9. Pacientes fuera de zona
SELECT p.id_paciente,
       p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo,
       a.tipo_alerta, a.fecha_hora
FROM pacientes p
JOIN alertas a ON p.id_paciente = a.id_paciente
WHERE a.tipo_alerta = 'Salida de Zona'
  AND a.estatus = 'Activa';


-- 10. Distancia del paciente respecto a su zona segura
SELECT p.id_paciente,
       p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo,
       z.nombre_zona, lg.latitud, lg.longitud, z.radio_metros,
       (
           6371000 * acos(
               cos(radians(z.latitud_centro)) * cos(radians(lg.latitud)) *
               cos(radians(lg.longitud) - radians(z.longitud_centro)) +
               sin(radians(z.latitud_centro)) * sin(radians(lg.latitud))
           )
       ) - z.radio_metros AS exceso_metros
FROM pacientes p
JOIN asignacion_kit ak ON p.id_paciente = ak.id_paciente
JOIN lecturas_gps lg ON ak.id_dispositivo_gps = lg.id_dispositivo
JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente AND sp.fecha_salida IS NULL
JOIN sede_zonas sz ON sp.id_sede = sz.id_sede
JOIN zonas z ON sz.id_zona = z.id_zona
WHERE lg.fecha_hora = (
    SELECT MAX(lg2.fecha_hora)
    FROM lecturas_gps lg2
    WHERE lg2.id_dispositivo = lg.id_dispositivo
)
AND (
    6371000 * acos(
        cos(radians(z.latitud_centro)) * cos(radians(lg.latitud)) *
        cos(radians(lg.longitud) - radians(z.longitud_centro)) +
        sin(radians(z.latitud_centro)) * sin(radians(lg.latitud))
    )
) > z.radio_metros;


-- 11. Adherencia terapéutica por paciente (NFC)
SELECT
    p.id_paciente,
    p.nombre || ' ' || p.apellido_p AS nombre_paciente,
    m.nombre_medicamento,
    rm.dosis,
    rm.frecuencia_horas,
    COUNT(db.id_deteccion) AS lecturas_nfc_mes
FROM pacientes p
JOIN paciente_recetas pr ON pr.id_paciente = p.id_paciente
JOIN recetas r ON r.id_receta = pr.id_receta
JOIN receta_medicamentos rm ON rm.id_receta = r.id_receta
JOIN medicamentos m ON m.GTIN = rm.GTIN
JOIN receta_nfc rn ON rn.id_receta = r.id_receta
LEFT JOIN detecciones_beacon db
    ON db.id_dispositivo = rn.id_dispositivo
    AND db.fecha_hora >= CURRENT_DATE - INTERVAL '30 days'
WHERE pr.fecha_fin_prescripcion IS NULL
   OR pr.fecha_fin_prescripcion >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY p.id_paciente, p.nombre, p.apellido_p,
         m.nombre_medicamento, rm.dosis, rm.frecuencia_horas
HAVING COUNT(db.id_deteccion) < 20
ORDER BY lecturas_nfc_mes ASC;


-- 12. Dispositivos NFC activos por sede con total de usos
SELECT
    s.nombre_sede,
    d.id_serial AS serial_nfc,
    d.modelo,
    d.estado,
    p.nombre || ' ' || p.apellido_p AS paciente_asignado,
    (
        SELECT COUNT(*)
        FROM detecciones_beacon db
        WHERE db.id_dispositivo = d.id_dispositivo
    ) AS total_usos
FROM dispositivos d
JOIN receta_nfc rn ON rn.id_dispositivo = d.id_dispositivo
JOIN recetas r ON r.id_receta = rn.id_receta
JOIN paciente_recetas pr ON pr.id_receta = r.id_receta
JOIN pacientes p ON p.id_paciente = pr.id_paciente
JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente
    AND sp.fecha_salida IS NULL
JOIN sedes s ON s.id_sede = sp.id_sede
WHERE d.tipo = 'NFC'
ORDER BY s.nombre_sede ASC, total_usos DESC;
