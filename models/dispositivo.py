import db


def listar():
    return db.query_sp("sp_sel_dispositivos")


def obtener(id):
    return db.one_sp("sp_sel_dispositivo_raw", (id,))


def por_serial(serial):
    return db.one_sp("sp_sel_dispositivo_serial", (serial,))


def por_serial_tipo(serial, tipo):
    return db.one_sp("sp_sel_dispositivo_por_serial_tipo", (serial, tipo))


def gps_activos():
    return db.query_sp("sp_sel_dispositivos_gps_activos")


def beacons_disponibles():
    return db.query_sp("sp_sel_beacons_disponibles_asig")


def crear(id_disp, id_serial, tipo, modelo):
    db.execute("CALL sp_ins_dispositivo(%s, %s, %s, %s)", (id_disp, id_serial, tipo, modelo))


def actualizar(id, id_serial, tipo, modelo, estado):
    db.execute("CALL sp_upd_dispositivo(%s, %s, %s, %s, %s)",
               (id, id_serial, tipo, modelo, estado))


def eliminar(id):
    db.execute("CALL sp_del_dispositivo(%s)", (id,))
