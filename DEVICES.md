# IoT Hardware — Dispositivos e Integración

Documentación de los dispositivos físicos integrados en AlzMonitor.

---

## Inventario de dispositivos

| Rol | Modelo | Tecnología | Lo porta |
|-----|--------|-----------|----------|
| GPS | PG12 GPS Tracker — Luejnbogty | GPRS / 4G + GPS | Paciente (oculto en ropa) |
| Beacon | FeasyBeacon FSC-BP104D Waterproof | Bluetooth 5.1 BLE | Cuidador (portátil) |
| NFC | NFC DESFire wristband | ISO 14443A (pasivo) | Paciente (pulsera, sin batería) |

---

## Arquitectura de tres capas

### Layer 1 — GPS (Exterior, flujo de seguridad crítico)

El paciente lleva el tracker GPS oculto en ropa/cinturón/zapato. El dispositivo envía coordenadas directamente a Flask usando el protocolo OsmAnd/Traccar (push, no polling).

#### Flujo de datos

```
Traccar Client / OsmAnd (en teléfono Android)
    ↓  GET http://<VM>:5003/api/gps/osmand?id=<serial>&lat=&lon=&batt=
Flask — api/gps_osmand
    ↓  CALL sp_ins_lectura_gps(...)
PostgreSQL  lecturas_gps  ← registro principal con FK a dispositivo y paciente
    ↓  triggers automáticos
    ├── trg_bateria_baja_gps  → alerta "Batería crítica" si nivel ≤ 15 %
    └── trg_zona_exit_gps    → alerta "Salida de Zona" si punto fuera de geocercas
MongoDB  lecturas_gps  ← espejo de lectura (fire-and-forget)
```

#### MongoDB — colección `lecturas_gps`

```js
{
  id_lectura:     42,
  id_dispositivo: 3,
  latitud:        19.4326,
  longitud:       -99.1332,
  nivel_bateria:  80,
  altura:         2240.0,
  fecha_hora:     ISODate("2026-05-12T14:00:00Z")
}
```

#### Endpoints disponibles

| Endpoint | Método | Autenticación | Uso |
|----------|--------|--------------|-----|
| `/api/gps/osmand` | GET/POST | ninguna | Traccar Client / OsmAnd (puerto 5003) |
| `/api/gps/lectura` | POST | `X-AlzMonitor-Key` | API directa con JSON |
| `/api/gps/ultima/<id_paciente>` | GET | sesión | Polling del mapa cada 8 s |
| `/sim/gps` | GET/POST | admin | Simulador web desde el panel |

#### Configuración del Traccar Client en el teléfono

1. **Identificador de dispositivo:** el serial registrado en **Admin → Dispositivos** (ej. `traccar-001`)
2. **URL del servidor:** `http://<IP_DE_LA_VM>:5003` (HTTP, puerto 5003)
3. Activar el seguimiento — el teléfono empieza a enviar coordenadas automáticamente

---

### Layer 2 — BLE Beacon (Interior, rondas del cuidador)

El cuidador porta el beacon Bluetooth mientras hace sus rondas. `beacon_scanner.py` corre en una computadora cercana con Bluetooth, detecta los beacons y reporta a Flask. Cada detección registra qué cuidador estuvo presente y cuándo.

#### Flujo de datos

```
Beacon FSC-BP104D (portado por el cuidador)
    ↓  BLE advertisement (iBeacon UUID-major-minor)
beacon_scanner.py  (computadora local con Bluetooth + bleak)
    ↓  POST /api/beacon/deteccion  (JSON)
Flask — api/beacon_deteccion
    ↓  CALL sp_ins_deteccion_beacon(...)
PostgreSQL  detecciones_beacon
MongoDB  detecciones_beacon  ← espejo de detección (fire-and-forget)
```

#### MongoDB — colección `detecciones_beacon`

