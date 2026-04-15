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

`pdf_report.py` — standalone ReportLab module. `generate_patient_report(patient_id)` returns a `BytesIO` PDF. Uses manual DB queries (does not reuse the historial route). Called only from `GET /pacientes/<id>/reporte-pdf`.

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

**IoT API endpoints and caregiver scanner webapp are implemented but commented out in `app.py`** — not yet active. Uncomment `POST /api/nfc/lectura`, `POST /api/beacon/deteccion`, and `GET /cuidador/escanear` when ready to activate.

## Advanced Queries — finalqueries.sql

All advanced queries are complete in `finalqueries.sql`. **Do not re-fix these — they are already done.**

## Schema — ProyectoFinalDDL.sql

Key schema facts:
- `pacientes.id_estado` is an integer FK → `estados_paciente` (1=Activo, 2=En Hospital, 3=Baja). Soft-delete sets `id_estado = 3`.
- Battery is in `lecturas_gps.nivel_bateria`, not on `dispositivos`.
- `empleados` has no `id_sede` — linked via `sede_empleados` bridge table.
- `asignacion_kit` links one patient to one GPS device (GPS only — no beacon column). Has `fecha_fin DATE` for historical records. Partial indexes `uq_kit_activo_por_paciente` and `uq_gps_activo` both use `WHERE fecha_fin IS NULL`. **All app.py queries joining `asignacion_kit` now include `AND ak.fecha_fin IS NULL`** — this fix was applied to all 4 affected queries.
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

### alerta_evento_origen — event traceability
Bridge table linking each `alertas` row to the raw IoT event that triggered it. Columns: `id_alerta`, `tipo_origen` (`'GPS'`|`'BEACON'`|`'NFC'`|`'Manual'`), `id_evento` (FK to the origin table row), `descripcion`. Seed data includes GPS-triggered battery-low and zone-exit alerts. The `notificar_a` field in dashboard queries currently returns `'—'` hardcoded — contact escalation is not implemented in code.

### Pending: Coverage trigger (commented out in DDL BLOQUE 11)
`fn_verificar_cobertura_zona()` + `trg_cobertura_zona` are fully written but commented out. Fires `AFTER INSERT ON detecciones_beacon`, checks all zones with active shifts for 30-min caretaker absence, inserts a `'Zona sin cobertura'` alert. Uncomment BLOQUE 11 to activate.

## Stored Procedures — RecetasProcedures.sql

`RecetasProcedures.sql` contains 10 stored procedures for the receta/NFC module. **Already applied to the live DB.**
- `sp_receta_crear` — creates a new recipe for a patient
- `sp_receta_agregar_medicamento` / `sp_receta_quitar_medicamento` / `sp_receta_actualizar_medicamento`
- `sp_receta_activar_nfc` / `sp_receta_cerrar_nfc` / `sp_receta_cambiar_nfc`
- `sp_nfc_registrar_lectura` — inserts into `lecturas_nfc` (validates active NFC-receta link)
- `sp_receta_cerrar` — closes all active NFC links for a recipe
- `sp_nfc_asignar` — assigns (or reassigns) an NFC device to a patient via `asignacion_nfc`

Re-apply if needed: `psql -U palermingoat -d alzheimer -f RecetasProcedures.sql`

### ProcedimientosAlmacenados.sql — consolidated reference file
Contains all 10 procedures rewritten to follow the academic `CREATE PROCEDURE` convention (no `OR REPLACE`, explicit `IN` on all params, `BEGIN; CALL …; COMMIT;` usage block after each one). Also adds 3 read-only REFCURSOR procedures (not in the live DB — for documentation/demo):
- `sp_receta_consultar_medicamentos(p_id_receta, INOUT io_resultados REFCURSOR)` — returns medication list joined with `medicamentos`
- `sp_nfc_historial_lecturas(p_id_receta, p_limite, INOUT io_resultados REFCURSOR)` — returns last N NFC readings with device serial
- `sp_paciente_recetas_activas(p_id_paciente, INOUT io_resultados REFCURSOR)` — returns active recetas with med count and NFC wristband serial

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
- **Can**: Download PDF report per patient at `GET /pacientes/<id>/reporte-pdf` (generated by `pdf_report.py` using ReportLab). Sections: patient identity, GPS kit, enfermedades, cuidadores, contactos, alert history (30d), medication + NFC adherence (7d), last 10 GPS readings.
- **Cannot**: Create, edit, or delete recetas from the UI; assign NFC devices from the UI — use stored procedures directly.

### Portal Clínico (rol: médico)
- Read-only view of sedes, patients, assignments, alerts.

### Portal Familiar (rol: contacto)
- Single scrollable page, mobile-first. Sections in order:
  1. **Status banner** (full-width, 120px): green "✓ [Nombre] está bien" / red pulsing "⚠ Alerta activa" / amber "⏳ Sin datos recientes" — based on last event across GPS+NFC+alerts and active critical alerts (Salida de Zona, Botón SOS).
  2. **Location card**: Leaflet map (200px, non-interactive), zone circles, patient marker, zone name or "Fuera de zona segura" with time since last GPS.
  3. **Medicinas de hoy**: per-medication checklist with NFC confirmation status (✓ Tomada / Pendiente), adherence progress bar.
  4. **Cuidadores de guardia**: tap-to-call green button per cuidador.
  5. **Alertas** (last 30 days): active in red, attended in gray.
  6. **Visitas recientes**.
