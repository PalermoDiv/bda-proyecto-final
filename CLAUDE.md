# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AlzMonitor** is an academic Flask web app for managing Alzheimer's patients across multiple clinical facilities. Built for an Advanced Databases (BDA) university course to demonstrate multi-tenant clinical data modeling, stored procedures, DB triggers, and IoT integration.

## Running the App

```bash
pip install -r requirements.txt
python app.py
# Runs at https://localhost:5002  (self-signed TLS — auto-generated on first run)
```

Apply the schema from scratch:
```bash
psql -U palermingoat -d alzheimer -f ProyectoFinalDDL.sql
psql -U palermingoat -d alzheimer -f RecetasProcedures.sql
psql -U palermingoat -d alzheimer -f TriggersDB.sql
```

Requires PostGIS installed (`brew install postgis`) — the DDL runs `CREATE EXTENSION IF NOT EXISTS postgis`.

Test credentials (defined in `.env`):
- Admin: `admin` / `admin123`
- Medical staff: `medico` / `medico123`
- Portal Familiar (demo): any contact email from seed data / PIN `1234`
  - e.g. `lucia.garcia@demo.com` / `1234`

## Architecture

### Data Layer
**Primary data source is PostgreSQL** (`alzheimer` DB, user `palermingoat`, empty password, Unix socket via `DB_HOST=/tmp`). `db.py` provides helpers: `query()`, `one()`, `scalar()`, `execute()`, `execute_many()` — all use `RealDictCursor` so results are dict-compatible.

`data.py` is still imported for a small set of in-memory structures not yet migrated: `TURNOS_HOY`, `TAREAS_HOY`, `MEDICAMENTOS`, `BITACORAS`, `INCIDENTES`, `PERFIL_CLINICO`, `BITACORA_COMEDOR`, `ALERTAS_MEDICAS`, `ASIGNACIONES_CUIDADORES`.

Multi-facility filtering is done at the route level using `id_sede` (maps to `id_sucursal` in templates).

### Route Organization
All routes are flat in `app.py` — no blueprints. Three auth decorators defined at module level:
- `admin_requerido` — checks `session["admin"]`
- `medico_requerido` — checks `session["medico"]`
- `contacto_requerido` — checks `session["contacto_id"]`; redirects to `/portal-familiar/login`

Three roles:
- `admin` — full CRUD, all sedes, admin panel with sidebar
- `medico` — clinic-scoped read view under `/clinica`; also accesses `/cuidador/escanear`
- `contacto` — read-only family portal under `/portal-familiar`; scoped to their linked patients only via `paciente_contactos`

IoT auth helper: `_iot_auth()` — returns True if session is admin/medico OR `X-AlzMonitor-Key: alz-dev-2026` header is present.

Helper `_haversine_m(lat1, lon1, lat2, lon2)` — returns distance in metres between two WGS-84 coordinates (used in portal familiar; API layer uses PostGIS `ST_DWithin`).

### Templates
`templates/base.html` is the master layout for the admin panel — sticky 248px sidebar. All admin/medico pages extend it. Patient templates live in `templates/pacientes/`, caregiver in `templates/cuidadores/`, turno in `templates/turnos/`, caregiver scanner in `templates/cuidador/`.

`templates/portal_familiar/base_familiar.html` is the separate master layout for the family portal — no sidebar, mobile-first, soft teal theme.

SQL aliases map real DB column names to the names templates expect (e.g. `nombre AS nombre_paciente`). Date columns are returned via `TO_CHAR(col, 'YYYY-MM-DD')`.

### Frontend
Vanilla JS only (`static/js/main.js`, 25 lines) — handles auto-dismiss alerts and deletion confirmations. No build step, no bundler. Portal familiar loads Leaflet.js via CDN for the GPS map. Caregiver scanner uses Web NFC API + Web Bluetooth API (Chrome Android only).

`pdf_report.py` — standalone ReportLab module. `generate_patient_report(patient_id)` returns a `BytesIO` PDF. Called only from `GET /pacientes/<id>/reporte-pdf`.

## IoT Hardware

| Role | Model | Technology | Carried by |
|------|-------|-----------|------------|
| GPS | PG12 GPS Tracker — Luejnbogty | GPRS/4G + GPS | Patient (hidden in clothing) |
| Beacon | FeasyBeacon FSC-BP104D Waterproof | Bluetooth 5.1 BLE | Fixed to building walls/ceilings |
| NFC | NFC DESFire wristband | ISO 14443A (passive) | Patient (wristband, no battery) |

Full integration plan is in `DEVICES.md`. **GPS is the central safety mechanism.**

