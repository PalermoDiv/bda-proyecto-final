from datetime import datetime, timezone
import db
import mongo
from flask import current_app


def registrar_gps(id_dispositivo, latitud, longitud, nivel_bateria, altura):
    db.execute("CALL sp_ins_lectura_gps(%s, %s, %s, %s, %s)",
               (id_dispositivo, latitud, longitud, nivel_bateria, altura))
    id_lectura = db.one_sp("sp_sel_last_id_lectura_gps")["id_lectura"]
    try:
        mongo.col("lecturas_gps").insert_one({
            "id_lectura":     id_lectura,
            "id_dispositivo": id_dispositivo,
            "latitud":        latitud,
            "longitud":       longitud,
            "nivel_bateria":  nivel_bateria,
            "altura":         altura,
            "fecha_hora":     datetime.now(timezone.utc),
        })
    except Exception as me:
        current_app.logger.warning("MongoDB GPS write failed: %s", me)
    return id_lectura


def ultima_lectura_gps(id_paciente, limit=1):
    return db.one_sp("sp_sel_lecturas_gps_paciente", (id_paciente, limit))


def lecturas_gps_paciente(id_paciente, limit=50):
    return db.query_sp("sp_sel_lecturas_gps_paciente", (id_paciente, limit))


def alertas_sim_recientes():
    return db.query_sp("sp_sel_alertas_sim_recientes")


def siguiente_id_nfc():
    return db.one_sp("sp_sel_next_id_lectura_nfc")["next_id"]


def registrar_nfc(next_id, id_dispositivo, id_receta, tipo_lectura, resultado):
    db.execute(
        "CALL sp_nfc_registrar_lectura(%s::integer, %s::integer, %s::integer, NOW(), %s, %s)",
        (next_id, id_dispositivo, id_receta, tipo_lectura, resultado),
    )
    try:
        mongo.col("lecturas_nfc").insert_one({
            "id_lectura_nfc": next_id,
            "id_dispositivo": id_dispositivo,
            "id_receta":      id_receta,
            "tipo_lectura":   tipo_lectura,
            "resultado":      resultado,
            "fecha_hora":     datetime.now(timezone.utc),
        })
    except Exception as me:
        current_app.logger.warning("MongoDB NFC write failed: %s", me)


def registrar_beacon(id_beacon, id_cuidador, rssi, gateway_id):
    db.execute("CALL sp_ins_deteccion_beacon(%s, %s, %s, %s)",
               (id_beacon, id_cuidador, rssi, gateway_id))
    row = db.one_sp("sp_sel_ultima_deteccion_por_beacon", (id_beacon,))
    id_deteccion = row["id_deteccion"] if row else None
    return id_deteccion
