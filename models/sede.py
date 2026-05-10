import db


def listar():
    return db.query_sp("sp_sel_sedes")


def obtener(id):
    return db.one_sp("sp_sel_sede_por_id", (id,))


def stats_por_sede():
    return db.query_sp("sp_sel_stats_por_sede")


def siguiente_id():
    return db.one_sp("sp_sel_next_id_sede")["next_id"]


def crear(id_sede, nombre, calle, numero, municipio, estado):
    db.execute("CALL sp_ins_sede(%s, %s, %s, %s, %s, %s)",
               (id_sede, nombre, calle, numero, municipio, estado))


def actualizar(id, nombre, calle, numero, municipio, estado):
    db.execute("CALL sp_upd_sede(%s, %s, %s, %s, %s, %s)",
               (id, nombre, calle, numero, municipio, estado))


def eliminar(id):
    db.execute("CALL sp_del_sede(%s)", (id,))
