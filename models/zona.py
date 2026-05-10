import db


def listar():
    return db.query_sp("sp_sel_zonas")


def obtener(id):
    return db.one_sp("sp_sel_zona_por_id", (id,))


def lista_dropdown():
    return db.query_sp("sp_sel_zonas_lista")


def por_paciente(id_paciente):
    return db.query_sp("sp_sel_zonas_por_paciente", (id_paciente,))


def sedes_asignadas(id_zona):
    return db.query_sp("sp_sel_sedes_por_zona", (id_zona,))


def ref():
    return db.query_sp("sp_sel_zonas_ref")


def siguiente_id():
    return db.one_sp("sp_sel_next_id_zona")["next_id"]


def crear(id_zona, nombre_zona, latitud, longitud, radio):
    db.execute("CALL sp_ins_zona(%s, %s, %s, %s, %s)",
               (id_zona, nombre_zona, latitud, longitud, radio))


def actualizar(id, nombre_zona, latitud, longitud, radio):
    db.execute("CALL sp_upd_zona(%s, %s, %s, %s, %s)",
               (id, nombre_zona, latitud, longitud, radio))


def eliminar(id):
    db.execute("CALL sp_del_zona(%s)", (id,))


def asignar_sede(id_zona, id_sede):
    db.execute("CALL sp_ins_sede_zona(%s, %s)", (id_zona, id_sede))


def desasignar_sedes(id_zona):
    db.execute("CALL sp_del_sedes_zona(%s)", (id_zona,))
