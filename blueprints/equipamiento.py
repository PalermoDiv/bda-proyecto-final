from flask import Blueprint, render_template, request, redirect, url_for, flash
import db
import mongo
from auth import admin_requerido

bp = Blueprint("equipamiento", __name__)


@bp.route("/equipamiento/asignacion-beacons", methods=["GET", "POST"])
@admin_requerido
def beacon_asignaciones():
    if request.method == "POST":
        try:
            id_dispositivo = int(request.form["id_dispositivo"])
            id_cuidador    = int(request.form["id_cuidador"])
            db.execute("CALL sp_ins_asignacion_beacon(%s, %s)", (id_dispositivo, id_cuidador))
            flash("Beacon asignado correctamente.", "success")
        except Exception as e:
            flash(f"Error al asignar beacon: {e}", "error")
        return redirect(url_for("equipamiento.beacon_asignaciones"))

    asignaciones = db.query_sp("sp_sel_asignacion_beacon_todas")
    beacons      = db.query_sp("sp_sel_beacons_disponibles_asig")
    cuidadores   = db.query_sp("sp_sel_cuidadores_sin_beacon")
    return render_template("equipamiento/asignacion_beacons.html",
                           asignaciones=asignaciones,
                           beacons=beacons,
                           cuidadores=cuidadores)


@bp.route("/equipamiento/asignacion-beacons/<int:id>/cerrar", methods=["POST"])
@admin_requerido
def beacon_cerrar_asignacion(id):
    try:
        db.execute("CALL sp_upd_cerrar_asignacion_beacon(%s)", (id,))
        flash("Asignación cerrada correctamente.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("equipamiento.beacon_asignaciones"))


@bp.route("/rondas")
@admin_requerido
def rondas_lista():
    docs = mongo.col("detecciones_beacon").find(
        {}, {"_id": 0}, sort=[("fecha_hora", -1)], limit=50
    )
    rondas = [
        {
            "id_deteccion":  d.get("id_deteccion"),
            "fecha_hora":    d.get("fecha_hora"),
            "id_gateway":    d.get("id_gateway"),
            "serial_beacon": d.get("serial_beacon", "—"),
            "nombre_cuidador": d.get("nombre_cuidador", "Anónimo"),
            "rssi":          d.get("rssi"),
        }
        for d in docs
    ]
    return render_template("rondas/lista.html", rondas=rondas)
