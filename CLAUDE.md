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

Apply the schema from scratch:
```bash
psql -U palermingoat -d alzheimer -f ProyectoFinalDDL.sql
```

Requires PostGIS installed (`brew install postgis`) — the DDL runs `CREATE EXTENSION IF NOT EXISTS postgis`.

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

Helper defined at module level: `_haversine_m(lat1, lon1, lat2, lon2)` — returns distance in metres between two WGS-84 coordinates (used in portal familiar for inside-zone check; the API layer uses PostGIS `ST_DWithin` instead).

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
- **Layer 1 — GPS (outdoor/critical):** Flask polls PG12 cloud API every 30–60s. Zone check via PostGIS `ST_DWithin` on `lecturas_gps.geom` vs `zonas.geom`. Outside all zones → PostgreSQL `alertas` + `alerta_evento_origen`.
- **Layer 2 — BLE Beacon (indoor/caregiver rounds):** Beacons are building-fixed (NOT patient-worn). Caregiver's Android phone scans via Web Bluetooth API, POSTs to `POST /api/beacon/deteccion`. Logs caregiver rounds, not patient location. No BLE gateways needed.
- **Layer 3 — NFC (medication adherence):** Caregiver taps phone to patient's NFC wristband via Web NFC API. POSTs to `POST /api/nfc/lectura`. Events stored in PostgreSQL `lecturas_nfc` (FK to `recetas`).

**HTTPS required** for caregiver webapp (Web Bluetooth + Web NFC need secure context). Web NFC is Chrome Android only.

## Advanced Queries — finalqueries.sql

All advanced queries are complete in `finalqueries.sql`. **Do not re-fix these — they are already done.**

## Schema — ProyectoFinalDDL.sql

Key schema facts:
- `pacientes.id_estado` is an integer FK → `estados_paciente` (1=Activo, 2=En Hospital, 3=Baja). Soft-delete sets `id_estado = 3`.
- Battery is in `lecturas_gps.nivel_bateria`, not on `dispositivos`.
- `empleados` has no `id_sede` — linked via `sede_empleados` bridge table.
- `asignacion_kit` links one patient to one GPS device. Has `fecha_fin DATE` for historical records. Partial indexes `uq_kit_activo_por_paciente` and `uq_gps_activo` both use `WHERE fecha_fin IS NULL`. **Any app.py query joining `asignacion_kit` must add `AND ak.fecha_fin IS NULL`** to avoid returning historical rows — currently 4 queries (around lines 137, 370, 848, 1701) lack this filter.
- `contactos_emergencia` linked via `paciente_contactos` bridge table.
- `sede_pacientes` uses `fecha_salida`/`hora_salida` (not `fecha_fin`). Partial unique index `uq_sede_activa_por_paciente` enforces one active sede per patient.
- `alertas.estatus` is the column name (not `estado`). Values: `'Activa'`, `'Atendida'`. `id_paciente` may be NULL for zone-level alerts.
- `cat_tipo_alerta.tipo_alerta` is a VARCHAR primary key — there is no `id_tipo_alerta` integer column.
- `recetas.estado` VARCHAR(20), default `'Activa'`. Values: `'Activa'`, `'Cerrada'`.
- `medicamentos.nombre_medicamento` (not `nombre`).
- `zonas.geom` and `lecturas_gps.geom` are `GEOGRAPHY(Point, 4326)`, populated from lat/lon via `ST_SetSRID(ST_MakePoint(...))`. GIST indexes on both.

### DDL block order (BLOQUE 5 → 6)
BLOQUE 5 = RECETAS Y MEDICACIÓN (`recetas`, `receta_medicamentos`, `receta_nfc`).
BLOQUE 6 = EVENTOS Y ALERTAS (`lecturas_gps`, `detecciones_beacon`, `lecturas_nfc`, `alertas`, `alerta_evento_origen`).
`lecturas_nfc` has a FK to `recetas`, so recetas must be defined first — this ordering is correct.

