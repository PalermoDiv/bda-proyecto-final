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


-- =============================================================================
-- Confirmación
-- =============================================================================
DO $$
BEGIN
    RAISE NOTICE '49 SPs de consulta SELECT aplicados correctamente.';
    RAISE NOTICE 'Requiere ViewsDB.sql aplicado previamente.';
END;
$$;
