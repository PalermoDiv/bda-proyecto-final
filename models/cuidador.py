import db


def listar():
    return db.query_sp("sp_sel_cuidadores")


def obtener(id):
    return db.one_sp("sp_sel_cuidador_por_id", (id,))


def siguiente_id():
    return db.one_sp("sp_sel_next_id_empleado")["next_id"]


def dropdown():
    return db.query_sp("sp_sel_cuidadores_dropdown")


def por_paciente(id_paciente):
    return db.query_sp("sp_sel_cuidadores_por_paciente", (id_paciente,))


def sin_beacon():
    return db.query_sp("sp_sel_cuidadores_sin_beacon")


def crear(id_cuid, nombre, apellido_p, apellido_m, curp, telefono):
    db.execute("CALL sp_ins_cuidador(%s, %s, %s, %s, %s, %s)",
               (id_cuid, nombre, apellido_p, apellido_m, curp, telefono))


def actualizar(id, nombre, apellido_p, apellido_m, curp, telefono):
    db.execute("CALL sp_upd_cuidador(%s, %s, %s, %s, %s, %s)",
               (id, nombre, apellido_p, apellido_m, curp, telefono))


def eliminar(id):
    db.execute("CALL sp_del_cuidador(%s)", (id,))