### Pending: Coverage trigger (commented out in DDL BLOQUE 11)
`fn_verificar_cobertura_zona()` + `trg_cobertura_zona` are fully written but commented out. Fires `AFTER INSERT ON detecciones_beacon`, checks all zones with active shifts for 30-min caretaker absence, inserts a `'Zona sin cobertura'` alert. Uncomment BLOQUE 11 to activate.

## Stored Procedures — RecetasProcedures.sql

`RecetasProcedures.sql` contains 8 stored procedures for the receta/NFC module:
- `sp_receta_crear` — creates a new recipe for a patient
- `sp_receta_agregar_medicamento` / `sp_receta_quitar_medicamento` / `sp_receta_actualizar_medicamento`
- `sp_receta_activar_nfc` / `sp_receta_cerrar_nfc` / `sp_receta_cambiar_nfc`
- `sp_nfc_registrar_lectura` — inserts into `lecturas_nfc` (validates active NFC-receta link)
- `sp_receta_cerrar` — closes all active NFC links for a recipe

Apply with: `psql -U palermingoat -d alzheimer -f RecetasProcedures.sql`

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
- **Can**: View patient historial — enfermedades, assigned cuidadores, contactos de emergencia, assigned IoT kit (GPS serial), full sede history, all alerts, visit history, external deliveries.
- **Can**: Transfer patient to a new sede via `POST /pacientes/<id>/transferir-sede`.
- **Cannot**: Assign a patient to a sede from the creation form; link diseases (`tiene_enfermedad`) from the UI; add emergency contacts from the UI; assign an IoT kit from the UI.

### Cuidadores
- **Can**: List, create, edit, hard-delete (removes from `cuidadores` then `empleados`).
- **Cannot**: Assign a cuidador to a patient or sede from the UI.

### Turnos
- **Can**: List, create, edit (including `activo` toggle), delete shifts.

### Alertas
- **Can**: List, create, mark as `Atendida`, hard-delete.

### Dispositivos
- **Can**: List, create, edit, hard-delete.
- **Cannot**: Assign device to kit/zone from the UI; view GPS history or beacon detections.

### Zonas Seguras
- **Can**: List, create, edit, hard-delete.

### Farmacia
- **Can**: View inventory with critical-stock highlights; adjust stock inline; create supply orders.

### Visitas
- **Can**: List, register new visit (links existing `visitantes`).

### Recetas
- **Can**: List all recetas with NFC serial, medication count, and today's adherence bar (`/recetas`). View per-receta detail with medication list + 30-day NFC adherence % + last 20 NFC readings (`/recetas/<id>`).
- **Cannot**: Create, edit, or delete recetas from the UI; assign NFC devices from the UI — use stored procedures directly.

### Portal Clínico (rol: médico)
- Read-only view of sedes, patients, assignments, alerts.

### Portal Familiar (rol: contacto)
- Read-only: GPS map, alerts, medication adherence, visits, caregiver rounds.

### Sedes
- **No admin CRUD UI** — 3 sedes seeded by the DDL are fixed.

### Tables with No UI at All
`lecturas_gps`, `detecciones_beacon`, `lecturas_nfc`, `receta_medicamentos`, `receta_nfc`, `tiene_enfermedad`, `enfermedades`, `asignacion_kit`, `asignacion_cuidador`, `sede_empleados`, `sede_zonas`, `bitacora_comedor`, `cocineros`, `alerta_evento_origen`, `entregas_externas`, `visitantes`.

---

## Design System

CSS variables in `static/css/main.css`:
- Primary teal: `#0E7490` / Dark bg: `#082F3E`
- Status colors: emerald (success), amber (warning), rose (danger), sky (info)
- Sidebar: dark gradient `#071C27 → #082F3E`, pill-style nav items, active state via `box-shadow: inset 3px 0 0 #2DD4BF`
- Stat cards: 16px radius, `.stat-icon` colored box per type (blue/green/amber/red), hover lift

Portal familiar uses the same teal palette but softer background (`#F0F9FF`), no sidebar. Styles are inline in `base_familiar.html`.

UI is entirely in Spanish.