### Three-layer architecture
- **Layer 1 — GPS (outdoor/critical):** `POST /api/gps/lectura` inserts into `lecturas_gps`. `trg_zona_exit_gps` fires automatically via PostGIS `ST_DWithin`. `trg_bateria_baja_gps` fires when `nivel_bateria ≤ 15`. Both triggers populate `alerta_evento_origen`.
- **Layer 2 — BLE Beacon (indoor/caregiver rounds):** Caregiver's Android phone scans via Web Bluetooth API, POSTs to `POST /api/beacon/deteccion`. Logs caregiver rounds into `detecciones_beacon`. `trg_cobertura_zona` fires and alerts if a zone goes 30+ min without a caregiver. UI: `GET /cuidador/ronda`.
- **Layer 3 — NFC (medication adherence):** Caregiver taps phone to patient's NFC wristband via Web NFC API. POSTs to `POST /api/nfc/lectura` → calls `sp_nfc_registrar_lectura`. Events stored in `lecturas_nfc` (FK to `recetas`).

**HTTPS required** for caregiver webapp (Web Bluetooth + Web NFC need secure context). TLS cert is auto-generated by `openssl` on first `python app.py` run. Web NFC is Chrome Android only.

## SQL Files Reference

| File | Status | Purpose |
|------|--------|---------|
| `ProyectoFinalDDL.sql` | Applied | Full schema + seed data (43 tables) |
| `RecetasProcedures.sql` | Applied | 10 stored procedures for receta/NFC module |
| `BeaconProcedures.sql` | Applied | 1 stored procedure for caregiver beacon rounds |
| `TriggersDB.sql` | Applied | 3 DB triggers (cobertura zona, batería baja, zona exit) |
| `ProcedimientosAlmacenados.sql` | Ref only | Academic convention rewrite of all SPs + 3 REFCURSOR SPs |
| `finalqueries.sql` | Complete | Advanced analytical queries — **do not re-fix** |
| `FinalStoredProcedures.sql` | Old ref | Earlier SP design — superseded by RecetasProcedures.sql |
| `queries.sql` | Old ref | Earlier query drafts |
| `Guia_Procedimientos_Almacenados.md` | Docs | Full usage guide for all 10 SPs — parameters, preconditions, error messages, SQL examples, lifecycle flow |

## Schema — ProyectoFinalDDL.sql

Key schema facts:
- `pacientes.id_estado` is an integer FK → `estados_paciente` (1=Activo, 2=En Hospital, 3=Baja). Soft-delete sets `id_estado = 3`.
- Battery is in `lecturas_gps.nivel_bateria`, not on `dispositivos`.
- `empleados` has no `id_sede` — linked via `sede_empleados` bridge table.
- `asignacion_kit` links one patient to one GPS device. Has `fecha_fin DATE` for historical records. Partial indexes `uq_kit_activo_por_paciente` and `uq_gps_activo` both use `WHERE fecha_fin IS NULL`. All `app.py` queries joining `asignacion_kit` include `AND ak.fecha_fin IS NULL`.
- `contactos_emergencia` linked via `paciente_contactos` bridge table. `prioridad` integer determines escalation order.
- `sede_pacientes` uses `fecha_salida`/`hora_salida` (not `fecha_fin`). Partial unique index enforces one active sede per patient.
- `alertas.estatus` values: `'Activa'`, `'Atendida'`. `id_paciente` may be NULL for zone-level alerts.
- `cat_tipo_alerta.tipo_alerta` is a VARCHAR primary key — no `id_tipo_alerta` integer. Values: `'Batería Baja'`, `'Botón SOS'`, `'Caída'`, `'Salida de Zona'`, `'Zona sin cobertura'`.
- `recetas.estado` VARCHAR(20), default `'Activa'`. Values: `'Activa'`, `'Cerrada'`.
- `medicamentos.nombre_medicamento` (not `nombre`).
- `zonas.geom` and `lecturas_gps.geom` are `GEOGRAPHY(Point, 4326)`, populated via `ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography`. GIST indexes on both. **Note: MakePoint takes (longitude, latitude) not (lat, lon).**
- `alerta_evento_origen.tipo_evento` CHECK constraint allows only `'GPS'`, `'NFC'`, `'SOS'` — not `'Manual'` or `'BEACON'`.
- `detecciones_beacon.rssi` is NOT NULL — always pass a value (0 if unknown).
- `detecciones_beacon.id_cuidador` (not `id_empleado`) — FK to `cuidadores.id_empleado`, nullable (anonymous rounds allowed).
- `beacon_zona` was empty after initial DDL apply — seed data is in `ProyectoFinalDDL.sql` but must be re-inserted if the table is empty: devices 401→zona 1, 402→2, 403→3, 404→4.
- Device 401 (`FeasyBeacon FSC-BP104D`) serial is `FDA50693-1000-1001` (UUID prefix-Major-Minor composite format). `POST /api/beacon/deteccion` resolves beacons by this key when `uuid`+`major`+`minor` are posted instead of `id_beacon`.

