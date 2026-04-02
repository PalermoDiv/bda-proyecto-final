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

Test credentials (defined in `.env`):
- Admin: `admin` / `admin123`
- Medical staff: `medico` / `medico123`

## Architecture

### Data Layer
All data lives in `data.py` as Python dicts/lists — there is no real database. `db.py` is a stub. Multi-facility filtering is done at the route level by `id_sucursal`.

### Route Organization
Three Flask blueprints registered in `app.py`:
- `routes/public.py` — unauthenticated routes (`/`, `/login`, `/logout`)
- `routes/admin.py` — admin panel under `/dashboard` prefix, guarded by `session["admin"]`
- `routes/clinica.py` — medical staff portal under `/clinica` prefix, guarded by `session["medico"]`

Authentication uses a `login_requerido` decorator that checks `session` keys. Two roles: `admin` (full access) and `medico` (clinic-scoped view).

### Templates
`templates/base.html` is the master layout with a sticky 248px sidebar. All authenticated pages extend it. Patient and caregiver templates live in `templates/pacientes/` and `templates/cuidadores/` subdirectories.

### Frontend
Vanilla JS only (`static/js/main.js`, 25 lines) — handles auto-dismiss alerts and deletion confirmations. No build step, no bundler.

## Key Data Entities

Defined in `data.py` and keyed as follows:
- `SUCURSALES` — clinic branches (Sede Norte, Sede Sur)
- `PACIENTES` — patients with `id_sucursal` for facility assignment
- `ENFERMEDADES`, `MEDICAMENTOS`, `CONTACTOS_EMERGENCIA` — dicts keyed by `id_paciente`
- `ALERTAS_RECIENTES`, `DISPOSITIVOS`, `ZONAS` — facility-level entities
- `INVENTARIO_MEDICINAS`, `SUMINISTROS`, `VISITAS`, `ENTREGAS_EXTERNAS` — operational logs

## Design System

CSS variables in `static/css/main.css`:
- Primary teal: `#0E7490` / Dark bg: `#082F3E`
- Status colors: emerald (success), amber (warning), rose (danger), sky (info)

UI is entirely in Spanish.
