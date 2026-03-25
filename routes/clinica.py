from flask import render_template, redirect, url_for, session
import data


def init_routes(app):

    @app.route("/clinica")
    def clinica_sedes():
        if not session.get("medico"):
            return redirect(url_for("login"))

        sedes = []
        for s in data.SUCURSALES:
            sid = s["id_sucursal"]
            pacientes_sede = [p for p in data.PACIENTES if p["id_sucursal"] == sid]
            sedes.append({
                "sucursal": s,
                "total_pacientes": len(pacientes_sede),
            })

        return render_template("clinica_sedes.html", sedes=sedes)

    @app.route("/clinica/<int:id_sucursal>")
    def dashboard_clinica(id_sucursal):
        if not session.get("medico"):
            return redirect(url_for("login"))

        sucursal = next((s for s in data.SUCURSALES if s["id_sucursal"] == id_sucursal), None)
        if not sucursal:
            return redirect(url_for("clinica_sedes"))

        pacientes_sede = [p for p in data.PACIENTES if p["id_sucursal"] == id_sucursal]
        ids_sede = {p["id_paciente"] for p in pacientes_sede}

        staff_en_turno    = sum(1 for t in data.TURNOS_HOY if t["estado"] == "En turno")
        tareas_pendientes = sum(1 for t in data.TAREAS_HOY  if t["estado"] == "Pendiente")
        alertas_activas   = sum(1 for a in data.ALERTAS_MEDICAS if a["estado"] not in ("Atendida", "Resuelto"))

        expedientes = []
        for p in pacientes_sede:
            pid = p["id_paciente"]
            expedientes.append({
                "paciente":     p,
                "perfil":       data.PERFIL_CLINICO.get(pid, {}),
                "medicamentos": data.MEDICAMENTOS.get(pid, []),
                "bitacoras":    [b for b in data.BITACORAS if b["id_paciente"] == pid],
                "enfermedades": data.ENFERMEDADES.get(pid, []),
            })

        incidentes_sede = [i for i in data.INCIDENTES if i["id_paciente"] in ids_sede]

        return render_template(
            "clinica.html",
            sucursal=sucursal,
            staff_en_turno=staff_en_turno,
            total_pacientes=len(pacientes_sede),
            tareas_pendientes=tareas_pendientes,
            alertas_activas=alertas_activas,
            tareas=data.TAREAS_HOY,
            alertas_medicas=data.ALERTAS_MEDICAS,
            turnos=data.TURNOS_HOY,
            asignaciones=data.ASIGNACIONES_CUIDADORES,
            pacientes=pacientes_sede,
            expedientes=expedientes,
            incidentes=incidentes_sede,
        )
