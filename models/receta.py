import db


def listar():
    return db.query_sp("sp_sel_recetas")


def obtener(id):
    return db.one_sp("sp_sel_receta_por_id", (id,))


def siguiente_id():
    return db.one_sp("sp_sel_next_id_receta")["next_id"]


def siguiente_id_detalle():
    return db.one_sp("sp_sel_next_id_detalle_receta")["next_id"]


def medicamentos(id):
    return db.query_sp("sp_sel_receta_medicamentos_por_receta", (id,))


def medicamentos_disponibles(id):
    return db.query_sp("sp_sel_medicamentos_disponibles_receta", (id,))


def nfc_activo(id):
    return db.one_sp("sp_sel_nfc_activo_por_receta", (id,))


def nfc_activa_por_dispositivo(id_dispositivo):
    return db.one_sp("sp_sel_receta_nfc_activa", (id_dispositivo,))


def lecturas_nfc(id):
    return db.query_sp("sp_sel_lecturas_nfc_por_receta", (id,))


def adherencia_chart():
    return db.query_sp("sp_sel_adherencia_nfc_por_paciente")


def adherencia_por_paciente(id_paciente):
    return db.query_sp("sp_sel_medicamentos_adherencia_por_paciente", (id_paciente,))


def dosis_nfc_hoy(id_paciente):
    return db.one_sp("sp_sel_dosis_nfc_hoy", (id_paciente,))


def crear(next_id, id_paciente, fecha):
    db.execute("CALL sp_receta_crear(%s, %s, %s)", (next_id, id_paciente, fecha))


def agregar_medicamento(next_det, id_receta, gtin, dosis, frecuencia_horas):
    db.execute("CALL sp_receta_agregar_medicamento(%s, %s, %s, %s, %s)",
               (next_det, id_receta, gtin, dosis, frecuencia_horas))


def actualizar_medicamento(id_detalle, id_receta, dosis, frecuencia_horas):
    db.execute("CALL sp_receta_actualizar_medicamento(%s, %s, %s, %s)",
               (id_detalle, id_receta, dosis, frecuencia_horas))


def quitar_medicamento(id_detalle, id_receta):
    db.execute("CALL sp_receta_quitar_medicamento(%s, %s)", (id_detalle, id_receta))


def cerrar(id):
    db.execute("CALL sp_receta_cerrar(%s, CURRENT_DATE)", (id,))


def activar_nfc(id, id_dispositivo):
    db.execute("CALL sp_receta_activar_nfc(%s, %s, CURRENT_DATE)", (id, id_dispositivo))


def cerrar_nfc(id, id_dispositivo):
    db.execute("CALL sp_receta_cerrar_nfc(%s, %s, CURRENT_DATE)", (id, id_dispositivo))


def cambiar_nfc(id, id_dispositivo_nuevo):
    db.execute("CALL sp_receta_cambiar_nfc(%s, %s, CURRENT_DATE)", (id, id_dispositivo_nuevo))
