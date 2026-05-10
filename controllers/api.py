from flask import Blueprint, request, jsonify, render_template, flash, redirect, url_for
from datetime import datetime, timezone
import models.iot as IoT
import models.dispositivo as Dispositivo
import models.receta as Receta
import models.paciente as Paciente
import models.zona as Zona
import models.equipamiento as Equipamiento
import models.alerta as Alerta
import mongo
from auth import admin_requerido, iot_auth
from utils import haversine_m

bp = Blueprint("api", __name__)


# ── NFC ───────────────────────────────────────────────────────────────────────

@bp.route("/api/nfc/lectura", methods=["POST"])
def api_nfc_lectura():
    if not iot_auth():
        return jsonify({"status": "error", "message": "No autorizado"}), 401

    data         = request.get_json(silent=True) or {}
    tipo_lectura = data.get("tipo_lectura", "Administración")
    resultado    = data.get("resultado", "Exitosa")

    id_dispositivo = data.get("id_dispositivo")
    id_receta      = data.get("id_receta")

    if not id_dispositivo and data.get("serial"):
        device = Dispositivo.por_serial_tipo(data["serial"], "NFC")
        if not device:
            return jsonify({"status": "error",
                            "error": f"Serial '{data['serial']}' no registrado"}), 404
        id_dispositivo = device["id_dispositivo"]

    if not id_dispositivo:
        return jsonify({"status": "error", "message": "Falta id_dispositivo o serial"}), 400

    if not id_receta:
        link = Receta.nfc_activa_por_dispositivo(id_dispositivo)
        if not link:
            return jsonify({"status": "error",
                            "error": "No hay receta activa vinculada a este dispositivo NFC"}), 404
        id_receta = link["id_receta"]

    try:
        next_id = IoT.siguiente_id_nfc()
        IoT.registrar_nfc(next_id, id_dispositivo, id_receta, tipo_lectura, resultado)
        return jsonify({"status": "ok", "ok": True,
                        "id_lectura_nfc": next_id, "id_receta": id_receta})
    except Exception as e:
        return jsonify({"status": "error", "error": str(e)}), 422


# ── Beacon ────────────────────────────────────────────────────────────────────

@bp.route("/api/beacon/deteccion", methods=["POST"])
def api_beacon_deteccion():
    data       = request.get_json(silent=True) or {}
    rssi       = data.get("rssi", 0)
    gateway_id = data.get("gateway_id", "central")
    id_beacon  = data.get("id_beacon")
    serial     = data.get("serial")

    if not id_beacon and serial:
        row = Dispositivo.por_serial_tipo(serial, "BEACON")
        if row:
            id_beacon = row["id_dispositivo"]

    if not id_beacon and data.get("uuid") and data.get("major") is not None and data.get("minor") is not None:
        uuid_prefix = str(data["uuid"]).upper()[:8]
        composite   = f"{uuid_prefix}-{data['major']}-{data['minor']}"
        row = Dispositivo.por_serial_tipo(composite, "BEACON")
        if row:
            id_beacon = row["id_dispositivo"]

    if not id_beacon:
        return jsonify({"status": "error", "message": "Beacon no identificado"}), 400

    beacon_dev    = Dispositivo.obtener(id_beacon)
    serial_beacon = beacon_dev["id_serial"] if beacon_dev else f"device-{id_beacon}"

    cuidador       = Equipamiento.asignacion_por_beacon(id_beacon)
    id_cuidador    = cuidador["id_cuidador"] if cuidador else None
    caregiver_name = cuidador["nombre"]      if cuidador else "Sin asignar"

    try:
        id_deteccion = IoT.registrar_beacon(id_beacon, id_cuidador, rssi, gateway_id)
        try:
            mongo.col("detecciones_beacon").insert_one({
                "id_deteccion":    id_deteccion,
                "id_beacon":       id_beacon,
                "serial_beacon":   serial_beacon,
                "id_cuidador":     id_cuidador,
                "nombre_cuidador": caregiver_name,
                "rssi":            rssi,
                "id_gateway":      gateway_id,
                "fecha_hora":      datetime.now(timezone.utc),
            })
        except Exception as me:
            from flask import current_app
            current_app.logger.warning("MongoDB beacon write failed: %s", me)
        return jsonify({
            "status":        "ok",
            "ok":            True,
            "id_deteccion":  id_deteccion,
            "caregiver_name": caregiver_name,
        })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 422


# ── GPS ───────────────────────────────────────────────────────────────────────

@bp.route("/sim/gps", methods=["GET", "POST"])
@admin_requerido
def sim_gps():
    dispositivos_gps = Dispositivo.gps_activos()
    result = None
    if request.method == "POST":
        try:
            id_dispositivo = int(request.form["id_dispositivo"])
            latitud        = float(request.form["latitud"])
            longitud       = float(request.form["longitud"])
            nivel_bateria  = int(request.form.get("nivel_bateria") or 80)
            id_lectura     = IoT.registrar_gps(id_dispositivo, latitud, longitud,
                                               nivel_bateria, None)
            nuevas_alertas = Alerta.sim_recientes()
            result = {
                "id_lectura":        id_lectura,
                "latitud":           latitud,
                "longitud":          longitud,
                "nivel_bateria":     nivel_bateria,
                "alertas_generadas": nuevas_alertas,
            }
            flash(f"Lectura GPS #{id_lectura} insertada. Triggers ejecutados.", "success")
        except Exception as e:
            flash(f"Error al simular lectura GPS: {e}", "error")
    return render_template("sim_gps.html",
                           dispositivos_gps=dispositivos_gps,
                           zonas_ref=Zona.ref(),
                           result=result)


