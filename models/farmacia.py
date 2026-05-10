import db


def inventario():
    return db.query_sp("sp_sel_inventario_farmacia")


def suministros():
    return db.query_sp("sp_sel_suministros")


def farmacias_proveedoras():
    return db.query_sp("sp_sel_farmacias_proveedoras")


def medicamentos_catalogo():
    return db.query_sp("sp_sel_medicamentos_catalogo")


def stock_completo():
    return db.query_sp("sp_sel_stock_farmacia_completo")


def medicamentos_criticos():
    return db.query_sp("sp_sel_medicamentos_criticos")


def suministros_pendientes():
    return db.query_sp("sp_sel_suministros_pendientes")


def siguiente_id_suministro():
    return db.one_sp("sp_sel_next_id_suministro")["next_id"]


def suministro_por_id(id):
    return db.one_sp("sp_sel_suministro_por_id", (id,))


def lineas_suministro(id):
    return db.query_sp("sp_sel_lineas_suministro_por_id", (id,))


def estados_suministro():
    return db.query_sp("sp_sel_cat_estado_suministro")


def ajustar_stock(gtin, id_sede, stock_nuevo):
    db.execute("CALL sp_upd_stock(%s, %s, %s)", (gtin, id_sede, stock_nuevo))


def crear_suministro(id_sum, id_farmacia, id_sede, fecha, estado):
    db.execute("CALL sp_ins_suministro(%s, %s, %s, %s, %s)",
               (id_sum, id_farmacia, id_sede, fecha, estado))


def agregar_linea(id_sum, gtin, cantidad):
    db.execute("CALL sp_ins_suministro_linea(%s, %s, %s)", (id_sum, gtin, cantidad))


def actualizar_estado_suministro(id, estado):
    db.execute("CALL sp_upd_suministro_estado(%s, %s)", (id, estado))


def eliminar_suministro(id):
    db.execute("CALL sp_del_suministro(%s)", (id,))