### DDL block order
BLOQUE 5 = RECETAS Y MEDICACIÓN. BLOQUE 6 = EVENTOS Y ALERTAS. BLOQUE 11 = trigger code (now moved to `TriggersDB.sql`).

## Stored Procedures — RecetasProcedures.sql

10 procedures applied to the live DB. All triggered from the UI or API — none require direct SQL.

| SP | Trigger location |
|----|----------------|
| `sp_receta_crear(id, id_paciente, fecha)` | `POST /recetas/nueva` |
| `sp_receta_agregar_medicamento(id, gtin, dosis, frecuencia_horas)` | `POST /recetas/<id>/agregar-medicamento` |
| `sp_receta_quitar_medicamento(id, id_detalle)` | `POST /recetas/<id>/quitar-medicamento` |
| `sp_receta_actualizar_medicamento(id, id_detalle, dosis, frecuencia_horas)` | `POST /recetas/<id>/actualizar-medicamento` |
| `sp_receta_activar_nfc(id, id_dispositivo, fecha_inicio)` | `POST /recetas/<id>/activar-nfc` |
| `sp_receta_cerrar_nfc(id, id_dispositivo, fecha_fin)` | `POST /recetas/<id>/cerrar-nfc` |
| `sp_receta_cambiar_nfc(id, id_dispositivo_nuevo, fecha_cambio)` | `POST /recetas/<id>/cambiar-nfc` |
| `sp_nfc_registrar_lectura(id, id_disp, id_receta, ts, tipo, resultado)` | `POST /api/nfc/lectura` |
| `sp_receta_cerrar(id, fecha_fin)` | `POST /recetas/<id>/cerrar` |
| `sp_nfc_asignar(id_paciente, id_dispositivo)` | `POST /pacientes/<id>/asignar-nfc` |

Re-apply: `psql -U palermingoat -d alzheimer -f RecetasProcedures.sql`

> **Note:** `sp_nfc_asignar` was found missing from the live DB on 2026-04-13 (likely truncated on a prior run). It was applied directly via psql inline SQL. All 10 SPs are confirmed present as of that date. If ever in doubt, re-apply the full file above.

Full interactive guide with parameters and CALL syntax: `GET /procedimientos` (admin only).
Full offline guide with SQL examples and lifecycle flow: `Guia_Procedimientos_Almacenados.md`.

### ProcedimientosAlmacenados.sql — academic reference
All 10 SPs rewritten following `CREATE PROCEDURE` convention (no `OR REPLACE`, explicit `IN` params, `BEGIN; CALL …; COMMIT;` blocks). Also adds 3 REFCURSOR read-only procedures for documentation (not in live DB):
- `sp_receta_consultar_medicamentos(p_id_receta, INOUT io_resultados REFCURSOR)`
- `sp_nfc_historial_lecturas(p_id_receta, p_limite, INOUT io_resultados REFCURSOR)`
- `sp_paciente_recetas_activas(p_id_paciente, INOUT io_resultados REFCURSOR)`

## DB Triggers — TriggersDB.sql

Applied to live DB. Re-apply: `psql -U palermingoat -d alzheimer -f TriggersDB.sql`

| Trigger | Fires on | Logic |
|---------|----------|-------|
| `trg_cobertura_zona` | `AFTER INSERT ON detecciones_beacon` | Checks all zones with active `turno_cuidador` shifts; if any zone has no cuidador detection in the last 30 min → inserts `'Zona sin cobertura'` alert. Dedup window: 2 hours. |
| `trg_bateria_baja_gps` | `AFTER INSERT ON lecturas_gps` | If `nivel_bateria ≤ 15`: resolves patient via `asignacion_kit`, inserts `'Batería Baja'` alert + `alerta_evento_origen` row with battery % context. Dedup window: 2 hours. |
| `trg_zona_exit_gps` | `AFTER INSERT ON lecturas_gps` | PostGIS `ST_DWithin` check against all zones of the patient's active sede. If outside all zones → inserts `'Salida de Zona'` alert + `alerta_evento_origen` row with zone names and coordinates. Dedup window: 1 hour. |

## Key Behaviors

