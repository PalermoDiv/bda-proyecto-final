# AlzMonitor

A multi-tenant clinical management system for Alzheimer's patients, built as the final project for an Advanced Databases (BDA) university course. The system integrates PostgreSQL with PostGIS, stored procedures, database triggers, and a three-layer IoT architecture (GPS, BLE Beacons, NFC wristbands) to provide real-time patient safety monitoring across multiple clinical facilities.

---

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Backend | Python 3.11 · Flask |
| Database | PostgreSQL 15 · PostGIS |
| ORM | None — raw SQL via `psycopg2` with `RealDictCursor` |
| PDF generation | ReportLab |
| Frontend | Jinja2 · Vanilla JS · CSS custom properties |
| IoT protocols | GPRS/4G GPS · Bluetooth 5.1 BLE · ISO 14443A NFC |
| Maps | Leaflet.js (family portal only) |
| Transport | HTTPS (self-signed TLS, required for Web NFC/Bluetooth APIs) |

---

## Setup

### Prerequisites

- Python 3.10+
- PostgreSQL 14+ with PostGIS extension
- `brew install postgis` (macOS) or equivalent

### Installation

```bash
# 1. Install Python dependencies
pip install -r requirements.txt

# 2. Create the database and apply the schema
psql -U palermingoat -d alzheimer -f ProyectoFinalDDL.sql

# 3. Apply stored procedures
psql -U palermingoat -d alzheimer -f RecetasProcedures.sql

# 4. Apply database triggers
psql -U palermingoat -d alzheimer -f TriggersDB.sql

# 5. Start the development server
python app.py
# Serves at https://localhost:5002 (TLS cert auto-generated on first run)
```

### Environment Variables (`.env`)

```
DB_HOST=/tmp
DB_NAME=alzheimer
DB_USER=palermingoat
DB_PASS=
ADMIN_USER=admin
ADMIN_PASS=admin123
MEDICO_USER=medico
MEDICO_PASS=medico123
SECRET_KEY=<flask-secret>
```

### Demo Credentials

| Role | Username | Password | Entry point |
|------|----------|----------|-------------|
| Administrator | `admin` | `admin123` | `/dashboard` |
| Clinical staff | `medico` | `medico123` | `/clinica` |
| Family portal | `lucia.garcia@demo.com` | `1234` (PIN) | `/portal-familiar/login` |

---

## Project Structure

```
app.py                        Route handlers (flat, no blueprints)
db.py                         PostgreSQL connection helpers
pdf_report.py                 Patient PDF report generator (ReportLab)
data.py                       Legacy in-memory stubs (partially migrated)

ProyectoFinalDDL.sql          Full schema DDL — 43 tables + seed data
RecetasProcedures.sql         10 stored procedures (receta/NFC module)
TriggersDB.sql                3 database triggers (GPS zone exit, battery low, beacon coverage)
ProcedimientosAlmacenados.sql Academic convention rewrite + 3 REFCURSOR procedures (reference only)
finalqueries.sql              Advanced analytical queries

static/
  css/main.css                Global stylesheet (CSS custom properties, teal palette)
  js/main.js                  Alert auto-dismiss and delete confirmations (25 lines)

templates/
  base.html                   Admin layout — sticky 248px sidebar
  login.html                  Admin/medico login (immersive dark background)
  dashboard.html              Global stats, per-sede counters, live alerts feed
  alertas.html / alertas_form.html
  dispositivos.html / dispositivos_form.html
  zonas.html / zonas_form.html
  farmacia.html / farmacia_suministro_*.html
  visitas.html / visitas_form.html
  recetas.html / recetas_form.html / recetas_detalle.html
  reportes.html
  procedimientos.html         SP guide (all 10 procedures, parameters, CALL syntax)
  sim_gps.html                GPS simulator for trigger demo
  clinica.html / clinica_sedes.html
  pacientes/
    list.html / form.html / historial.html
  cuidadores/
    list.html / form.html
  turnos/
    list.html / form.html
  cuidador/
    escanear.html             Mobile caregiver scanner (Web NFC + Web Bluetooth)
  portal_familiar/
    base_familiar.html        Family portal layout (mobile-first, no sidebar)
    login.html                Two-column split card login
    paciente.html             Patient detail (map, medications, caregivers, alerts)
```

