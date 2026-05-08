from flask import Blueprint, render_template, request, redirect, url_for, flash, abort
from datetime import date, datetime, timezone, timedelta
import db
import mongo
from auth import admin_requerido

bp = Blueprint("recetas", __name__, url_prefix="/recetas")


@bp.route("/")
@admin_requerido
def recetas_lista():
    recetas          = db.query_sp("sp_sel_recetas")
    adherencia_chart = db.query_sp("sp_sel_adherencia_nfc_por_paciente")

    # Chart 3 — donut: tasa de éxito NFC (MongoDB)
    try:
        nfc_exito = [
            {"resultado": r["_id"], "total": r["total"]}
            for r in mongo.col("lecturas_nfc").aggregate([
                {"$group": {"_id": "$resultado", "total": {"$sum": 1}}},
                {"$sort": {"total": -1}},
            ])
        ]
    except Exception:
        nfc_exito = []

    # Chart 5 — columnas apiladas: lecturas NFC por día y resultado (MongoDB)
    try:
        since = datetime.now(timezone.utc) - timedelta(days=14)
        raw = list(mongo.col("lecturas_nfc").aggregate([
            {"$match": {"fecha_hora": {"$gte": since}}},
            {"$group": {
                "_id": {
                    "dia":      {"$dateToString": {"format": "%d/%m", "date": "$fecha_hora"}},
                    "resultado": "$resultado",
                },
                "total": {"$sum": 1},
            }},
        ]))
        hoy        = date.today()
        dias_labels = [(hoy - timedelta(days=i)).strftime("%d/%m") for i in range(13, -1, -1)]
        dia_map = {}
        for r in raw:
            dia_map.setdefault(r["_id"]["dia"], {})[r["_id"]["resultado"]] = r["total"]
        nfc_dias_labels = dias_labels
        nfc_exitosas    = [dia_map.get(d, {}).get("Exitosa", 0) for d in dias_labels]
        nfc_fallidas    = [dia_map.get(d, {}).get("Fallida", 0) for d in dias_labels]
    except Exception:
        nfc_dias_labels = []
        nfc_exitosas    = []
        nfc_fallidas    = []

    return render_template(
        "recetas.html",
        recetas=recetas,
        adherencia_chart=adherencia_chart,
        nfc_exito=nfc_exito,
        nfc_dias_labels=nfc_dias_labels,
        nfc_exitosas=nfc_exitosas,
        nfc_fallidas=nfc_fallidas,
    )


@bp.route("/nueva", methods=["GET", "POST"])
@admin_requerido
def recetas_nueva():
    pacientes = db.query_sp("sp_sel_pacientes_activos")
    if request.method == "POST":
        try:
            id_paciente = int(request.form["id_paciente"])
            fecha       = request.form["fecha"]
            next_id     = db.one_sp("sp_sel_next_id_receta")["next_id"]
            db.execute("CALL sp_receta_crear(%s, %s, %s)", (next_id, id_paciente, fecha))
            flash("Receta creada correctamente.", "success")
            return redirect(url_for("recetas.recetas_detalle", id=next_id))
        except Exception as e:
            flash(f"Error al crear receta: {e}", "error")
    return render_template("recetas_form.html", pacientes=pacientes, today=date.today().isoformat())


@bp.route("/<int:id>")
@admin_requerido
def recetas_detalle(id):
    receta = db.one_sp("sp_sel_receta_por_id", (id,))
    if not receta:
        abort(404)
    medicamentos             = db.query_sp("sp_sel_receta_medicamentos_por_receta", (id,))
    medicamentos_disponibles = db.query_sp("sp_sel_medicamentos_disponibles_receta", (id,))
    nfc                      = db.one_sp("sp_sel_nfc_activo_por_receta", (id,))
    lecturas                 = db.query_sp("sp_sel_lecturas_nfc_por_receta", (id,))
    nfc_disponibles          = db.query_sp("sp_sel_nfc_disponibles")
    return render_template("recetas_detalle.html",
                           receta=receta,
                           medicamentos=medicamentos,
                           medicamentos_disponibles=medicamentos_disponibles,
                           nfc=nfc,
                           nfc_disponibles=nfc_disponibles,
                           lecturas=lecturas)


