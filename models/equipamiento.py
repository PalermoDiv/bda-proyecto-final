from datetime import datetime, timezone, timedelta
import db
import mongo


def asignaciones_beacon():
    return db.query_sp("sp_sel_asignacion_beacon_todas")


def asignacion_por_beacon(id_beacon):
    return db.one_sp("sp_sel_asignacion_beacon_cuidador", (id_beacon,))


def ultima_deteccion_beacon(id_beacon):
    return db.one_sp("sp_sel_ultima_deteccion_por_beacon", (id_beacon,))


def asignar_beacon(id_dispositivo, id_cuidador):
    db.execute("CALL sp_ins_asignacion_beacon(%s, %s)", (id_dispositivo, id_cuidador))


def cerrar_asignacion_beacon(id):
    db.execute("CALL sp_upd_cerrar_asignacion_beacon(%s)", (id,))


def rondas(limit=50):
    docs = mongo.col("detecciones_beacon").find(
        {}, {"_id": 0}, sort=[("fecha_hora", -1)], limit=limit
    )
    return [
        {
            "id_deteccion":    d.get("id_deteccion"),
            "fecha_hora":      d.get("fecha_hora"),
            "id_gateway":      d.get("id_gateway"),
            "serial_beacon":   d.get("serial_beacon", "—"),
            "nombre_cuidador": d.get("nombre_cuidador", "Anónimo"),
            "rssi":            d.get("rssi"),
        }
        for d in docs
    ]


def rondas_chart(days=7):
    try:
        since = datetime.now(timezone.utc) - timedelta(days=days)
        pipeline = [
            {"$match": {"fecha_hora": {"$gte": since}}},
            {"$group": {"_id": "$nombre_cuidador", "total": {"$sum": 1}}},
            {"$sort": {"total": -1}},
        ]
        return [
            {"nombre": r["_id"] or "Anónimo", "total": r["total"]}
            for r in mongo.col("detecciones_beacon").aggregate(pipeline)
        ]
    except Exception:
        return []
