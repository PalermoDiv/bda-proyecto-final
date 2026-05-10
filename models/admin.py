import db


def dashboard_stats():
    return db.one_sp("sp_sel_dashboard_stats")


def reportes_stats():
    return db.one_sp("sp_sel_reportes_stats")
