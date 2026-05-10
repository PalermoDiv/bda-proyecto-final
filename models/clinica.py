import db


def pacientes_sede(id_sede):
    return db.query_sp("sp_sel_clinica_pacientes", (id_sede,))


def alertas_activas(id_sede):
    return db.query_sp("sp_sel_clinica_alertas_activas", (id_sede,))


def asignaciones(id_sede):
    return db.query_sp("sp_sel_clinica_asignaciones", (id_sede,))


def meds(id_sede):
    return db.query_sp("sp_sel_clinica_meds", (id_sede,))


def enfermedades(id_sede):
    return db.query_sp("sp_sel_clinica_enfermedades", (id_sede,))


def incidentes(id_sede):
    return db.query_sp("sp_sel_clinica_incidentes", (id_sede,))


def comedor_hoy(id_sede):
    return db.query_sp("sp_sel_clinica_comedor_hoy", (id_sede,))


def cobertura_zonas(id_sede):
    return db.query_sp("sp_sel_clinica_cobertura_zonas", (id_sede,))


def gps_estado(id_sede):
    return db.query_sp("sp_sel_clinica_gps_estado", (id_sede,))


def zonas_mapa(id_sede):
    return db.query_sp("sp_sel_clinica_zonas_mapa", (id_sede,))


def alertas_salida_zona(id_sede):
    return db.query_sp("sp_sel_clinica_alertas_salida_zona", (id_sede,))


def meds_nfc_hoy(id_sede):
    return db.query_sp("sp_sel_clinica_meds_nfc_hoy", (id_sede,))


def nfc_hoy(id_sede):
    return db.query_sp("sp_sel_clinica_nfc_hoy", (id_sede,))


def staff_en_turno(id_sede):
    return db.one_sp("sp_sel_staff_en_turno", (id_sede,))
