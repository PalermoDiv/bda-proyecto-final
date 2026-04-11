# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AlzMonitor** is an academic Flask web app for managing Alzheimer's patients across multiple clinical facilities. Built for an Advanced Databases (BDA) university course to demonstrate multi-tenant clinical data modeling.

## Running the App

```bash
pip install -r requirements.txt
python app.py
# Runs at http://localhost:5002
```

Apply the corrected schema to the database:
```bash
psql -U palermingoat -d alzheimer -f ProyectoFinalDDL.sql
```

> **Known DDL ordering issue**: `lecturas_nfc` is defined before `recetas` in the file, so its FK constraint fails on a fresh run. After running the DDL, manually create it:
> ```sql
> CREATE TABLE IF NOT EXISTS lecturas_nfc (
>     id_lectura_nfc INTEGER PRIMARY KEY,
>     id_dispositivo INTEGER NOT NULL,
>     id_receta      INTEGER NOT NULL,
>     fecha_hora     TIMESTAMP NOT NULL,
>     tipo_lectura   VARCHAR(30) NOT NULL DEFAULT 'Administración',
>     resultado      VARCHAR(20) NOT NULL DEFAULT 'Exitosa',
>     CONSTRAINT fk_lnfc_dispositivo FOREIGN KEY (id_dispositivo) REFERENCES dispositivos(id_dispositivo) ON DELETE RESTRICT,
>     CONSTRAINT fk_lnfc_receta      FOREIGN KEY (id_receta)      REFERENCES recetas(id_receta)            ON DELETE RESTRICT,
>     CONSTRAINT uq_lnfc_instante    UNIQUE (id_dispositivo, id_receta, fecha_hora)
> );
> ```

Test credentials (defined in `.env`):
- Admin: `admin` / `admin123`
- Medical staff: `medico` / `medico123`
- Portal Familiar (demo): any contact email from seed data / PIN `1234`
  - e.g. `lucia.garcia@demo.com` / `1234`

## Architecture

### Data Layer
**Primary data source is PostgreSQL** (`alzheimer` DB, user `palermingoat`, empty password, Unix socket via `DB_HOST=/tmp`). `db.py` provides four helpers: `query()`, `one()`, `scalar()`, `execute()`, `execute_many()` — all use `RealDictCursor` so results are dict-compatible.

`data.py` is still imported for a small set of in-memory structures not yet migrated: `TURNOS_HOY`, `TAREAS_HOY`, `MEDICAMENTOS`, `BITACORAS`, `INCIDENTES`, `PERFIL_CLINICO`, `BITACORA_COMEDOR`, `ALERTAS_MEDICAS`, `ASIGNACIONES_CUIDADORES`.

Multi-facility filtering is done at the route level using `id_sede` (maps to `id_sucursal` in templates).

### Route Organization
All routes are flat in `app.py` — no blueprints. Three auth decorators defined at module level:
- `admin_requerido` — checks `session["admin"]`
- `medico_requerido` — checks `session["medico"]`
- `contacto_requerido` — checks `session["contacto_id"]`; redirects to `/portal-familiar/login`

Three roles:
- `admin` — full CRUD, all sedes, admin panel with sidebar
- `medico` — clinic-scoped read view under `/clinica`
- `contacto` — read-only family portal under `/portal-familiar`; scoped to their linked patients only via `paciente_contactos`

Helper defined at module level: `_haversine_m(lat1, lon1, lat2, lon2)` — returns distance in metres between two WGS-84 coordinates (used in portal familiar for inside-zone check without PostGIS).

### Templates
`templates/base.html` is the master layout for the admin panel — sticky 248px sidebar. All admin/medico pages extend it. Patient and caregiver templates live in `templates/pacientes/` and `templates/cuidadores/` subdirectories. Turno templates live in `templates/turnos/`.

`templates/portal_familiar/base_familiar.html` is the separate master layout for the family portal — no sidebar, mobile-first, soft teal theme. All portal pages extend it.

SQL aliases map real DB column names to the names templates expect (e.g. `nombre AS nombre_paciente`, `apellido_p AS apellido_p_pac`). Date columns used with string slicing in templates are returned via `TO_CHAR(col, 'YYYY-MM-DD')`.

