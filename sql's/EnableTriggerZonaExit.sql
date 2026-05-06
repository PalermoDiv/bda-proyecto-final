-- Poblar geom en zonas existentes que lo tengan NULL
UPDATE zonas
SET geom = ST_SetSRID(ST_MakePoint(longitud_centro, latitud_centro), 4326)::geography
WHERE geom IS NULL;

-- Habilitar trigger de salida de zona
ALTER TABLE lecturas_gps ENABLE TRIGGER trg_zona_exit_gps;

DO $$
BEGIN
    RAISE NOTICE 'trg_zona_exit_gps habilitado.';
END;
$$;