```js
{
  id_deteccion:    15,
  id_beacon:       2,
  serial_beacon:   "FDA50693-1000-1001",
  id_cuidador:     5,
  nombre_cuidador: "Juan Martínez",
  rssi:            -68,
  id_gateway:      "central",
  fecha_hora:      ISODate("2026-05-12T14:05:00Z")
}
```

#### Ejecutar el escáner BLE

```bash
# Apunta al servidor en la VM (requiere bleak y requests instalados)
ALZMONITOR_URL="https://<IP_DE_LA_VM>:5002/api/beacon/deteccion" python3 beacon_scanner.py
```

Salida esperada al detectar un beacon:

```
==================================================
AlzMonitor — Escáner BLE
Reportando a: https://35.x.x.x:5002/api/beacon/deteccion
==================================================
[OK] Beacon 1001-1 | RSSI -68 dBm | Cuidador: Juan Martínez
```

#### Simular sin hardware

```bash
curl -k -X POST https://<IP>:5002/api/beacon/deteccion \
  -H "X-AlzMonitor-Key: alz-dev-2026" \
  -H "Content-Type: application/json" \
  -d '{"uuid": "FDA50693-1000-1001", "major": 1001, "minor": 1, "rssi": -70}'
```

---

### Layer 3 — NFC (Checkpoint, adherencia terapéutica)

El paciente lleva una pulsera NFC DESFire (pasiva, sin batería). El cuidador acerca su teléfono Android (Chrome) a la pulsera para registrar la administración de medicamentos.

#### Flujo de datos

```
Cuidador acerca teléfono a pulsera NFC del paciente
    ↓  Web NFC API (Chrome Android) — solo en HTTPS
Flask — /cuidador/escanear (Jinja2 + JS)
    ↓  POST /api/nfc/lectura  (JSON)
Flask — api/nfc_lectura
    ↓  CALL sp_nfc_registrar_lectura(...)
PostgreSQL  lecturas_nfc  ← registro con FK a receta y dispositivo
MongoDB  lecturas_nfc  ← espejo (fire-and-forget)
```

#### MongoDB — colección `lecturas_nfc`

```js
{
  id_lectura_nfc: 200,
  id_dispositivo: 5,
  id_receta:      10,
  tipo_lectura:   "Administración",
  resultado:      "Exitosa",
  fecha_hora:     ISODate("2026-05-12T14:10:00Z")
}
```

#### Simular sin hardware

```bash
curl -k -X POST https://<IP>:5002/api/nfc/lectura \
  -H "X-AlzMonitor-Key: alz-dev-2026" \
  -H "Content-Type: application/json" \
  -d '{"serial": "<SERIAL_NFC>", "tipo_lectura": "Administración", "resultado": "Exitosa"}'
```

> Web NFC solo funciona en Chrome para Android en contexto HTTPS. Para pruebas de escritorio usar el endpoint directo con curl o la página `/test/nfc`.

---

## Resumen de almacenamiento

| Dispositivo | Colección MongoDB | Tabla PostgreSQL principal |
|-------------|------------------|--------------------------|
| GPS | `lecturas_gps` | `lecturas_gps` + `alertas` (vía triggers) |
| Beacon | `detecciones_beacon` | `detecciones_beacon` |
| NFC | `lecturas_nfc` | `lecturas_nfc` (FK a `recetas`, `dispositivos`) |

Los tres siguen el mismo patrón: PostgreSQL es la fuente de verdad, MongoDB es espejo secundario. Si Mongo falla, la operación no se revierte.

---

## Triggers activados por lecturas IoT

| Trigger | Evento | Condición | Efecto |
|---------|--------|-----------|--------|
| `trg_bateria_baja_gps` | INSERT en `lecturas_gps` | `nivel_bateria ≤ 15` | Inserta alerta tipo "Batería crítica" |
| `trg_zona_exit_gps` | INSERT en `lecturas_gps` | Punto fuera de todas las geocercas del paciente | Inserta alerta tipo "Salida de Zona" |
| `trg_cobertura_zona` | INSERT en `detecciones_beacon` | Siempre | Registra cobertura del cuidador en zona |