---

## Database Design

### Schema overview

The schema is organized into logical blocs in `ProyectoFinalDDL.sql`:

| Bloc | Tables |
|------|--------|
| Catalog tables | `estados_paciente`, `cat_tipo_dispositivo`, `cat_tipo_alerta`, `cat_estado_alerta`, `cat_estado_suministro`, `cat_estado_entrega`, `cat_turno_comedor` |
| People | `pacientes`, `empleados`, `cuidadores`, `cocineros`, `contactos_emergencia`, `paciente_contactos`, `visitantes` |
| Facilities | `sedes`, `sede_pacientes`, `sede_empleados`, `sede_zonas` |
| Clinical | `enfermedades`, `tiene_enfermedad`, `visitas`, `entregas_externas`, `bitacora_comedor` |
| IoT devices | `dispositivos`, `asignacion_kit`, `asignacion_nfc`, `zonas`, `beacon_zona`, `turno_cuidador` |
| IoT events | `lecturas_gps`, `detecciones_beacon`, `lecturas_nfc` |
| Alerts | `alertas`, `alerta_evento_origen` |
| Pharmacy | `medicamentos`, `inventario_medicinas`, `farmacias_proveedoras`, `suministros`, `suministro_medicinas` |
| Prescriptions | `recetas`, `receta_medicamentos`, `receta_nfc` |
| Shifts | `asignacion_cuidador` |

### Key design decisions

**Soft deletes for patients** — `pacientes.id_estado = 3` marks a patient as discharged without losing any FK-referenced history (alerts, visits, GPS readings, prescriptions all stay intact).

**Sede history** — `sede_pacientes` has `fecha_salida` for temporal tracking. A partial unique index (`WHERE fecha_salida IS NULL`) enforces that a patient can only have one active sede. Transferring a patient is a two-statement atomic operation: close the current row and insert a new one.

**IoT event traceability** — `alerta_evento_origen` links each alert to the raw IoT event that triggered it (`tipo_evento IN ('GPS', 'NFC', 'SOS')`), with a `regla_disparada` text description. This enables forensic reconstruction of why any alert was raised.

**Geography types** — `zonas.geom` and `lecturas_gps.geom` are `GEOGRAPHY(Point, 4326)`. Zone boundary checks use PostGIS `ST_DWithin(point, zone_center, radius_meters)` which correctly accounts for Earth's curvature. GIST indexes on both columns.

**Catalog tables instead of CHECK constraints** — all enumerated values are FK-constrained to catalog tables (e.g., `cat_tipo_alerta`) rather than inline CHECK constraints, enabling `ON UPDATE CASCADE` and maintainability.

**Prescription-NFC link** — `receta_nfc` is a history table (not a simple FK on `recetas`). A device can be swapped mid-treatment; each row has `fecha_inicio_gestion`/`fecha_fin_gestion` so the full wristband history is preserved.

---

## Stored Procedures

All 10 procedures are in `RecetasProcedures.sql` and are applied to the live database. Every mutation to the receta/NFC module goes through a stored procedure rather than raw SQL to enforce business rules at the database level.

| Procedure | What it enforces |
|-----------|-----------------|
| `sp_receta_crear` | Patient must exist and not be discharged |
| `sp_receta_agregar_medicamento` | Receta must be Activa; no duplicate GTIN |
| `sp_receta_quitar_medicamento` | Receta must be Activa; operates on `id_detalle` |
| `sp_receta_actualizar_medicamento` | Receta must be Activa; `frecuencia_horas > 0` |
| `sp_receta_activar_nfc` | Device must be type NFC; receta must not have an active NFC link already |
| `sp_receta_cerrar_nfc` | Active link between this receta and this device must exist |
| `sp_receta_cambiar_nfc` | New device must be type NFC; atomically closes old link and opens new one |
| `sp_nfc_registrar_lectura` | Active receta-NFC link must exist; validates `tipo_lectura` and `resultado` values |
| `sp_receta_cerrar` | Closes all active NFC links; preserves history (no DELETE) |
| `sp_nfc_asignar` | Closes any prior assignment for patient or device before creating new one |