@bp.route("/<int:id>/agregar-medicamento", methods=["POST"])
@admin_requerido
def recetas_agregar_medicamento(id):
    try:
        gtin             = request.form["gtin"]
        dosis            = request.form["dosis"].strip()
        frecuencia_horas = int(request.form["frecuencia_horas"])
        next_det = db.one_sp("sp_sel_next_id_detalle_receta")["next_id"]
        db.execute("CALL sp_receta_agregar_medicamento(%s, %s, %s, %s, %s)",
                   (next_det, id, gtin, dosis, frecuencia_horas))
        flash("Medicamento agregado correctamente.", "success")
    except Exception as e:
        flash(f"Error al agregar medicamento: {e}", "error")
    return redirect(url_for("recetas.recetas_detalle", id=id))


@bp.route("/<int:id>/actualizar-medicamento", methods=["POST"])
@admin_requerido
def recetas_actualizar_medicamento(id):
    try:
        id_detalle       = int(request.form["id_detalle"])
        dosis            = request.form["dosis"].strip()
        frecuencia_horas = int(request.form["frecuencia_horas"])
        db.execute("CALL sp_receta_actualizar_medicamento(%s, %s, %s, %s)",
                   (id_detalle, id, dosis, frecuencia_horas))
        flash("Medicamento actualizado correctamente.", "success")
    except Exception as e:
        flash(f"Error al actualizar medicamento: {e}", "error")
    return redirect(url_for("recetas.recetas_detalle", id=id))


@bp.route("/<int:id>/quitar-medicamento", methods=["POST"])
@admin_requerido
def recetas_quitar_medicamento(id):
    try:
        id_detalle = int(request.form["id_detalle"])
        db.execute("CALL sp_receta_quitar_medicamento(%s, %s)", (id_detalle, id))
        flash("Medicamento eliminado de la receta.", "success")
    except Exception as e:
        flash(f"Error al quitar medicamento: {e}", "error")
    return redirect(url_for("recetas.recetas_detalle", id=id))


@bp.route("/<int:id>/cerrar", methods=["POST"])
@admin_requerido
def recetas_cerrar(id):
    try:
        db.execute("CALL sp_receta_cerrar(%s, CURRENT_DATE)", (id,))
        flash("Receta cerrada correctamente.", "success")
    except Exception as e:
        flash(f"Error al cerrar receta: {e}", "error")
    return redirect(url_for("recetas.recetas_detalle", id=id))


@bp.route("/<int:id>/activar-nfc", methods=["POST"])
@admin_requerido
def recetas_activar_nfc(id):
    try:
        id_dispositivo = int(request.form["id_dispositivo"])
        db.execute("CALL sp_receta_activar_nfc(%s, %s, CURRENT_DATE)", (id, id_dispositivo))
        flash("Pulsera NFC vinculada correctamente.", "success")
    except Exception as e:
        flash(f"Error al activar NFC: {e}", "error")
    return redirect(url_for("recetas.recetas_detalle", id=id))


@bp.route("/<int:id>/cerrar-nfc", methods=["POST"])
@admin_requerido
def recetas_cerrar_nfc(id):
    try:
        id_dispositivo = int(request.form["id_dispositivo"])
        db.execute("CALL sp_receta_cerrar_nfc(%s, %s, CURRENT_DATE)", (id, id_dispositivo))
        flash("Vínculo NFC cerrado.", "success")
    except Exception as e:
        flash(f"Error al cerrar NFC: {e}", "error")
    return redirect(url_for("recetas.recetas_detalle", id=id))


@bp.route("/<int:id>/cambiar-nfc", methods=["POST"])
@admin_requerido
def recetas_cambiar_nfc(id):
    try:
        id_dispositivo_nuevo = int(request.form["id_dispositivo_nuevo"])
        db.execute("CALL sp_receta_cambiar_nfc(%s, %s, CURRENT_DATE)", (id, id_dispositivo_nuevo))
        flash("Pulsera NFC reemplazada correctamente.", "success")
    except Exception as e:
        flash(f"Error al cambiar NFC: {e}", "error")
    return redirect(url_for("recetas.recetas_detalle", id=id))
