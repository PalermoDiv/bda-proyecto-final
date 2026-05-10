from flask import Blueprint, render_template, redirect, url_for
from datetime import date as _date, datetime as _dt
import models.clinica as Clinica
import models.sede as Sede
import models.visita as Visita
from auth import medico_requerido
from utils import haversine_m

bp = Blueprint("clinica", __name__, url_prefix="/clinica")

_MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
          'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']


@bp.route("/")
@medico_requerido
def clinica_sedes():
    sedes      = Sede.listar()
    sede_stats = {r["id_sede"]: r for r in Sede.stats_por_sede()}
    result = []
    for s in sedes:
        sid = s["id_sede"]
        ss  = sede_stats.get(sid, {})
        result.append({
            "sucursal": {
                "id_sucursal": sid,
                "nombre":      s["nombre_sede"],
                "zona":        s.get("municipio", ""),
                "direccion":   s.get("direccion", ""),
            },
            "total_pacientes": ss.get("total_pacientes", 0),
        })
    return render_template("clinica_sedes.html", sedes=result)


@bp.route("/<int:id_sucursal>")
@medico_requerido
def dashboard_clinica(id_sucursal):
    sede = Sede.obtener(id_sucursal)
    if not sede:
        return redirect(url_for("clinica.clinica_sedes"))

    sucursal = {"id_sucursal": sede["id_sede"], "nombre": sede["nombre_sede"]}

    pacientes_sede        = Clinica.pacientes_sede(id_sucursal)
    alertas_medicas_rows  = Clinica.alertas_activas(id_sucursal)
    alertas_activas_count = len(alertas_medicas_rows)
    alertas_medicas       = alertas_medicas_rows[:10]

    _now          = _dt.now()
    staff_row     = Clinica.staff_en_turno(id_sucursal)
    staff_en_turno = staff_row["staff_count"] if staff_row else 0

    _asig_rows   = Clinica.asignaciones(id_sucursal)
    asignaciones = {}
    for row in _asig_rows:
        rec = dict(row)
        rec["apellido_p_cuid"] = rec.pop("apellido_p", "")
        rec["apellido_m_cuid"] = rec.pop("apellido_m", "")
        asignaciones.setdefault(row["id_paciente"], []).append(rec)

    _med_rows = Clinica.meds(id_sucursal)
    medicamentos_por_paciente = {}
    for row in _med_rows:
        medicamentos_por_paciente.setdefault(row["id_paciente"], []).append(row)

    _enf_rows = Clinica.enfermedades(id_sucursal)
    enf_por_paciente = {}
    for row in _enf_rows:
        enf_por_paciente.setdefault(row["id_paciente"], []).append(row)

    expedientes = []
    for p in pacientes_sede:
        pid = p["id_paciente"]
        expedientes.append({
            "paciente":     p,
            "perfil":       {},
            "medicamentos": medicamentos_por_paciente.get(pid, []),
            "bitacoras":    [],
            "enfermedades": enf_por_paciente.get(pid, []),
        })

    _visitas_hoy_all = Visita.hoy()
    visitas_hoy = [v for v in _visitas_hoy_all if v["id_sede"] == id_sucursal]

    _entregas_all = Visita.entregas_pendientes()
    entregas_pend = [e for e in _entregas_all if e["id_sede"] == id_sucursal]

    hoy_obj   = _date.today()
    fecha_hoy = f"{hoy_obj.day} de {_MESES[hoy_obj.month - 1]}, {hoy_obj.year}"

    estado_pacientes   = Clinica.gps_estado(id_sucursal)
    zonas_mapa         = Clinica.zonas_mapa(id_sucursal)
    alertas_salida_ids = {
        row["id_paciente"]
        for row in Clinica.alertas_salida_zona(id_sucursal)
    }

    for p in estado_pacientes:
        if p["ultima_lectura"] is None:
            p["zona_status"] = "sin_datos"
            p["tiempo_rel"]  = None
        else:
            if p["id_paciente"] in alertas_salida_ids:
                p["zona_status"] = "fuera"
            else:
                dentro = any(
                    haversine_m(p["latitud"], p["longitud"],
                                float(z["latitud_centro"]), float(z["longitud_centro"]))
                    <= float(z["radio_metros"])
                    for z in zonas_mapa
                )
                p["zona_status"] = "dentro" if dentro else "fuera"
            mins = int((_now - p["ultima_lectura"]).total_seconds() / 60)
            if mins < 1:
                p["tiempo_rel"] = "hace un momento"
            elif mins < 60:
                p["tiempo_rel"] = f"hace {mins} min"
            elif mins < 1440:
                p["tiempo_rel"] = f"hace {mins // 60} h"
            else:
                p["tiempo_rel"] = f"hace {mins // 1440} d"

    meds_sede = Clinica.meds_nfc_hoy(id_sucursal)
    nfc_hoy   = {row["id_receta"]: row["hora_toma"]
                 for row in Clinica.nfc_hoy(id_sucursal)}
    for med in meds_sede:
        med["tomada_hoy"] = nfc_hoy.get(med["id_receta"])

    return render_template(
        "clinica.html",
        sucursal=sucursal,
        staff_en_turno=staff_en_turno,
        total_pacientes=len(pacientes_sede),
        tareas_pendientes=0,
        alertas_activas=alertas_activas_count,
        tareas=[],
        alertas_medicas=alertas_medicas,
        cobertura_zonas=Clinica.cobertura_zonas(id_sucursal),
        asignaciones=asignaciones,
        pacientes=pacientes_sede,
        expedientes=expedientes,
        incidentes=Clinica.incidentes(id_sucursal),
        comedor_hoy=Clinica.comedor_hoy(id_sucursal),
        visitas_hoy=visitas_hoy,
        entregas_pendientes=entregas_pend,
        fecha_hoy=fecha_hoy,
        estado_pacientes=estado_pacientes,
        zonas_mapa=zonas_mapa,
        meds_sede=meds_sede,
    )