- **Dispositivo registration**: `id_dispositivo` must be supplied manually (no SERIAL). `estado` defaults to `'Activo'`. `tipo` must be exactly `GPS`, `BEACON`, or `NFC`.
- **Cuidador deletion**: deletes from `cuidadores` then `empleados` in a single transaction (FK dependency).
- **Paciente deletion**: soft-delete only — `UPDATE pacientes SET id_estado = 3`.
- **Sede transfer**: `POST /pacientes/<id>/transferir-sede` closes active `sede_pacientes` row and inserts new one atomically via `execute_many`. Guards against same-sede transfers.
- **Turno management**: `id_turno` must be supplied manually. Day coverage uses individual boolean columns; `activo` flag disables without deleting.
- **Alertas creation**: `id_alerta` is auto-computed (`COALESCE(MAX,0)+1`). `id_paciente` is optional — NULL for zone-level alerts.
- **Portal familiar login**: looks up `contactos_emergencia` by `LOWER(email)` + `pin_acceso`. Session keys: `contacto_id`, `contacto_nombre`.
- **Portal familiar security**: every `/portal-familiar/paciente/<id>` request verifies the contact-patient link before loading; returns `abort(403)` if not found.
- **GPS readings**: always populate `geom` via `ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography` — triggers won't work without it.

## What the App Can and Cannot Do

### Pacientes
- **Can**: List active (id_estado != 3); create (with sede assignment, manual ID); edit name/DOB/estado; soft-delete; transfer sede.
- **Can**: Historial — enfermedades (add/remove), contactos de emergencia (add), kit GPS (assign), full sede history, alerts, visits.
- **Cannot**: Add a cuidador assignment from the UI; register entrega externa.

### Cuidadores
- **Can**: List, create, edit, hard-delete.
- **Cannot**: Assign to patient or sede from UI.

### Turnos
- **Can**: List, create, edit (`activo` toggle), delete.

### Alertas
- **Can**: List (with IoT origen, regla_disparada, priority contact); create (paciente optional); mark Atendida; delete.
- **Cannot**: Edit an existing alert; view full `alerta_evento_origen` history in a dedicated page.

### Dispositivos
- **Can**: List (with last GPS battery + patient), create, edit, hard-delete.
- **Cannot**: View GPS reading history or beacon detections; assign kit from UI (use `/sim/gps` for testing).

### Zonas Seguras
- **Can**: List (with active patients and priority contact); create, edit, hard-delete.
- **Cannot**: Assign beacons to zone (`beacon_zona`) from UI; manage `turno_cuidador` via a zone detail page.

### Farmacia
- **Can**: View per-sede inventory with critical-stock highlights; adjust stock inline; create supply orders; view order detail.
- **Cannot**: Add medication lines to an order (`suministro_medicinas`); manage farmacias proveedoras from UI.

### Recetas
- **Can**: List (with NFC serial, adherence bar); create; add/edit/remove medications; activate/change/deactivate NFC wristband; close receta. All via stored procedures.
- **Can**: PDF report per patient (`GET /pacientes/<id>/reporte-pdf`).
- **Cannot**: View recetas filtered by medico (only admin can see all).

### IoT APIs (active, no hardware required)
- `POST /api/gps/lectura` — insert GPS reading, fires zone-exit + battery triggers
- `POST /api/nfc/lectura` — register NFC tap, calls `sp_nfc_registrar_lectura`; resolves device by serial
- `POST /api/beacon/deteccion` — log caregiver round via `sp_cuidador_registrar_ronda`; resolves beacon by `id_beacon`, `serial`, or `uuid`+`major`+`minor` composite; returns `zone_name`
- `GET /cuidador/escanear` — caregiver NFC wristband scanner (Web NFC; `@medico_requerido`; login at `/clinica/login`)
- `GET /cuidador/ronda` — caregiver beacon round page (Web Bluetooth `requestLEScan` iBeacon parsing + manual zone check-in fallback; no auth yet)
- `GET /sim/gps` — admin GPS simulator form for demo without hardware

### Portal Clínico (rol: médico)
- Read-only view of sedes, patients, assignments, alerts, turnos.

### Portal Familiar (rol: contacto)
- Single scrollable page, mobile-first. Status banner, Leaflet GPS map with zones, today's medications (NFC confirmation), caregivers on duty (tap-to-call), last 30d alerts, recent visits.

### Sedes
- **No admin CRUD UI** — 3 sedes seeded by the DDL are fixed.