### Frontend
Vanilla JS only (`static/js/main.js`, 25 lines) — handles auto-dismiss alerts and deletion confirmations. No build step, no bundler. The portal familiar patient detail page loads Leaflet.js via CDN for the GPS map — no other JS libraries used anywhere.

## IoT Hardware

| Role | Model | Technology | Carried by |
|------|-------|-----------|------------|
| GPS | PG12 GPS Tracker — Luejnbogty | GPRS/4G + GPS | Patient (hidden in clothing) |
| Beacon | FeasyBeacon FSC-BP104D Waterproof | Bluetooth 5.1 BLE | Fixed to building walls/ceilings |
| NFC | NFC DESFire wristband | ISO 14443A (passive) | Patient (wristband, no battery) |

Full integration plan is in `DEVICES.md`. **GPS is the central safety mechanism.**

### Three-layer architecture
- **Layer 1 — GPS (outdoor/critical):** Flask polls PG12 cloud API every 30–60s. Events stored in MongoDB `gps_events`. Zone check via PostGIS `ST_DWithin`. Outside all zones → PostgreSQL `alertas` + `alerta_evento_origen`.
- **Layer 2 — BLE Beacon (indoor/caregiver rounds):** Beacons are building-fixed (NOT patient-worn). Caregiver's Android phone scans via Web Bluetooth API, POSTs to Flask. Events stored in MongoDB `ble_events`. Logs caregiver rounds, not patient location. No BLE gateways needed.
- **Layer 3 — NFC (checkpoint/medication adherence):** Caregiver taps phone to patient's NFC wristband via Web NFC API. POSTs to Flask. Events stored in PostgreSQL `lecturas_nfc` (low volume, FK to `recetas`).

### Device-to-database routing
| Device | Endpoint | Database |
|--------|----------|----------|
| PG12 GPS | Flask polls cloud API | MongoDB `gps_events` → PostGIS → PostgreSQL `alertas` |
| FeasyBeacon | `POST /api/beacon/deteccion` | MongoDB `ble_events` |
| NFC wristband | `POST /api/nfc/lectura` | PostgreSQL `lecturas_nfc` |

**HTTPS required** for caregiver webapp (Web Bluetooth + Web NFC need secure context). Web NFC is Chrome Android only.

## Advanced Queries — finalqueries.sql

All advanced queries are complete in `finalqueries.sql`:
- `ORDER BY total_salidas_zona DESC` (was ASC — corrected)
- Last-location query uses `DISTINCT ON (id_dispositivo) ORDER BY fecha_hora DESC, id_lectura DESC`
- Adherence query rewritten to use `lecturas_nfc` instead of `detecciones_beacon`
- `ACOS()` wrapped with `LEAST(1, GREATEST(-1, ...))` to prevent domain errors
- Analytical queries added: temporal alert trends, MTTA, time-outside-zone per patient, SLA by sede

**Do not re-fix these — they are already done.**

## Schema — ProyectoFinalDDL.sql

The corrected DDL (`ProyectoFinalDDL.sql`) incorporates changes from the professor's feedback and subsequent development:

1. **Removed `paciente_recetas`** — `recetas.id_paciente` is the single source of truth.
2. **Catalog tables replace CHECK literals** — `cat_tipo_dispositivo` (`GPS`, `BEACON`, `NFC`), `cat_estado_dispositivo` (`Activo`, `Inactivo`, `Mantenimiento`), `cat_tipo_alerta` (`Salida de Zona`, `Batería Baja`, `Botón SOS`, `Caída`, `Zona sin cobertura`), `cat_estado_alerta` (`Activa`, `Atendida`), `cat_estado_suministro`, `cat_estado_entrega`, `cat_turno_comedor`.
3. **`alerta_evento_origen`** — links each alert to the IoT event that triggered it. **`lecturas_nfc`** separated from `detecciones_beacon` (NFC = medication adherence, Beacon = location/presence).
4. **`beacon_zona`** — links each fixed beacon device to the zone where it is installed (replaces the removed `zona_beacons`/`gateways` approach). One row per beacon.
5. **`turno_cuidador`** — weekly recurring shifts: `id_cuidador`, `id_zona`, `hora_inicio`, `hora_fin`, seven boolean day columns (`lunes`…`domingo`), `activo`. A cuidador can cover multiple zones.
6. **`detecciones_beacon.id_cuidador`** — nullable FK to `cuidadores`; identifies which caretaker's phone made the detection during a round.
7. **`alertas`** — `id_paciente` is now nullable (zone-level alerts have no specific patient). New nullable `id_zona` FK for zone alerts generated by the coverage trigger.
8. **`contactos_emergencia`** — added `email VARCHAR(100) UNIQUE` and `pin_acceso VARCHAR(20)` for portal familiar authentication.

