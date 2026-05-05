-- =============================================================================
-- DisableTriggers.sql — Deshabilita todos los triggers automáticos de AlzMonitor
-- Los triggers quedan definidos en la DB pero no se ejecutan.
-- Para re-habilitar: ALTER TABLE ... ENABLE TRIGGER ...
-- Para aplicar: psql -U palermingoat -d alzheimer -f DisableTriggers.sql
-- =============================================================================

-- trg_cobertura_zona usa beacon_zona (arquitectura antigua de paredes fijas),
-- incompatible con el nuevo esquema donde el cuidador lleva el beacon.
ALTER TABLE detecciones_beacon DISABLE TRIGGER trg_cobertura_zona;

-- Triggers GPS deshabilitados temporalmente mientras se valida el flujo OsmAnd.
ALTER TABLE lecturas_gps DISABLE TRIGGER trg_bateria_baja_gps;
ALTER TABLE lecturas_gps DISABLE TRIGGER trg_zona_exit_gps;

DO $$
BEGIN
    RAISE NOTICE '✓ trg_cobertura_zona   — DESHABILITADO';
    RAISE NOTICE '✓ trg_bateria_baja_gps — DESHABILITADO';
    RAISE NOTICE '✓ trg_zona_exit_gps    — DESHABILITADO';
    RAISE NOTICE 'Para re-habilitar: psql -f TriggersDB.sql && psql -c "ALTER TABLE ... ENABLE TRIGGER ..."';
END;
$$;
