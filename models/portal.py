import db


def login(email):
    return db.query_sp("sp_sel_contacto_login", (email,))


def ultima_ronda_paciente(id_paciente):
    return db.one_sp("sp_sel_ultima_ronda_por_paciente", (id_paciente,))


def bateria_historial(id_paciente, limit=20):
    return db.query_sp("sp_sel_bateria_historial_gps", (id_paciente, limit))
