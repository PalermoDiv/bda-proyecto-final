import db


def listar():
    return db.query_sp("sp_sel_alertas")


def listar_recientes():
    return db.query_sp("sp_sel_alertas_recientes")


def banner():
    return db.query_sp("sp_sel_alertas_banner")


def tipos():
    return db.query_sp("sp_sel_cat_tipo_alerta")


def contactos_emergencia():
    return db.query_sp("sp_sel_contactos_emergencia")


def por_paciente(id_paciente):
    return db.query_sp("sp_sel_alertas_por_paciente", (id_paciente,))


def activas_por_paciente(id_paciente):
    return db.query_sp("sp_sel_alertas_activas_por_paciente", (id_paciente,))


def historial_por_paciente(id_paciente):
    return db.query_sp("sp_sel_alertas_historial_por_paciente", (id_paciente,))


def resumen_por_tipo():
    return db.query_sp("sp_sel_resumen_alertas_por_tipo")


def por_dia_14d():
    return db.query_sp("sp_sel_alertas_por_dia_14d")


def critica_por_paciente(id_paciente):
    return db.one_sp("sp_sel_alerta_critica_por_paciente", (id_paciente,))


def sim_recientes():
    return db.query_sp("sp_sel_alertas_sim_recientes")


def crear(id_paciente, tipo_alerta, fecha_hora):
    db.execute("CALL sp_ins_alerta(%s, %s, %s)", (id_paciente, tipo_alerta, fecha_hora))


def resolver(id):
    db.execute("CALL sp_upd_alerta_atendida(%s)", (id,))


def eliminar(id):
    db.execute("CALL sp_del_alerta(%s)", (id,))