An interactive guide to all procedures — with parameter tables, trigger location links, and copyable CALL syntax — is available at `GET /procedimientos` (admin role required).

---

## Database Triggers

Three triggers are defined in `TriggersDB.sql`:

### `trg_cobertura_zona` — Beacon coverage monitoring

Fires `AFTER INSERT ON detecciones_beacon`. Iterates all zones that have an active `turno_cuidador` shift at the time of the new detection. For each such zone, checks whether any caregiver has been detected in the last 30 minutes (`id_cuidador IS NOT NULL`). If not, inserts a `'Zona sin cobertura'` alert. Deduplication prevents multiple alerts for the same zone within a 2-hour window.

### `trg_bateria_baja_gps` — Battery alert

Fires `AFTER INSERT ON lecturas_gps`. If `nivel_bateria ≤ 15`, resolves the patient via `asignacion_kit WHERE fecha_fin IS NULL` and inserts a `'Batería Baja'` alert plus an `alerta_evento_origen` row with the exact battery percentage. Dedup window: 2 hours.

### `trg_zona_exit_gps` — GPS zone exit

Fires `AFTER INSERT ON lecturas_gps`. Uses PostGIS `ST_DWithin` to test whether the reading falls inside any of the patient's active sede zones. If the patient is outside all zones, inserts a `'Salida de Zona'` alert plus an `alerta_evento_origen` row listing the zone names and the exact coordinates. Dedup window: 1 hour.

---

## IoT Architecture

```
                 ┌──────────────────────────────────┐
                 │           PostgreSQL              │
                 │                                  │
  GPS tracker ──►│  lecturas_gps                    │
  (PG12 / API)   │    └─ trg_zona_exit_gps ─────────┤──► alertas
                 │    └─ trg_bateria_baja_gps ───────┤──► alerta_evento_origen
                 │                                  │
  BLE Beacon ───►│  detecciones_beacon              │
  (caregiver     │    └─ trg_cobertura_zona ─────────┤──► alertas
   phone scan)   │                                  │
                 │  lecturas_nfc                    │
  NFC wristband ►│    └─ sp_nfc_registrar_lectura   │
  (caregiver tap)│         (validates active link)  │
                 └──────────────────────────────────┘
```

**Layer 1 — GPS (safety-critical):** The PG12 tracker pushes readings to a cloud endpoint. The app polls that endpoint and POSTs to `POST /api/gps/lectura`, which inserts into `lecturas_gps`. Both GPS triggers fire automatically on every insert. No application code is needed for zone checking — it is entirely in the database.

**Layer 2 — BLE Beacons (indoor rounds):** Beacons are building-fixed, not patient-worn. A caregiver opens `/cuidador/escanear` on their Android phone. The Web Bluetooth API scans for nearby beacons and POSTs the detection to `POST /api/beacon/deteccion`. The coverage trigger checks zone staffing.

**Layer 3 — NFC wristbands (medication adherence):** Each patient wears an NFC DESFire wristband. At medication time, a caregiver taps their Android phone to the wristband via the Web NFC API on `/cuidador/escanear`. The app POSTs to `POST /api/nfc/lectura`, which resolves the device by serial, finds the linked active prescription, and calls `sp_nfc_registrar_lectura`.

All three endpoints accept authentication via session (`admin`/`medico`) or the `X-AlzMonitor-Key` header for device-to-server calls.

### GPS Simulator

For demo and development without physical hardware, `GET /sim/gps` provides an admin form to insert GPS readings directly. The form shows all zones with their center coordinates as clickable references. Submitting a reading with `nivel_bateria ≤ 15` or coordinates outside the configured zones demonstrates both GPS triggers firing in real time.

---

