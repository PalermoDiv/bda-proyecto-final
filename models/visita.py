import db


def hoy():
    return db.query_sp("sp_sel_visitas_hoy")


def historial():
    return db.query_sp("sp_sel_visitas_historial")


def entregas_externas():
    return db.query_sp("sp_sel_entregas_externas")


def entregas_pendientes():
    return db.query_sp("sp_sel_entregas_pendientes")


def visitantes():
    return db.query_sp("sp_sel_visitantes")


def por_paciente(id_paciente):
    return db.query_sp("sp_sel_visitas_por_paciente", (id_paciente,))


def entregas_por_paciente(id_paciente):
    return db.query_sp("sp_sel_entregas_por_paciente", (id_paciente,))


def portal(id_paciente):
    return db.query_sp("sp_sel_visitas_portal", (id_paciente,))


def crear(id_paciente, id_visitante, id_sede, fecha, hora):
    db.execute("CALL sp_ins_visita(%s, %s, %s, %s, %s)",
               (id_paciente, id_visitante, id_sede, fecha, hora))
