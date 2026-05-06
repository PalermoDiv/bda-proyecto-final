from flask import Blueprint, render_template
from datetime import date, timedelta
import db
from auth import admin_requerido

bp = Blueprint("admin", __name__)


@bp.route("/dashboard")
@admin_requerido
def dashboard():
    stats = dict(db.one_sp("sp_sel_dashboard_stats"))

    sedes = db.query_sp("sp_sel_sedes")
    sede_stats = {r["id_sede"]: r for r in db.query_sp("sp_sel_stats_por_sede")}

    stats_por_sede = []
    for s in sedes:
        sid = s["id_sede"]
        ss = sede_stats.get(sid, {})
        stats_por_sede.append({
            "sucursal": {
                "id_sucursal": sid,
                "nombre":    s["nombre_sede"],
                "zona":      "",
                "direccion": s["direccion"],
                "director":  "",
            },
            "pacientes":       ss.get("total_pacientes", 0),
            "cuidadores":      ss.get("total_cuidadores", 0),
            "dispositivos":    ss.get("total_dispositivos", 0),
            "alertas_activas": ss.get("alertas_activas", 0),
        })

    alertas                = db.query_sp("sp_sel_alertas_recientes")
    medicamentos_criticos  = db.query_sp("sp_sel_medicamentos_criticos")
    suministros_pendientes = db.query_sp("sp_sel_suministros_pendientes")
    visitas_hoy            = db.query_sp("sp_sel_visitas_hoy")

    alertas_por_tipo = db.query_sp("sp_sel_resumen_alertas_por_tipo")
    alertas_por_dia  = db.query_sp("sp_sel_alertas_por_dia_14d")
    hoy = date.today()
    dia_map = {r["dia_label"]: int(r["total"]) for r in alertas_por_dia}
    alertas_dias_labels  = []
    alertas_dias_valores = []
    for i in range(13, -1, -1):
        d = hoy - timedelta(days=i)
        label = d.strftime("%d/%m")
        alertas_dias_labels.append(label)
        alertas_dias_valores.append(dia_map.get(label, 0))

    stock_farmacia = db.query_sp("sp_sel_stock_farmacia_completo")

    return render_template(
        "dashboard.html",
        stats=stats,
        alertas=alertas,
        stats_por_sede=stats_por_sede,
        sucursales=sedes,
        medicamentos_criticos=medicamentos_criticos,
        suministros_pendientes=suministros_pendientes,
        visitas_hoy=visitas_hoy,
        alertas_por_tipo=alertas_por_tipo,
        alertas_dias_labels=alertas_dias_labels,
        alertas_dias_valores=alertas_dias_valores,
        stock_farmacia=stock_farmacia,
    )


@bp.route("/reportes")
@admin_requerido
def reportes():
    stats = dict(db.one_sp("sp_sel_reportes_stats"))
    return render_template("reportes.html", stats=stats)


@bp.route("/procedimientos")
@admin_requerido
def procedimientos():
    return render_template("procedimientos.html")
