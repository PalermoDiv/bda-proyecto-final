import db


def listar_activos():
    return db.query_sp("sp_sel_pacientes_activos")


def obtener(id):
    return db.one_sp("sp_sel_paciente_por_id", (id,))


def estados():
    return db.query_sp("sp_sel_estados_paciente")


def sede_activa(id):
    return db.query_sp("sp_sel_sede_activa_por_paciente", (id,))


def historial_sedes(id):
    return db.query_sp("sp_sel_historial_sedes_por_paciente", (id,))


def enfermedades(id):
    return db.query_sp("sp_sel_enfermedades_por_paciente", (id,))


def enfermedades_disponibles(id):
    return db.query_sp("sp_sel_enfermedades_disponibles", (id,))


def cuidadores(id):
    return db.query_sp("sp_sel_cuidadores_por_paciente", (id,))


def contactos(id):
    return db.query_sp("sp_sel_contactos_por_paciente", (id,))


def kit(id):
    return db.one_sp("sp_sel_kit_por_paciente", (id,))


def gps_disponibles():
    return db.query_sp("sp_sel_gps_disponibles")


def nfc_asignacion(id):
    return db.one_sp("sp_sel_nfc_asignacion_por_paciente", (id,))


def nfc_disponibles():
    return db.query_sp("sp_sel_nfc_disponibles")


def por_contacto(contacto_id):
    return db.query_sp("sp_sel_pacientes_por_contacto", (contacto_id,))


def verificar_contacto(contacto_id, id_paciente):
    return db.one_sp("sp_sel_contacto_verificacion", (contacto_id, id_paciente))


def por_nfc(serial):
    return db.one_sp("sp_sel_paciente_por_nfc", (serial,))


def ultima_actividad(id):
    return db.one_sp("sp_sel_ultima_actividad_ts", (id,))


def crear(nombre, apellido_p, apellido_m, fecha_nac, id_estado, id_sede):
    db.execute("CALL sp_ins_paciente(%s, %s, %s, %s, %s, %s)",
               (nombre, apellido_p, apellido_m, fecha_nac, id_estado, id_sede))


def actualizar(id, nombre, apellido_p, apellido_m, fecha_nac, id_estado):
    db.execute("CALL sp_upd_paciente(%s, %s, %s, %s, %s, %s)",
               (id, nombre, apellido_p, apellido_m, fecha_nac, id_estado))


def eliminar(id):
    db.execute("CALL sp_del_paciente(%s)", (id,))


def transferir_sede(id, nueva_sede_id):
    db.execute("CALL sp_transferir_sede(%s, %s)", (id, nueva_sede_id))


def asignar_nfc(id, id_dispositivo):
    db.execute("CALL sp_nfc_asignar(%s, %s)", (id, id_dispositivo))


def agregar_enfermedad(id, id_enfermedad, fecha_diag):
    db.execute("CALL sp_ins_enfermedad(%s, %s, %s)", (id, id_enfermedad, fecha_diag))


def quitar_enfermedad(id, id_enfermedad):
    db.execute("CALL sp_del_enfermedad(%s, %s)", (id, id_enfermedad))


def agregar_contacto(id, nombre, apellido_p, apellido_m, telefono, relacion, email, pin_acceso):
    db.execute("CALL sp_ins_contacto(%s, %s, %s, %s, %s, %s, %s, %s)",
               (id, nombre, apellido_p, apellido_m, telefono, relacion, email, pin_acceso))


def asignar_kit(id, id_gps):
    db.execute("CALL sp_ins_kit(%s, %s)", (id, id_gps))


def cambiar_kit(id, id_gps):
    db.execute("CALL sp_kit_reasignar(%s, %s)", (id, id_gps))