### Pending: Coverage trigger (commented out in DDL BLOQUE 11)
`fn_verificar_cobertura_zona()` + `trg_cobertura_zona` are fully written but commented out. The trigger fires `AFTER INSERT ON detecciones_beacon`, checks all zones with active shifts for 30-min caretaker absence, and inserts a `'Zona sin cobertura'` alert. Uncomment BLOQUE 11 to activate.

Key schema facts:
- `pacientes.id_estado` is an integer FK → `estados_paciente` (1=Activo, 2=En Hospital, 3=Baja). Soft-delete sets `id_estado = 3`.
- Battery is in `lecturas_gps.nivel_bateria`, not on `dispositivos`. (GPS battery also tracked in MongoDB `gps_events.battery`.)
- `empleados` has no `id_sede` — linked via `sede_empleados` bridge table.
- `asignacion_kit` links one patient to one GPS device (beacon assignment per patient is deprecated — beacons are building-fixed).
- `contactos_emergencia` linked via `paciente_contactos` bridge table.
- `sede_pacientes` uses `fecha_salida`/`hora_salida` (not `fecha_fin`). Partial unique index `uq_sede_activa_por_paciente` enforces one active sede per patient.
- `alertas.estatus` is the column name (not `estado`). Values: `'Activa'`, `'Atendida'`.
- `cat_tipo_alerta.tipo_alerta` is a VARCHAR primary key — there is no `id_tipo_alerta` integer column.
- `recetas` has no `estado` column — all recetas for a patient are considered active.
- `medicamentos.nombre_medicamento` (not `nombre`).

## Key Behaviors

- **Dispositivo registration**: `id_dispositivo` must be supplied manually (no SERIAL). `estado` defaults to `'Activo'`. Tipo must be exactly `GPS`, `BEACON`, or `NFC`.
- **Cuidador deletion**: deletes from `cuidadores` then `empleados` in a single transaction (FK dependency).
- **Paciente deletion**: soft-delete only — `UPDATE pacientes SET id_estado = 3`.
- **Alerta status values**: `'Activa'` and `'Atendida'` (not `'Resuelta'`). `id_paciente` may be NULL for zone-level alerts.
- **Sede transfer**: `POST /pacientes/<id>/transferir-sede` closes the active `sede_pacientes` row (`fecha_salida = CURRENT_DATE`) and inserts a new one in a single `execute_many` transaction. Guards against same-sede transfers and detects schema corruption (>1 active row).
- **Turno management**: `id_turno` must be supplied manually. Day coverage uses individual boolean columns; `activo` flag disables a shift without deleting it.
- **Portal familiar login**: looks up `contactos_emergencia` by `LOWER(email)` + `pin_acceso`. Session keys are `contacto_id` and `contacto_nombre` — completely separate from admin/medico sessions.
- **Portal familiar security**: every `/portal-familiar/paciente/<id>` request verifies the contact-patient link in `paciente_contactos` before loading any data; returns `abort(403)` if not found.

## What the App Can and Cannot Do

### Pacientes
- **Can**: List active patients (id_estado != 3) with sede; create new patient (manual ID required); edit name, DOB, estado; soft-delete (sets id_estado = 3).
- **Can**: View patient historial — enfermedades, assigned cuidadores, contactos de emergencia, assigned IoT kit (GPS serial), full sede history (all `sede_pacientes` rows ordered by `fecha_ingreso DESC`), all alerts, visit history, external deliveries.
- **Can**: Transfer patient to a new sede via `POST /pacientes/<id>/transferir-sede` — closes active record, opens new one atomically.
- **Cannot**: Assign a patient to a sede from the creation form (no UI for INSERT into `sede_pacientes`); link diseases (`tiene_enfermedad`) from the UI; add emergency contacts (`paciente_contactos`) from the UI; assign an IoT kit (`asignacion_kit`) from the UI.