## API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/api/gps/lectura` | IoT key / session | Insert GPS reading; fires zone-exit + battery triggers |
| `POST` | `/api/nfc/lectura` | IoT key / session | Register NFC medication tap; resolves by `serial` or `id_dispositivo` |
| `POST` | `/api/beacon/deteccion` | IoT key / session | Log caregiver beacon round; resolves by `serial` or `id_beacon` |
| `GET` | `/api/test/nfc` | None | Development NFC tag lookup (returns device + linked patient) |

**`POST /api/nfc/lectura` — smart resolution:**
```json
// Option A — direct IDs
{ "id_dispositivo": 3, "id_receta": 42, "tipo_lectura": "Administración", "resultado": "Exitosa" }

// Option B — from caregiver scanner (serial lookup + auto receta resolution)
{ "serial": "04:AB:CD:EF:01:02", "tipo_lectura": "Administración", "resultado": "Exitosa" }
```

---

## Application Roles

### Administrator (`/dashboard`)

Full CRUD access to all entities across all facilities. Key capabilities:

- **Patients** — create (with initial sede assignment), edit, soft-delete, transfer between sedes, view full historial (diseases, caregivers, emergency contacts, GPS kit, sede history, alerts, visits)
- **Prescriptions** — create and manage medications; assign/change/deactivate NFC wristband; view 30-day adherence percentage per medication
- **Alerts** — full list with IoT origin badge, rule description, and priority contact info; mark as attended
- **Zones** — list with active patients and priority contact for each zone
- **GPS Simulator** — inject readings to demo triggers without hardware
- **Procedures guide** — `GET /procedimientos` shows all stored procedures with parameters and CALL syntax

### Clinical Staff (`/clinica`)

Read-only, scoped to a specific sede. Views patients, assignments, active shifts, and alerts for that facility.

### Family Portal (`/portal-familiar`)

Mobile-first single-page view per patient. Scoped to the patient(s) linked to the contact via `paciente_contactos`. Shows:

1. **Status banner** — green (ok) / red pulsing (active critical alert) / amber (no data >2h)
2. **GPS map** — Leaflet map with zone circles and patient's last known position
3. **Today's medications** — NFC confirmation status per medication, adherence progress bar
4. **On-duty caregivers** — tap-to-call button per caregiver
5. **Recent alerts** — last 30 days, active in red / attended in gray
6. **Recent visits**

---

## Data Access Layer

`db.py` wraps a connection pool and exposes four functions, all using `psycopg2.extras.RealDictCursor`:

```python
db.query(sql, params)        # → list[dict]  — for SELECT returning multiple rows
db.one(sql, params)          # → dict | None — for SELECT returning one row
db.scalar(sql, params)       # → any         — for SELECT returning one value
db.execute(sql, params)      # → None        — for INSERT/UPDATE/DELETE (auto-commit)
db.execute_many([(sql, p)])  # → None        — multiple statements in one transaction
```

All mutations that touch more than one table use `execute_many` for atomicity (e.g., patient creation inserts into `pacientes` + `sede_pacientes` in a single call).

---

## PDF Reports

`GET /pacientes/<id>/reporte-pdf` streams a PDF generated by `pdf_report.py` using ReportLab. The report includes:

- Patient identity and current status
- Assigned GPS kit and last battery reading
- Active diagnoses
- Assigned caregivers
- Emergency contacts with priority order
- Alert history (last 30 days)
- Medication adherence by NFC (last 7 days)
- Last 10 GPS readings with coordinates

---

## Demo Scenarios (Academic Requirements)

| # | Scenario | Status |
|---|----------|--------|
| 1 | Zone exit detection and escalation | 🟡 Triggers + UI complete; GPS polling loop pending |
| 2 | Sede transfer without data loss | ✅ Complete |
| 3 | Treatment change and NFC adherence | ✅ Complete |
| 4 | Battery failure and kit replacement | 🟡 Battery trigger complete; kit reassignment UI pending |
| 5 | Critical multi-sede pharmacy supply | ✅ Complete |