- `estado_banner` computed in Python: `'ok'`, `'critica'`, or `'sin_datos'` (no data >2h). Time strings (`tiempo_actividad`, `tiempo_alerta_critica`, `tiempo_gps`) also computed in Python as human-readable relative strings.

### Sedes
- **No admin CRUD UI** — 3 sedes seeded by the DDL are fixed.

### Kit Assignment (Escenario 4)
- **Cannot**: Reassign a GPS kit from the UI. `asignacion_kit` has `fecha_fin` for history and partial indexes `uq_kit_activo_por_paciente` / `uq_gps_activo` (both `WHERE fecha_fin IS NULL`) prevent duplicate active assignments — but the reassignment flow only exists via SQL. No alert is auto-generated when `nivel_bateria <= 15`; the battery-low alerts in seed data were inserted manually.

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

---

## Professor Demo Scenarios — Status

Five scenarios required for the final demo/grade. Professor's core critique: fix semantic consistency between 3NF normalization, IoT event traceability, analytical queries, and UI before adding more visual modules.

### Escenario 1 — Salida de zona y escalamiento 🔴 INCOMPLETE
Chain: `lecturas_gps → PostGIS zone check → alertas → alerta_evento_origen → notify priority contact`.
- Schema supports it fully (`paciente_contactos.prioridad`, `alerta_evento_origen`, PostGIS indexes)
- Seed data has GPS readings and zone-exit alerts already inserted
- **Missing**: GPS polling loop (no code calls the PG12 cloud API); PostGIS `ST_DWithin` check never runs in production; contact escalation (email/SMS) has no implementation anywhere; `notificar_a` in dashboard queries is hardcoded `'—'`

### Escenario 2 — Cambio de sede sin pérdida histórica ✅ COMPLETE
- `POST /pacientes/<id>/transferir-sede` closes active `sede_pacientes` row (`fecha_salida = CURRENT_DATE`) and inserts new one atomically
- Alerts and visits are FK'd to `id_paciente`, not `id_sede` — fully preserved on transfer
- Full sede history visible in `/pacientes/<id>/historial`

### Escenario 3 — Cambio de tratamiento y adherencia NFC 🟡 PARTIAL
- Stored procedures exist for all receta/NFC mutations (`sp_receta_actualizar_medicamento`, `sp_receta_cambiar_nfc`, etc.)
- `/recetas/<id>` shows 30-day adherence % and last 20 NFC readings from seed data
- **Missing**: No UI to modify a receta — doctor must use SQL directly; NFC endpoints (`POST /api/nfc/lectura`) are commented out so no live reading can be demonstrated

### Escenario 4 — Falla de batería y reemplazo de kit 🟡 PARTIAL
- `nivel_bateria` column exists in `lecturas_gps`; seed data has battery-low alerts in `alerta_evento_origen`
- `uq_kit_activo_por_paciente` and `uq_gps_activo` partial indexes prevent duplicate active assignments
- **Missing**: No UI for kit reassignment; no automatic alert trigger when `nivel_bateria <= 15` — those alerts in seed data were inserted manually

### Escenario 5 — Suministro crítico multisede ✅ MOSTLY COMPLETE
- `inventario_medicinas` PK is `(GTIN, id_sede)` — inventory is per-sede
- `suministros` has `id_sede` + `id_farmacia` — each order targets a specific sede and pharmacy
- Seed data has Donepezilo below `stock_minimo` in 2 sedes
- Farmacia UI shows critical-stock highlights and allows creating supply orders
- **Minor gap**: supply order creation form should visually enforce sede selection

---

## Pending UI Improvements

### Done
- ✅ Admin panel responsive sidebar (hamburger + overlay, breakpoint 900px) — `main.css` + `base.html`
- ✅ Admin login redesign — full-viewport dark background, animated CSS orbs + dot grid, floating card with Live badge (`templates/login.html`)
- ✅ Portal familiar login redesign — two-column split card (brand panel + form), feature bullets, richer gradient (`templates/portal_familiar/login.html`)

### To Do
2. **Portal familiar auto-refresh** — status banner and GPS data go stale without a page reload. Add a `setTimeout` (60s) that either reloads the page or hits a lightweight `/api/portal/estado/<id>` endpoint and updates the banner + time strings in-place. Families check this anxiously — it needs to feel live.

3. **Caregiver mobile webapp** (`GET /cuidador/escanear`) — currently commented out in `app.py`. A mobile-first page (same visual language as portal familiar) for the caregiver to tap the patient's NFC wristband and log a round. Flow: open page → tap wristband → `POST /api/nfc/lectura` → confirmation. Requires HTTPS (Web NFC). Auth via `medico_requerido` or a new `cuidador_requerido` decorator.

4. **Alert badge on sidebar nav item** — the "Alertas" nav item in `base.html` should show a live red count pill when `alertas_activas > 0`. Count already available on dashboard; needs to be injected into the base layout (pass via a `g` context or base query).

5. **Dashboard empty states** — when sections have no data (no visits today, no critical meds, no active alerts), replace empty tables with illustrated empty-state blocks. Consistent with the card style.

### Scenario gaps to close (professor priority)
- **Escenario 1**: implement GPS polling loop + PostGIS zone check + insert into `alertas`/`alerta_evento_origen` automatically; add contact escalation display (who was notified, at what priority)
- **Escenario 3**: add UI for a doctor to modify a receta's medications and frequency; uncomment NFC endpoints for live demo