### Cuidadores
- **Can**: List cuidadores with their sede; create (inserts into both `empleados` and `cuidadores` in one transaction); edit name/phone/CURP; hard-delete (removes from `cuidadores` then `empleados`).
- **Cannot**: Assign a cuidador to a patient (`asignacion_cuidador`) from the UI; assign a cuidador to a sede (`sede_empleados`) from the UI.

### Turnos
- **Can**: List all shifts grouped by zone; create new shift (manual ID, select cuidador, zona, hora_inicio, hora_fin, days); edit all fields including `activo` toggle; delete shift.
- **Cannot**: Assign a shift to a sede directly — zones are linked to sedes via `sede_zonas`.

### Alertas
- **Can**: List all alerts with patient name (or zone name for coverage alerts) and sede; create new alert (manual ID, pick patient + type + datetime); mark alert as `Atendida`; hard-delete alert.
- **Cannot**: Link an alert to its triggering IoT event (`alerta_evento_origen`) from the UI.

### Dispositivos
- **Can**: List devices with last GPS battery level and assigned patient; create new device (manual ID, serial, tipo GPS/BEACON/NFC, modelo — estado defaults to `Activo`); edit serial/tipo/modelo/estado; hard-delete.
- **Cannot**: Assign a device to a patient kit (`asignacion_kit`) from the UI; assign a beacon to a zone (`beacon_zona`) from the UI; view GPS location history or beacon detections from the UI.

### Zonas Seguras
- **Can**: List zonas with sede, coordinates, and radius; create new zona (nombre, latitud, longitud, radio); edit; hard-delete.
- **Cannot**: Link a zona to a sede (`sede_zonas`) from the UI after creation.

### Farmacia
- **Can**: View full medicine inventory per sede with stock vs minimum; highlight critical stock (below minimum); adjust stock inline (UPDATE `inventario_medicinas`); create a new supply order (`suministros`) linked to a pharmacy provider and sede.
- **Cannot**: Add medicines to a supply order (`suministro_medicinas` detail lines) from the UI; add/edit/delete `farmacias_proveedoras` from the UI; add/edit `medicamentos` catalog from the UI; manage `entregas_externas` from the farmacia module.

### Visitas
- **Can**: List today's visits and last 50 historical visits; list recent external deliveries; register a new visit (links existing `visitantes` to a patient + sede with date/time).
- **Cannot**: Create a new `visitante` (visitor) from the UI — must exist in DB already; register visit departure time (hora_salida) from the UI; register an `entrega_externa` from the UI.

### Portal Clínico (rol: médico)
- **Can**: View sede list with active patient count; view per-sede dashboard with patient list, their enfermedades, cuidador assignments, IoT kit, active alerts count, and zone coverage (live from `turno_cuidador`).
- **Cannot**: Edit or create anything — read-only role.

### Portal Familiar (rol: contacto)
- **Can**: Log in with email + PIN; see a list of their linked patients; view per-patient detail with: last GPS location on a Leaflet map with zone circles, active alerts, alert history (30 days), medication list with NFC adherence count today, recent visits, last caregiver round timestamp.
- **Cannot**: Edit, create, or delete anything; see patients they are not linked to via `paciente_contactos`; access any admin or medico functionality.

### Sedes
- **No admin CRUD UI** — the 3 sedes seeded by the DDL are fixed. There is no route to create, edit, or delete sedes.

### Tables with No UI at All
The following DB tables exist in the schema but have zero admin CRUD routes:
`lecturas_gps`, `detecciones_beacon`, `lecturas_nfc`, `recetas`, `receta_medicamentos`, `receta_nfc`, `tiene_enfermedad`, `enfermedades`, `asignacion_kit`, `asignacion_cuidador`, `sede_empleados`, `sede_zonas`, `bitacora_comedor`, `cocineros`, `alerta_evento_origen`, `entregas_externas`, `visitantes`.

Note: `beacon_zona` and `turno_cuidador` have admin CRUD. `sede_pacientes` is managed indirectly via the sede transfer route. `contactos_emergencia` and `paciente_contactos` are read via the portal familiar but have no admin CRUD.

---

## Design System

CSS variables in `static/css/main.css`:
- Primary teal: `#0E7490` / Dark bg: `#082F3E`
- Status colors: emerald (success), amber (warning), rose (danger), sky (info)

Portal familiar uses the same teal palette but with a softer background (`#F0F9FF`) and no sidebar. Styles are inline in `base_familiar.html`.

UI is entirely in Spanish.
