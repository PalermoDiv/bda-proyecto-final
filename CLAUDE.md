# AlzMonitor — CLAUDE.md

Sistema de gestión clínica multisede para pacientes de Alzheimer. Proyecto final de Bases de Datos Avanzadas (BDA). Integra PostgreSQL, MongoDB, IoT (GPS/BLE/NFC) y un portal web en Flask.

---

## Arquitectura general

```
app.py          → Flask app factory; registra 18 blueprints
blueprints/     → Rutas organizadas por dominio
templates/      → Jinja2; base.html (admin) y portal_familiar/base_familiar.html
static/         → CSS y JS compartidos
db.py           → PostgreSQL (psycopg3) — solo stored procedures
mongo.py        → MongoDB — espejo de lecturas IoT
auth.py         → Decoradores de sesión: admin_requerido, medico_requerido, contacto_requerido
utils.py        → haversine_m(lat1, lon1, lat2, lon2) → metros
beacon_scanner.py → Escáner BLE independiente; reporta a /api/beacon/deteccion
```

### Puertos

| Puerto | Protocolo | Propósito |
|--------|-----------|-----------|
| 5002   | HTTPS     | App principal (cert.pem / key.pem) |
| 5003   | HTTP      | Receptor Traccar / OsmAnd |

---

## Base de datos

### PostgreSQL — regla de oro

**Todas las lecturas y escrituras pasan por stored procedures.** No se usan consultas SQL directas a tablas.

```python
# Leer muchas filas
rows = db.query_sp("sp_sel_nombre_sp", (param1, param2))

# Leer una fila
row  = db.one_sp("sp_sel_nombre_sp", (param1,))

# Ejecutar INSERT / UPDATE / DELETE
db.execute("CALL sp_ins_algo(%s, %s)", (val1, val2))
```

Los SPs devuelven un REFCURSOR llamado `io_resultados`. `db.query_sp` abre el cursor automáticamente.

### MongoDB — espejo secundario

Las lecturas IoT se insertan también en MongoDB (`alzmonitor` DB). Las colecciones son:

- `lecturas_gps`
- `detecciones_beacon`
- `lecturas_nfc`

Si MongoDB falla, la operación principal en PostgreSQL no se revierte (try/except silencioso con log).

```python
mongo.col("lecturas_gps").insert_one({...})
```

---

## Autenticación y sesiones

| Session key     | Rol                          | Decorador          |
|-----------------|------------------------------|--------------------|
| `session["admin"]`     | Administrador            | `@admin_requerido` |
| `session["medico"]`    | Médico                   | `@medico_requerido` |
| `session["contacto_id"]` | Familiar (portal)      | `@contacto_requerido` |

Los endpoints IoT usan `iot_auth()` → verifica header `X-AlzMonitor-Key: alz-dev-2026` o sesión staff.

---

## Blueprints (blueprints/)

| Archivo              | Prefijo URL         | Descripción |
|----------------------|---------------------|-------------|
| `auth.py`            | `/login`, `/logout` | Login admin/medico |
| `admin.py`           | `/admin`            | Panel administración |
| `pacientes.py`       | `/pacientes`        | CRUD pacientes, historial, GPS, NFC |
| `cuidadores.py`      | `/cuidadores`       | CRUD cuidadores |
| `cuidador.py`        | `/cuidador`         | Vista ronda de cuidador |
| `turnos.py`          | `/turnos`           | Gestión de turnos |
| `alertas.py`         | `/alertas`          | Alertas clínicas |
| `dispositivos.py`    | `/dispositivos`     | Inventario GPS/NFC/Beacon |
| `zonas.py`           | `/zonas`            | Geocercas de zona segura |
| `farmacia.py`        | `/farmacia`         | Suministros farmacéuticos |
| `visitas.py`         | `/visitas`          | Registro de visitas |
| `recetas.py`         | `/recetas`          | Recetas médicas + lectura NFC |
| `equipamiento.py`    | `/equipamiento`     | Equipamiento clínico |
| `clinica.py`         | `/clinica`          | Vista clínica / médico |
| `portal_familiar.py` | `/portal-familiar`  | Portal para familiares |
| `sedes.py`           | `/sedes`            | Gestión multisede |
| `api.py`             | `/api`, `/sim`      | Endpoints IoT y simulador GPS |

---

## IoT — Flujo de datos

### GPS

1. **OsmAnd / Traccar** → `GET /api/gps/osmand?id=<serial>&lat=&lon=&batt=` (puerto 5003 HTTP o 5002 HTTPS)
2. **API directa** → `POST /api/gps/lectura` (JSON, requiere `X-AlzMonitor-Key`)
3. **Simulador admin** → `POST /sim/gps` (formulario web)

Todos llaman `sp_ins_lectura_gps` → triggers PostgreSQL:
- `trg_bateria_baja_gps` → alerta *Batería crítica* si nivel ≤ 15 %
- `trg_zona_exit_gps` → alerta *Salida de Zona* si punto fuera de geocercas

**Polling del mapa:** `GET /api/gps/ultima/<id_paciente>` — devuelve última posición + estado de zona. El portal familiar llama este endpoint cada 8 s para actualizar el marcador Leaflet sin recargar la página.

### BLE Beacon (cuidadores)

- `beacon_scanner.py` escanea iBeacons y reporta a `POST /api/beacon/deteccion`
- Identifica cuidadores por UUID-major-minor del beacon
- Cooldown de 10 s por beacon para evitar spam

### NFC (pulsera del paciente)

- `POST /api/nfc/lectura` — registra administración de medicamento
- Página de prueba: `/test/nfc`

---

## Mapa — Leaflet.js

El mapa GPS está en `templates/portal_familiar/paciente.html`. Es **no interactivo** (solo visual):
- Tiles: OpenStreetMap
- Geocercas: `L.circle` verde para cada zona segura
- Marcador: punto verde (dentro de zona) o rojo (fuera)

El polling automático actualiza el marcador cada 8 s vía `fetch('/api/gps/ultima/<id>')` y mueve el mapa con `map.panTo()`.

---

## Gráficas — Highcharts

Se usa Highcharts para el sparkline de batería GPS en el portal familiar (`chart-bateria-sparkline`). Los datos vienen de `sp_sel_bateria_historial_gps`.

---

## Variables de entorno (.env)

```
SECRET_KEY=...
DB_HOST=localhost
DB_PORT=5432
DB_NAME=alzheimer
DB_USER=alzadmin
DB_PASSWORD=...
MONGO_URI=mongodb://localhost:27017/
MONGO_DB=alzmonitor
```

---

## Comandos útiles

```bash
# Levantar servidor principal
python app.py

# Escáner BLE (requiere hardware + bleak)
python beacon_scanner.py

# Instalar dependencias
pip install -r requirements.txt
```

---

## Convenciones de código

- Los SPs de SELECT se nombran `sp_sel_*`, los de INSERT `sp_ins_*`, los CALL directos con `db.execute("CALL sp_*")`.
- Los blueprints importan `db` y `mongo` directamente (no via app context).
- El banner de alertas críticas se inyecta globalmente vía `@app.context_processor` en `app.py`.
- Los reportes PDF se generan en `pdf_report.py` con ReportLab.