@bp.route("/api/gps/lectura", methods=["POST"])
def api_gps_lectura():
    if not iot_auth():
        return jsonify({"status": "error", "message": "No autorizado"}), 401

    data           = request.get_json(silent=True) or {}
    id_dispositivo = data.get("id_dispositivo")
    latitud        = data.get("latitud")
    longitud       = data.get("longitud")
    nivel_bateria  = data.get("nivel_bateria", 100)
    altura         = data.get("altura")

    if not id_dispositivo or latitud is None or longitud is None:
        return jsonify({"status": "error",
                        "message": "Faltan campos: id_dispositivo, latitud, longitud"}), 400

    try:
        id_lectura = IoT.registrar_gps(id_dispositivo, latitud, longitud, nivel_bateria, altura)
        return jsonify({"status": "ok", "id_lectura": id_lectura})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 422


@bp.route("/api/gps/osmand", methods=["GET", "POST"])
def api_gps_osmand():
    from flask import current_app
    device_id = request.args.get("id", "").strip()

    json_body = request.get_json(silent=True, force=True)
    if json_body and "location" in json_body:
        coords   = json_body["location"].get("coords", {})
        lat      = coords.get("latitude")
        lon      = coords.get("longitude")
        altitude = coords.get("altitude")
        raw_batt = json_body["location"].get("battery", {}).get("level", -1)
        batt = max(0, min(100, int(raw_batt * 100))) if raw_batt >= 0 else None
    else:
        lat      = request.values.get("lat")
        lon      = request.values.get("lon")
        altitude = request.values.get("altitude")
        batt     = request.values.get("batt") or request.values.get("battery")

    if not device_id or lat is None or lon is None:
        return f"Missing params — id={device_id!r} lat={lat!r} lon={lon!r}", 400

    try:
        row = Dispositivo.por_serial(device_id)
        if row and row.get("tipo") == "GPS":
            id_dispositivo = row["id_dispositivo"]
        else:
            try:
                id_dispositivo = int(device_id)
            except ValueError:
                return f"Device not found: {device_id}", 404

        latitud       = float(lat)
        longitud      = float(lon)
        nivel_bateria = int(batt) if batt is not None else 100
        altura        = float(altitude) if altitude else None

        current_app.logger.debug("OsmAnd insert: id=%s lat=%s lon=%s batt=%s alt=%s",
                                 id_dispositivo, latitud, longitud, nivel_bateria, altura)
        IoT.registrar_gps(id_dispositivo, latitud, longitud, nivel_bateria, altura)
        return "OK", 200
    except Exception as e:
        current_app.logger.error("OsmAnd SP error: %s", e)
        return str(e), 422


# ── GPS — última posición (polling) ──────────────────────────────────────────

@bp.route("/api/gps/ultima/<int:id_paciente>")
def api_gps_ultima(id_paciente):
    from flask import session as _s

    contacto_id = _s.get("contacto_id")
    is_staff    = _s.get("admin") or _s.get("medico")

    if not contacto_id and not is_staff:
        return jsonify({"status": "error", "message": "No autorizado"}), 401

    if contacto_id and not is_staff:
        if not Paciente.verificar_contacto(contacto_id, id_paciente):
            return jsonify({"status": "error", "message": "Acceso denegado"}), 403

    gps = IoT.ultima_lectura_gps(id_paciente, 1)
    if not gps:
        return jsonify({"status": "sin_datos"})

    zonas       = Zona.por_paciente(id_paciente)
    dentro_zona = False
    nombre_zona = None
    for z in zonas:
        if haversine_m(gps["latitud"], gps["longitud"],
                       z["latitud_centro"], z["longitud_centro"]) <= float(z["radio_metros"]):
            dentro_zona = True
            nombre_zona = z["nombre_zona"]
            break

    return jsonify({
        "status":        "ok",
        "latitud":       float(gps["latitud"]),
        "longitud":      float(gps["longitud"]),
        "nivel_bateria": gps.get("nivel_bateria"),
        "fecha_hora":    gps["fecha_hora"].isoformat() if gps.get("fecha_hora") else None,
        "dentro_zona":   dentro_zona,
        "nombre_zona":   nombre_zona,
    })


# ── NFC test page (dev only) ──────────────────────────────────────────────────

@bp.route("/test/nfc")
def test_nfc_page():
    return render_template("test_nfc.html")


@bp.route("/api/test/nfc", methods=["POST"])
def test_nfc_read():
    from flask import current_app
    data       = request.get_json(silent=True) or {}
    tag_serial = data.get("tag_serial", "").strip()

    if not tag_serial:
        return jsonify({"status": "error", "message": "No serial received"}), 400

    device = Dispositivo.por_serial_tipo(tag_serial, "NFC")

    if not device:
        current_app.logger.info("Unknown NFC tag scanned: %s", tag_serial)
        return jsonify({
            "status":     "not_found",
            "tag_serial": tag_serial,
            "message":    "Tag not registered. Add this serial to Dispositivos as type NFC.",
        })

    try:
        patient = Paciente.por_nfc(device["id_serial"])
    except Exception:
        patient = None

    response = {
        "status":         "found",
        "device_id":      device["id_dispositivo"],
        "device_serial":  device["id_serial"],
        "device_status":  device["estado"],
        "tag_serial_raw": tag_serial,
        "patient_name":   "Sin paciente asignado",
        "patient_id":     None,
    }
    if patient:
        response["patient_name"] = f"{patient['nombre']} {patient['apellido_p']}"
        response["patient_id"]   = patient["id_paciente"]

    return jsonify(response)
