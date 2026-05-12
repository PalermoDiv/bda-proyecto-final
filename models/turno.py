import db


def listar():
    return db.query_sp("sp_sel_turnos")


def obtener(id):
    return db.one_sp("sp_sel_turno_por_id", (id,))


def staff_en_turno(id_sede):
    return db.one_sp("sp_sel_staff_en_turno", (id_sede,))


def crear(id_cuidador, id_zona, hora_inicio, hora_fin, dias):
    db.execute(
        "CALL sp_ins_turno(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
        (id_cuidador, id_zona, hora_inicio, hora_fin,
         dias["lunes"], dias["martes"], dias["miercoles"], dias["jueves"],
         dias["viernes"], dias["sabado"], dias["domingo"]),
    )


def actualizar(id, id_cuidador, id_zona, hora_inicio, hora_fin, dias, activo):
    db.execute(
        "CALL sp_upd_turno(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
        (id, id_cuidador, id_zona, hora_inicio, hora_fin,
         dias["lunes"], dias["martes"], dias["miercoles"], dias["jueves"],
         dias["viernes"], dias["sabado"], dias["domingo"], activo),
    )


def eliminar(id):
    db.execute("CALL sp_del_turno(%s)", (id,))
