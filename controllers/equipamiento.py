from flask import Blueprint, render_template, request, redirect, url_for, flash
import models.equipamiento as Equipamiento
import models.cuidador as Cuidador
import models.dispositivo as Dispositivo
from auth import admin_requerido

bp = Blueprint("equipamiento", __name__)


@bp.route("/equipamiento/asignacion-beacons", methods=["GET", "POST"])
@admin_requerido
def beacon_asignaciones():
    if request.method == "POST":
        try:
            id_dispositivo = int(request.form["id_dispositivo"])
            id_cuidador    = int(request.form["id_cuidador"])
            Equipamiento.asignar_beacon(id_dispositivo, id_cuidador)
            flash("Beacon asignado correctamente.", "success")
        except Exception as e:
            flash(f"Error al asignar beacon: {e}", "error")
        return redirect(url_for("equipamiento.beacon_asignaciones"))

    return render_template("equipamiento/asignacion_beacons.html",
                           asignaciones=Equipamiento.asignaciones_beacon(),
                           beacons=Dispositivo.beacons_disponibles(),
                           cuidadores=Cuidador.sin_beacon())


@bp.route("/equipamiento/asignacion-beacons/<int:id>/cerrar", methods=["POST"])
@admin_requerido
def beacon_cerrar_asignacion(id):
    try:
        Equipamiento.cerrar_asignacion_beacon(id)
        flash("Asignación cerrada correctamente.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("equipamiento.beacon_asignaciones"))


@bp.route("/rondas")
@admin_requerido
def rondas_lista():
    return render_template("rondas/lista.html",
                           rondas=Equipamiento.rondas(),
                           rondas_chart=Equipamiento.rondas_chart())