### Tables with No UI
`lecturas_gps` (except via sim), `receta_medicamentos`, `receta_nfc`, `tiene_enfermedad` (managed via historial), `enfermedades`, `asignacion_kit` (assign via historial), `asignacion_cuidador`, `sede_empleados`, `sede_zonas`, `bitacora_comedor`, `cocineros`, `alerta_evento_origen` (shown inline in alerts list), `entregas_externas`, `visitantes`.

Note: `detecciones_beacon` is now writable via `GET /cuidador/ronda` (BLE scan or manual check-in).

---

## Design System

CSS variables in `static/css/main.css`:
- Primary teal: `#0E7490` / Dark bg: `#082F3E`
- Status colors: emerald (success), amber (warning), rose (danger), sky (info)
- Sidebar: dark gradient `#071C27 → #082F3E`, pill-style nav items, active state via `box-shadow: inset 3px 0 0 #2DD4BF`
- Admin login: full-viewport dark bg (`#030D14`), floating CSS orbs, dot-grid radial gradient, pulsing Live badge
- Portal familiar login: two-column split card, teal brand panel, white form panel

UI is entirely in Spanish.

---

## Professor Demo Scenarios — Status

### Escenario 1 — Salida de zona y escalamiento 🟡 MOSTLY COMPLETE
- `trg_zona_exit_gps` fires on every `lecturas_gps` INSERT, PostGIS `ST_DWithin` check, inserts alert + `alerta_evento_origen` with zone names and coordinates
- Alertas list shows `tipo_evento` badge + `regla_disparada` + priority contact name + tap-to-call phone
- Zonas list shows patients in zone + priority contact
- `POST /api/gps/lectura` and `GET /sim/gps` enable demo without physical device
- **Still missing**: actual PG12 cloud API polling loop (no scheduled background task); contact escalation via email/SMS

### Escenario 2 — Cambio de sede sin pérdida histórica ✅ COMPLETE
- Atomic sede transfer via `execute_many`; full sede history in historial

### Escenario 3 — Cambio de tratamiento y adherencia NFC ✅ COMPLETE
- Full receta CRUD via 10 stored procedures, all with UI
- NFC wristband assign/change/deactivate from receta detail
- `POST /api/nfc/lectura` live, resolves by serial
- 30-day adherence % per medication, last 20 NFC readings

### Escenario 4 — Falla de batería y reemplazo de kit 🟡 MOSTLY COMPLETE
- `trg_bateria_baja_gps` auto-fires on INSERT, inserts `'Batería Baja'` alert + origen
- `sim/gps` simulator: set `nivel_bateria ≤ 15` to demo trigger in real time
- **Still missing**: UI for GPS kit reassignment (`asignacion_kit fecha_fin` flow); `uq_kit_activo_por_paciente` index enforces correctness but reassignment is SQL-only

### Escenario 5 — Suministro crítico multisede ✅ COMPLETE
- Per-sede inventory, critical-stock highlights, supply order creation

---

## Pending for Future Sessions

### High priority (demo gaps)
1. **GPS polling loop** — background thread or APScheduler job calling the PG12 cloud API every 60s, POSTing to `POST /api/gps/lectura`. No complex logic needed — the DB triggers handle everything once a row is inserted.
2. **GPS kit reassignment UI** — form in `historial.html` to close current `asignacion_kit` (set `fecha_fin = CURRENT_DATE`) and open a new one. The partial index `uq_kit_activo_por_paciente` already enforces correctness at the DB level.
3. **Contact escalation display** — when a `'Salida de Zona'` or `'Botón SOS'` alert fires, show on the alert detail which contact was notified at which priority. Currently the `notificar_a` chain is computable from `paciente_contactos` but nothing sends or logs a notification.

### Medium priority (UX)
4. **Portal familiar auto-refresh** — 60s `setTimeout` reload or lightweight `/api/portal/estado/<id>` JSON endpoint so the status banner and GPS time strings feel live without a manual reload.
5. **Alert badge on sidebar** — inject `alertas_activas` count from `g` context into `base.html` so the Alertas nav item shows a red pill when alerts are active.
6. **Dashboard empty states** — illustrated empty-state blocks when no visits, no critical meds, no active alerts.

### Low priority (completeness)
7. **GPS kit reassignment stored procedure** — `sp_kit_reasignar(id_paciente, id_dispositivo_nuevo)` wrapping the close+open in a single atomic call.
8. **Assign `beacon_zona` from UI** — seed data applied and live; no admin form to add/remove beacon↔zone links yet.
9. **`turno_cuidador` in zone detail** — show active shifts per zone on the zonas page so coverage can be inspected visually.
10. **Medico-scoped recetas** — filter `/recetas` by the medico's sede so doctors only see their patients' prescriptions.
