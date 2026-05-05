-- =============================================================================
-- SelectProcedures.sql — SPs de consulta SELECT para AlzMonitor
-- Cada SP abre un REFCURSOR sobre su vista correspondiente en ViewsDB.sql.
-- ViewsDB.sql debe aplicarse antes que este archivo.
--
-- Patrón de uso desde Python (db.py):
--   with conn.cursor() as cur:
--       cur.execute("BEGIN")
--       cur.execute("CALL sp_sel_xxx(%s)", ('io_resultados',))
--       cur.execute("FETCH ALL FROM io_resultados")
--       rows = cur.fetchall()
--       cur.execute("COMMIT")
--
-- Aplicar: psql -U palermingoat -d alzheimer -f SelectProcedures.sql
-- =============================================================================


-- 1
CREATE OR REPLACE PROCEDURE sp_sel_pacientes_activos(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_pacientes_activos;
END;
$$;


-- 2
CREATE OR REPLACE PROCEDURE sp_sel_cuidadores(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_cuidadores;
END;
$$;


-- 3
CREATE OR REPLACE PROCEDURE sp_sel_dispositivos(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_dispositivos;
END;
$$;


-- 4
CREATE OR REPLACE PROCEDURE sp_sel_zonas(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_zonas;
END;
$$;


-- 5
CREATE OR REPLACE PROCEDURE sp_sel_alertas(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_alertas;
END;
$$;


-- 6
CREATE OR REPLACE PROCEDURE sp_sel_recetas(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_recetas;
END;
$$;


-- 7
CREATE OR REPLACE PROCEDURE sp_sel_turnos(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_turnos;
END;
$$;


-- 8
CREATE OR REPLACE PROCEDURE sp_sel_detecciones_beacon(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_detecciones_beacon;
END;
$$;


-- 9
CREATE OR REPLACE PROCEDURE sp_sel_kit_gps_activo(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_kit_gps_activo;
END;
$$;


-- 10
CREATE OR REPLACE PROCEDURE sp_sel_inventario_farmacia(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_inventario_farmacia;
END;
$$;


-- 11
CREATE OR REPLACE PROCEDURE sp_sel_suministros(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_suministros;
END;
$$;


-- 12
CREATE OR REPLACE PROCEDURE sp_sel_visitas(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_visitas;
END;
$$;


-- 13
CREATE OR REPLACE PROCEDURE sp_sel_entregas_externas(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_entregas_externas;
END;
$$;


-- 14
CREATE OR REPLACE PROCEDURE sp_sel_receta_medicamentos(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_receta_medicamentos;
END;
$$;


-- 15
CREATE OR REPLACE PROCEDURE sp_sel_nfc_activo(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_nfc_activo;
END;
$$;


-- 16
CREATE OR REPLACE PROCEDURE sp_sel_asignacion_beacon(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_asignacion_beacon;
END;
$$;


-- 17
CREATE OR REPLACE PROCEDURE sp_sel_cuidadores_asignados(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_cuidadores_asignados;
END;
$$;


-- 18
CREATE OR REPLACE PROCEDURE sp_sel_medicamentos_por_paciente(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_medicamentos_por_paciente;
END;
$$;


-- 19
CREATE OR REPLACE PROCEDURE sp_sel_contactos_emergencia(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_contactos_emergencia;
END;
$$;


-- 20
CREATE OR REPLACE PROCEDURE sp_sel_ultima_lectura_gps(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_ultima_lectura_gps;
END;
$$;


-- 21
CREATE OR REPLACE PROCEDURE sp_sel_enfermedades_paciente(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_enfermedades_paciente;
END;
$$;


-- 22
CREATE OR REPLACE PROCEDURE sp_sel_adherencia_nfc_30d(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_adherencia_nfc_30d;
END;
$$;


-- 23
CREATE OR REPLACE PROCEDURE sp_sel_pacientes_sin_gps(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_pacientes_sin_gps;
END;
$$;


-- 24
CREATE OR REPLACE PROCEDURE sp_sel_historial_sedes_paciente(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_historial_sedes_paciente;
END;
$$;


-- 25
CREATE OR REPLACE PROCEDURE sp_sel_alertas_activas(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_alertas_activas;
END;
$$;


-- 26
CREATE OR REPLACE PROCEDURE sp_sel_lecturas_gps_recientes(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_lecturas_gps_recientes;
END;
$$;


-- 27
CREATE OR REPLACE PROCEDURE sp_sel_cuidadores_sin_beacon(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_cuidadores_sin_beacon;
END;
$$;


-- 28
CREATE OR REPLACE PROCEDURE sp_sel_resumen_alertas_por_tipo(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_resumen_alertas_por_tipo;
END;
$$;


-- 29
CREATE OR REPLACE PROCEDURE sp_sel_visitas_recientes(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_visitas_recientes;
END;
$$;


-- 30
CREATE OR REPLACE PROCEDURE sp_sel_pacientes_transferidos(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_pacientes_transferidos;
END;
$$;


-- 31
CREATE OR REPLACE PROCEDURE sp_sel_stats_por_sede(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_stats_por_sede;
END;
$$;


-- 32
CREATE OR REPLACE PROCEDURE sp_sel_suministros_pendientes(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_suministros_pendientes;
END;
$$;


-- 33
CREATE OR REPLACE PROCEDURE sp_sel_medicamentos_criticos(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_medicamentos_criticos;
END;
$$;


-- 34
CREATE OR REPLACE PROCEDURE sp_sel_nfc_disponibles(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_nfc_disponibles;
END;
$$;


-- 35
CREATE OR REPLACE PROCEDURE sp_sel_gps_disponibles(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_gps_disponibles;
END;
$$;


-- 36
CREATE OR REPLACE PROCEDURE sp_sel_lineas_suministro(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_lineas_suministro;
END;
$$;


-- 37
CREATE OR REPLACE PROCEDURE sp_sel_lecturas_nfc_recientes(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_lecturas_nfc_recientes;
END;
$$;


-- 38
CREATE OR REPLACE PROCEDURE sp_sel_cuidadores_en_turno(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_cuidadores_en_turno;
END;
$$;


-- 39
CREATE OR REPLACE PROCEDURE sp_sel_bitacora_comedor(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_bitacora_comedor;
END;
$$;


-- 40 — filtrado por contacto
CREATE OR REPLACE PROCEDURE sp_sel_pacientes_por_contacto(
    IN  p_id_contacto INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_pacientes_por_contacto
        WHERE id_contacto = p_id_contacto;
END;
$$;


-- 41 — filtrado por paciente
CREATE OR REPLACE PROCEDURE sp_sel_zonas_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_zonas_por_paciente
        WHERE id_paciente = p_id_paciente;
END;
$$;


-- 42
CREATE OR REPLACE PROCEDURE sp_sel_alertas_criticas_activas(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_alertas_criticas_activas;
END;
$$;


-- 43
CREATE OR REPLACE PROCEDURE sp_sel_alertas_historial_30d(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_alertas_historial_30d;
END;
$$;


-- 44
CREATE OR REPLACE PROCEDURE sp_sel_medicamentos_adherencia_hoy(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_medicamentos_adherencia_hoy;
END;
$$;


-- 45
CREATE OR REPLACE PROCEDURE sp_sel_entregas_pendientes(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_entregas_pendientes;
END;
$$;


-- 46
CREATE OR REPLACE PROCEDURE sp_sel_visitas_hoy(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_visitas_hoy;
END;
$$;


-- 47
CREATE OR REPLACE PROCEDURE sp_sel_ultima_actividad_paciente(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_ultima_actividad_paciente;
END;
$$;


-- 48 — filtrado por sede
CREATE OR REPLACE PROCEDURE sp_sel_alertas_por_sede(
    IN  p_id_sede INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_alertas_por_sede
        WHERE id_sede = p_id_sede;
END;
$$;


-- 49
CREATE OR REPLACE PROCEDURE sp_sel_expediente_clinico(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_expediente_clinico;
END;
$$;


-- 50
CREATE OR REPLACE PROCEDURE sp_sel_alertas_por_dia_14d(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_alertas_por_dia_14d;
END;
$$;


-- 51
CREATE OR REPLACE PROCEDURE sp_sel_stock_farmacia_completo(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_stock_farmacia_completo;
END;
$$;


-- 52
CREATE OR REPLACE PROCEDURE sp_sel_adherencia_nfc_por_paciente(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_adherencia_nfc_por_paciente;
END;
$$;


-- 53 — filtrado por paciente
CREATE OR REPLACE PROCEDURE sp_sel_bateria_historial_gps(
    IN  p_id_paciente   INTEGER,
    IN  p_limite        INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT label, nivel_bateria
        FROM v_bateria_historial_gps
        WHERE id_paciente = p_id_paciente
        LIMIT p_limite;
END;
$$;


-- 54 — filtrado por paciente
CREATE OR REPLACE PROCEDURE sp_sel_lecturas_gps_paciente(
    IN  p_id_paciente   INTEGER,
    IN  p_limite        INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT fecha, hora, latitud, longitud, nivel_bateria, fecha_hora
        FROM v_lecturas_gps_paciente
        WHERE id_paciente = p_id_paciente
        LIMIT p_limite;
END;
$$;


-- =============================================================================
-- GRUPO A (55-63) — Catálogos
-- =============================================================================

-- 55
CREATE OR REPLACE PROCEDURE sp_sel_sedes(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_sedes;
END;
$$;

-- 56
CREATE OR REPLACE PROCEDURE sp_sel_estados_paciente(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_estados_paciente;
END;
$$;

-- 57
CREATE OR REPLACE PROCEDURE sp_sel_cat_tipo_alerta(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_cat_tipo_alerta;
END;
$$;

-- 58
CREATE OR REPLACE PROCEDURE sp_sel_cat_estado_suministro(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_cat_estado_suministro;
END;
$$;

-- 59
CREATE OR REPLACE PROCEDURE sp_sel_farmacias_proveedoras(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_farmacias_proveedoras;
END;
$$;

-- 60
CREATE OR REPLACE PROCEDURE sp_sel_medicamentos_catalogo(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_medicamentos_catalogo;
END;
$$;

-- 61
CREATE OR REPLACE PROCEDURE sp_sel_visitantes_lista(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_visitantes_lista;
END;
$$;

-- 62
CREATE OR REPLACE PROCEDURE sp_sel_zonas_lista(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_zonas_lista;
END;
$$;

-- 63
CREATE OR REPLACE PROCEDURE sp_sel_cuidadores_dropdown(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_cuidadores_dropdown;
END;
$$;


-- =============================================================================
-- GRUPO B (64-67) — Stats generales
-- =============================================================================

-- 64
CREATE OR REPLACE PROCEDURE sp_sel_dashboard_stats(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_dashboard_stats;
END;
$$;

-- 65
CREATE OR REPLACE PROCEDURE sp_sel_alertas_recientes(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_alertas_recientes;
END;
$$;

-- 66
CREATE OR REPLACE PROCEDURE sp_sel_alertas_banner(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_alertas_banner;
END;
$$;

-- 67
CREATE OR REPLACE PROCEDURE sp_sel_reportes_stats(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_reportes_stats;
END;
$$;


-- =============================================================================
-- GRUPO C (68-74) — Single-row lookups por ID
-- =============================================================================

-- 68 — filtrado por paciente
CREATE OR REPLACE PROCEDURE sp_sel_paciente_por_id(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_pacientes_todos
        WHERE id_paciente = p_id_paciente;
END;
$$;

-- 69 — filtrado por cuidador
CREATE OR REPLACE PROCEDURE sp_sel_cuidador_por_id(
    IN  p_id_cuidador INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_cuidadores
        WHERE id_cuidador = p_id_cuidador;
END;
$$;

-- 70 — filtrado por turno
CREATE OR REPLACE PROCEDURE sp_sel_turno_por_id(
    IN  p_id_turno INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_turnos
        WHERE id_turno = p_id_turno;
END;
$$;

-- 71 — filtrado por dispositivo
CREATE OR REPLACE PROCEDURE sp_sel_dispositivo_por_id(
    IN  p_id_dispositivo INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_dispositivos
        WHERE id_dispositivo = p_id_dispositivo;
END;
$$;

-- 72 — filtrado por zona
CREATE OR REPLACE PROCEDURE sp_sel_zona_por_id(
    IN  p_id_zona INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_zonas
        WHERE id_zona = p_id_zona;
END;
$$;

-- 73 — filtrado por suministro
CREATE OR REPLACE PROCEDURE sp_sel_suministro_por_id(
    IN  p_id_suministro INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_suministro_detalle
        WHERE id_suministro = p_id_suministro;
END;
$$;

-- 74 — filtrado por sede
CREATE OR REPLACE PROCEDURE sp_sel_sede_por_id(
    IN  p_id_sede INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_sedes
        WHERE id_sede = p_id_sede;
END;
$$;


-- =============================================================================
-- GRUPO D (75-85) — Historial de paciente
-- =============================================================================

-- 75 — enfermedades de un paciente
CREATE OR REPLACE PROCEDURE sp_sel_enfermedades_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_enfermedades_paciente
        WHERE id_paciente = p_id_paciente;
END;
$$;

-- 76 — cuidadores asignados a un paciente
CREATE OR REPLACE PROCEDURE sp_sel_cuidadores_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_cuidadores_asignados
        WHERE id_paciente = p_id_paciente;
END;
$$;

-- 77 — contactos de emergencia de un paciente
CREATE OR REPLACE PROCEDURE sp_sel_contactos_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_contactos_emergencia
        WHERE id_paciente = p_id_paciente;
END;
$$;

-- 78 — kit GPS activo de un paciente
CREATE OR REPLACE PROCEDURE sp_sel_kit_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_kit_gps_activo
        WHERE id_paciente = p_id_paciente;
END;
$$;

-- 79 — historial de sedes de un paciente
CREATE OR REPLACE PROCEDURE sp_sel_historial_sedes_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_historial_sedes_paciente
        WHERE id_paciente = p_id_paciente;
END;
$$;

-- 80 — alertas de un paciente
CREATE OR REPLACE PROCEDURE sp_sel_alertas_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_alertas
        WHERE id_paciente = p_id_paciente
        ORDER BY fecha_hora DESC;
END;
$$;

-- 81 — visitas de un paciente
CREATE OR REPLACE PROCEDURE sp_sel_visitas_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_visitas_historial
        WHERE id_paciente = p_id_paciente
        ORDER BY fecha_entrada DESC;
END;
$$;

-- 82 — NFC asignado a un paciente
CREATE OR REPLACE PROCEDURE sp_sel_nfc_asignacion_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_nfc_asignacion_paciente
        WHERE id_paciente = p_id_paciente;
END;
$$;

-- 83 — enfermedades disponibles para agregar a un paciente
CREATE OR REPLACE PROCEDURE sp_sel_enfermedades_disponibles(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_enfermedades_catalogo
        WHERE id_enfermedad NOT IN (
            SELECT id_enfermedad FROM tiene_enfermedad
            WHERE id_paciente = p_id_paciente
        );
END;
$$;

-- 84 — sede activa de un paciente
CREATE OR REPLACE PROCEDURE sp_sel_sede_activa_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_sede_activa_paciente
        WHERE id_paciente = p_id_paciente;
END;
$$;

-- 85 — lecturas GPS recientes de un paciente (todas las columnas incl. fecha_hora para ts)
CREATE OR REPLACE PROCEDURE sp_sel_gps_por_paciente(
    IN  p_id_paciente INTEGER,
    IN  p_limite      INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT *
        FROM v_lecturas_gps_paciente
        WHERE id_paciente = p_id_paciente
        LIMIT p_limite;
END;
$$;


-- =============================================================================
-- GRUPO E (86-91) — Detalle de receta
-- =============================================================================

-- 86 — receta por ID
CREATE OR REPLACE PROCEDURE sp_sel_receta_por_id(
    IN  p_id_receta INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_receta_detalle
        WHERE id_receta = p_id_receta;
END;
$$;

-- 87 — medicamentos de una receta
CREATE OR REPLACE PROCEDURE sp_sel_receta_medicamentos_por_receta(
    IN  p_id_receta INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_receta_medicamentos
        WHERE id_receta = p_id_receta;
END;
$$;

-- 88 — NFC activo de una receta
CREATE OR REPLACE PROCEDURE sp_sel_nfc_activo_por_receta(
    IN  p_id_receta INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_nfc_activo
        WHERE id_receta = p_id_receta;
END;
$$;

-- 89 — lecturas NFC de una receta
CREATE OR REPLACE PROCEDURE sp_sel_lecturas_nfc_por_receta(
    IN  p_id_receta INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_lecturas_nfc_receta
        WHERE id_receta = p_id_receta
        ORDER BY fecha_hora DESC
        LIMIT 20;
END;
$$;

-- 90 — medicamentos disponibles para agregar a una receta
CREATE OR REPLACE PROCEDURE sp_sel_medicamentos_disponibles_receta(
    IN  p_id_receta INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_medicamentos_catalogo
        WHERE gtin NOT IN (
            SELECT gtin FROM receta_medicamentos
            WHERE id_receta = p_id_receta
        );
END;
$$;

-- 91 — recetas de un paciente
CREATE OR REPLACE PROCEDURE sp_sel_recetas_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_recetas
        WHERE id_paciente = p_id_paciente
        ORDER BY fecha_inicio DESC;
END;
$$;


-- =============================================================================
-- GRUPO F (92-93) — Visitas admin
-- =============================================================================

-- 92 — historial completo de visitas
CREATE OR REPLACE PROCEDURE sp_sel_visitas_historial(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_visitas_historial ORDER BY fecha_entrada DESC;
END;
$$;

-- 93 — visitantes registrados
CREATE OR REPLACE PROCEDURE sp_sel_visitantes(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_visitantes_lista;
END;
$$;


-- =============================================================================
-- GRUPO G (94-96) — Rondas / Beacon
-- =============================================================================

-- 94 — rondas recientes (log de detecciones beacon)
CREATE OR REPLACE PROCEDURE sp_sel_rondas_recientes(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_rondas_recientes;
END;
$$;

-- 95 — todas las asignaciones beacon (incluyendo históricas)
CREATE OR REPLACE PROCEDURE sp_sel_asignacion_beacon_todas(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_asignacion_beacon_todas;
END;
$$;

-- 96 — beacons disponibles para nueva asignación
CREATE OR REPLACE PROCEDURE sp_sel_beacons_disponibles_asig(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_beacons_disponibles_asig;
END;
$$;


-- =============================================================================
-- GRUPO H (97-112) — Clínica dashboard (parametrizados por id_sede)
-- =============================================================================

-- 97
CREATE OR REPLACE PROCEDURE sp_sel_clinica_pacientes(
    IN  p_id_sede INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_clinica_pacientes
        WHERE id_sede = p_id_sede;
END;
$$;

-- 98
CREATE OR REPLACE PROCEDURE sp_sel_clinica_asignaciones(
    IN  p_id_sede INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_clinica_asignaciones
        WHERE id_sede = p_id_sede;
END;
$$;

-- 99
CREATE OR REPLACE PROCEDURE sp_sel_clinica_meds(
    IN  p_id_sede INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_clinica_meds
        WHERE id_sede = p_id_sede;
END;
$$;

-- 100
CREATE OR REPLACE PROCEDURE sp_sel_clinica_enfermedades(
    IN  p_id_sede INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_clinica_enfermedades
        WHERE id_sede = p_id_sede;
END;
$$;

-- 101
CREATE OR REPLACE PROCEDURE sp_sel_clinica_alertas_activas(
    IN  p_id_sede INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_clinica_alertas_activas
        WHERE id_sede = p_id_sede;
END;
$$;

-- 102
CREATE OR REPLACE PROCEDURE sp_sel_clinica_comedor_hoy(
    IN  p_id_sede INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_clinica_comedor_hoy
        WHERE id_sede = p_id_sede;
END;
$$;

-- 103
CREATE OR REPLACE PROCEDURE sp_sel_clinica_gps_estado(
    IN  p_id_sede INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_clinica_gps_estado
        WHERE id_sede = p_id_sede;
END;
$$;

-- 104
CREATE OR REPLACE PROCEDURE sp_sel_clinica_zonas_mapa(
    IN  p_id_sede INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_clinica_zonas_mapa
        WHERE id_sede = p_id_sede;
END;
$$;

-- 105
CREATE OR REPLACE PROCEDURE sp_sel_clinica_alertas_salida_zona(
    IN  p_id_sede INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_clinica_alertas_salida_zona
        WHERE id_sede = p_id_sede;
END;
$$;

-- 106
CREATE OR REPLACE PROCEDURE sp_sel_clinica_meds_nfc_hoy(
    IN  p_id_sede INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_clinica_meds_nfc_hoy
        WHERE id_sede = p_id_sede;
END;
$$;

-- 107
CREATE OR REPLACE PROCEDURE sp_sel_clinica_nfc_hoy(
    IN  p_id_sede INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_clinica_nfc_hoy
        WHERE id_sede = p_id_sede;
END;
$$;

-- 108
CREATE OR REPLACE PROCEDURE sp_sel_staff_en_turno(
    IN  p_id_sede INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_staff_en_turno
        WHERE id_sede = p_id_sede;
END;
$$;


-- =============================================================================
-- GRUPO I (109-118) — Portal familiar (parametrizados por id_paciente / id_contacto)
-- =============================================================================

-- 109 — login de contacto por email
CREATE OR REPLACE PROCEDURE sp_sel_contacto_login(
    IN  p_email VARCHAR,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_contacto_login
        WHERE email = LOWER(p_email);
END;
$$;

-- 110 — alerta crítica activa de un paciente (portal banner)
CREATE OR REPLACE PROCEDURE sp_sel_alerta_critica_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_alerta_critica_por_paciente
        WHERE id_paciente = p_id_paciente
        LIMIT 1;
END;
$$;

-- 111 — última actividad GPS/NFC de un paciente
CREATE OR REPLACE PROCEDURE sp_sel_ultima_actividad_ts(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_ultima_actividad_ts
        WHERE id_paciente = p_id_paciente;
END;
$$;

-- 112 — última ronda de un paciente
CREATE OR REPLACE PROCEDURE sp_sel_ultima_ronda_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_ultima_ronda_por_paciente
        WHERE id_paciente = p_id_paciente;
END;
$$;

-- 113 — dosis NFC de hoy de un paciente (portal)
CREATE OR REPLACE PROCEDURE sp_sel_dosis_nfc_hoy(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_dosis_nfc_hoy
        WHERE id_paciente = p_id_paciente;
END;
$$;

-- 114 — visitas recientes para el portal familiar
CREATE OR REPLACE PROCEDURE sp_sel_visitas_portal(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_visitas_portal
        WHERE id_paciente = p_id_paciente;
END;
$$;

-- 115 — verificación de acceso contacto-paciente
CREATE OR REPLACE PROCEDURE sp_sel_contacto_verificacion(
    IN  p_id_contacto INTEGER,
    IN  p_id_paciente  INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_contacto_verificacion
        WHERE id_contacto = p_id_contacto
          AND id_paciente  = p_id_paciente;
END;
$$;

-- 116 — alertas activas de un paciente (portal)
CREATE OR REPLACE PROCEDURE sp_sel_alertas_activas_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_alertas_activas_paciente
        WHERE id_paciente = p_id_paciente;
END;
$$;

-- 117 — historial de alertas (30d) de un paciente
CREATE OR REPLACE PROCEDURE sp_sel_alertas_historial_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_alertas_historial_30d
        WHERE id_paciente = p_id_paciente
        ORDER BY fecha DESC, hora DESC;
END;
$$;

-- 118 — adherencia NFC de medicamentos de un paciente (30d)
CREATE OR REPLACE PROCEDURE sp_sel_medicamentos_adherencia_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_adherencia_nfc_por_paciente
        WHERE id_paciente = p_id_paciente;
END;
$$;


-- =============================================================================
-- GRUPO J (119-122) — GPS simulador
-- =============================================================================

-- 119
CREATE OR REPLACE PROCEDURE sp_sel_dispositivos_gps_activos(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_dispositivos_gps_activos;
END;
$$;

-- 120
CREATE OR REPLACE PROCEDURE sp_sel_zonas_ref(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_zonas_ref;
END;
$$;

-- 121
CREATE OR REPLACE PROCEDURE sp_sel_alertas_sim_recientes(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_alertas_sim_recientes;
END;
$$;

-- 122
CREATE OR REPLACE PROCEDURE sp_sel_last_id_lectura_gps(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_last_id_lectura_gps;
END;
$$;


-- =============================================================================
-- GRUPO K (123-127) — API / IoT lookups
-- =============================================================================

-- 123 — dispositivo por serial (OsmAnd / API GPS)
CREATE OR REPLACE PROCEDURE sp_sel_dispositivo_serial(
    IN  p_serial VARCHAR,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_dispositivo_serial
        WHERE id_serial = p_serial;
END;
$$;

-- 124 — receta NFC activa por dispositivo
CREATE OR REPLACE PROCEDURE sp_sel_receta_nfc_activa(
    IN  p_id_dispositivo INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_receta_nfc_activa
        WHERE id_dispositivo = p_id_dispositivo;
END;
$$;

-- 125 — cuidador asignado a un beacon
CREATE OR REPLACE PROCEDURE sp_sel_asignacion_beacon_cuidador(
    IN  p_id_dispositivo INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_asignacion_beacon_cuidador
        WHERE id_dispositivo = p_id_dispositivo;
END;
$$;

-- 126 — última detección de un beacon
CREATE OR REPLACE PROCEDURE sp_sel_ultima_deteccion_por_beacon(
    IN  p_id_dispositivo INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_ultima_deteccion_por_beacon
        WHERE id_dispositivo = p_id_dispositivo;
END;
$$;

-- 127 — paciente por NFC serial (wristband tap)
CREATE OR REPLACE PROCEDURE sp_sel_paciente_por_nfc(
    IN  p_serial VARCHAR,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_paciente_por_nfc
        WHERE id_serial = p_serial;
END;
$$;


-- =============================================================================
-- GRUPO L (128-130) — Next IDs
-- =============================================================================

-- 128
CREATE OR REPLACE PROCEDURE sp_sel_next_id_receta(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_next_id_receta;
END;
$$;

-- 129
CREATE OR REPLACE PROCEDURE sp_sel_next_id_detalle_receta(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_next_id_detalle_receta;
END;
$$;

-- 130
CREATE OR REPLACE PROCEDURE sp_sel_next_id_lectura_nfc(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR SELECT * FROM v_next_id_lectura_nfc;
END;
$$;


-- =============================================================================
-- GRUPO M (131-135) — SPs adicionales para migración completa de app.py
-- =============================================================================

-- 131 — entregas externas de un paciente (historial)
CREATE OR REPLACE PROCEDURE sp_sel_entregas_por_paciente(
    IN  p_id_paciente INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT *
        FROM v_entregas_externas
        WHERE id_paciente = p_id_paciente
        ORDER BY fecha DESC
        LIMIT 30;
END;
$$;

-- 132 — dispositivo por serial y tipo (APIs IoT — case-insensitive)
CREATE OR REPLACE PROCEDURE sp_sel_dispositivo_por_serial_tipo(
    IN  p_serial VARCHAR,
    IN  p_tipo   VARCHAR,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT *
        FROM v_dispositivo_serial
        WHERE LOWER(id_serial) = LOWER(p_serial)
          AND tipo = p_tipo;
END;
$$;

-- 133 — líneas de una orden de suministro (detalle farmacia)
CREATE OR REPLACE PROCEDURE sp_sel_lineas_suministro_por_id(
    IN  p_id_suministro INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT gtin AS "GTIN", cantidad_pedida AS cantidad,
               nombre_medicamento, stock_actual, stock_minimo
        FROM v_lineas_suministro
        WHERE id_suministro = p_id_suministro
        ORDER BY nombre_medicamento;
END;
$$;

-- 134 — dispositivo por id (raw columns para formulario edición)
CREATE OR REPLACE PROCEDURE sp_sel_dispositivo_raw(
    IN  p_id_dispositivo INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT id_dispositivo, id_serial, tipo, modelo, estado
        FROM dispositivos
        WHERE id_dispositivo = p_id_dispositivo;
END;
$$;

-- 135 — incidentes (alertas) de una sede (portal clínico, últimos 20)
CREATE OR REPLACE PROCEDURE sp_sel_clinica_incidentes(
    IN  p_id_sede INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT *
        FROM v_clinica_incidentes
        WHERE id_sede = p_id_sede
        ORDER BY fecha DESC, hora DESC
        LIMIT 20;
END;
$$;


-- 136 — cobertura de zonas activa ahora mismo en una sede (sin f-string DOW)
CREATE OR REPLACE PROCEDURE sp_sel_clinica_cobertura_zonas(
    IN  p_id_sede INTEGER,
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT * FROM v_clinica_cobertura_zonas
        WHERE id_sede = p_id_sede;
END;
$$;


-- 137 — next ID for empleados (used when creating cuidadores)
CREATE OR REPLACE PROCEDURE sp_sel_next_id_empleado(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT COALESCE(MAX(id_empleado), 0) + 1 AS next_id FROM empleados;
END;
$$;

-- 138 — next ID for suministros
CREATE OR REPLACE PROCEDURE sp_sel_next_id_suministro(
    INOUT io_resultados REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN io_resultados FOR
        SELECT COALESCE(MAX(id_suministro), 0) + 1 AS next_id FROM suministros;
END;
$$;

-- =============================================================================
-- Confirmación
-- =============================================================================
DO $$
BEGIN
    RAISE NOTICE '138 SPs de consulta SELECT aplicados correctamente.';
    RAISE NOTICE 'Requiere ViewsDB.sql aplicado previamente.';
END;
$$;
