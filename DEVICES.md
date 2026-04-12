# IoT Hardware — Dispositivos y Plan de Integración

Documentación de los dispositivos físicos y arquitectura actualizada de AlzMonitor.

> **Estado actual:** dispositivos adquiridos, pendientes de configuración. Ningún endpoint de recepción de datos está implementado todavía. Este documento describe la arquitectura objetivo.

---

## Inventario de dispositivos

| Rol | Modelo | Tecnología | Lo porta |
|-----|--------|-----------|----------|
| GPS | PG12 GPS Tracker — Luejnbogty | GPRS / 4G + GPS | Paciente (oculto en ropa) |
| Beacon | FeasyBeacon FSC-BP104D Waterproof | Bluetooth 5.1 BLE | Fijo en paredes/techo del edificio |
| NFC | NFC DESFire wristband | ISO 14443A (pasivo) | Paciente (pulsera, sin batería) |

---

## Arquitectura de tres capas

### Layer 1 — GPS (Exterior, flujo de seguridad crítico)

**El GPS es el mecanismo central de seguridad de la app.**

El paciente lleva el PG12 oculto en ropa/cinturón/zapato. No interactúa con él. Flask hace polling a la API cloud del PG12 cada 30–60 segundos, obtiene coordenadas, y evalúa si el paciente está dentro de alguna zona segura.

#### Flujo de datos
```
PG12 → API cloud del fabricante
           ↓  polling cada 30-60s
       Flask (tarea de background / APScheduler)
           ↓
       MongoDB  gps_events  ← almacenamiento principal (alto volumen)
           ↓
       PostGIS ST_DWithin(point, zone_geometry, radio)
           ↓  fuera de zona
       PostgreSQL alertas (tipo='Salida de Zona', estado='Activa')
                + alerta_evento_origen (FK → referencia al evento MongoDB)
           ↓  sin atender después de 5 min
       Escalación + notificación a contacto de emergencia
```

#### MongoDB collection: `gps_events`
```js
{
  device_id: "PG12-001",
  patient_id: 42,
  timestamp: ISODate(),
  location: { type: "Point", coordinates: [lng, lat] },
  speed: 1.2,
  battery: 78,
  inside_zone: true
}
// Índices: 2dsphere en location, compuesto {patient_id, timestamp}
```

#### Endpoint a implementar
```
GET /api/gps/poll  (interno, llamado por scheduler)
```
No es un endpoint público — es una tarea interna que Flask ejecuta periódicamente.

#### Configuración pendiente
1. Insertar SIM con datos en el PG12.
2. Obtener credenciales de la API cloud del fabricante (Luejnbogty).
3. Registrar el dispositivo en `dispositivos` con tipo `GPS` y número de serie.
4. Asignarlo al paciente via `asignacion_kit`.
5. Configurar MongoDB con índice 2dsphere.

---

### Layer 2 — BLE Beacon (Interior, rondas del cuidador)

Los beacons son **fijos en el edificio** — no los porta el paciente. Están en puntos estratégicos: puerta principal, salida de emergencia, salida al jardín, sala común, comedor, escaleras.

El cuidador lleva su teléfono Android (Chrome). Durante las rondas, el teléfono escanea beacons cercanos via **Web Bluetooth API** y hace POST a Flask. Esto registra qué zonas visitó el cuidador y cuándo — no es rastreo del paciente.

**No se requieren gateways BLE.** El teléfono del cuidador es el receptor.

#### Flujo de datos
```
Beacon (fijo en pared/techo)
    ↓  BLE advertisement
Teléfono Android del cuidador (Chrome, Web Bluetooth API)
    ↓  POST
/api/beacon/deteccion
    ↓
MongoDB  ble_events  ← almacenamiento (volumen medio durante rondas)
```

#### MongoDB collection: `ble_events`
```js
{
  beacon_id: "FEASY-003",
  zone_name: "Puerta Principal",
  caregiver_id: 5,
  timestamp: ISODate(),
  rssi: -45,
  estimated_distance_m: 2.3
}
// Índice: compuesto {caregiver_id, timestamp}
```

#### Endpoint a implementar
```
POST /api/beacon/deteccion
Body: { "beacon_id": "FEASY-003", "zone_name": "Puerta Principal",
        "caregiver_id": 5, "rssi": -45, "timestamp": "..." }
```

#### Configuración pendiente
1. Configurar UUID/Major/Minor en cada FeasyBeacon con la app del fabricante.
2. Asignar nombre de zona a cada beacon (registrar en tabla `gateways` o nueva tabla de beacons fijos).
3. Registrar los beacons en `dispositivos` con tipo `BEACON`.
4. Implementar la página de rondas del cuidador (Web Bluetooth scan).

---

### Layer 3 — NFC (Checkpoint, adherencia terapéutica)

El paciente lleva una **pulsera NFC DESFire** (pasiva, sin batería — como pulsera de hospital). El cuidador acerca su teléfono a la pulsera via **Web NFC API** para verificar identidad, confirmar administración de medicamento, o registrar un checkpoint.

**Web NFC: solo Chrome Android.**

#### Flujo de datos
```
Cuidador acerca teléfono a pulsera NFC del paciente
    ↓  Web NFC API (Chrome Android)
App Flask (Jinja2 + JS)
    ↓  POST
/api/nfc/lectura
    ↓
PostgreSQL  lecturas_nfc  ← bajo volumen, alta integridad clínica
    (FK a recetas, FK a dispositivos)
```

#### Endpoint a implementar
```
POST /api/nfc/lectura
Body: { "id_serial_nfc": "...", "id_receta": 1,
        "tipo_lectura": "Administración", "resultado": "Exitosa" }
```

#### Configuración pendiente
1. Grabar en cada pulsera el ID de receta con NFC Tools u otra app.
2. Registrar la pulsera en `dispositivos` con tipo `NFC` y número de serie.
3. Crear `receta_nfc` que vincula la pulsera a la receta del paciente desde `/recetas/<id>/editar`.

---

## Resumen de tablas afectadas

| Dispositivo | Almacenamiento principal | Tabla PostgreSQL afectada |
|-------------|--------------------------|--------------------------|
| GPS PG12 | MongoDB `gps_events` | `alertas` + `alerta_evento_origen` |
| Beacon FSC-BP104D | MongoDB `ble_events` | — (presencia del cuidador) |
| NFC DESFire | PostgreSQL `lecturas_nfc` | `lecturas_nfc` (FK a `recetas`, `dispositivos`) |

`asignacion_kit` vincula un paciente a su dispositivo GPS. Los beacons no tienen asignación por paciente.

---

## Requisitos técnicos del webapp del cuidador

- **HTTPS obligatorio** — Web Bluetooth y Web NFC requieren contexto seguro.
- Servir Flask con SSL (certificado autofirmado para desarrollo, Let's Encrypt para producción).
- El webapp del cuidador es una página Jinja2 servida por Flask que usa las APIs del navegador y hace POST a Flask.

---

## Endpoints API a implementar (resumen)

| Endpoint | Método | Descripción |
|----------|--------|-------------|
| `/api/beacon/deteccion` | POST | Recibe detección BLE del teléfono del cuidador, inserta en MongoDB `ble_events` |
| `/api/nfc/lectura` | POST | Recibe escaneo NFC, inserta en PostgreSQL `lecturas_nfc` |
| `/api/gps/sos` | POST | Botón SOS del GPS → alerta tipo `'Botón SOS'` inmediata en PostgreSQL |

El flujo GPS es interno (polling) — no es un endpoint público.

Todos los endpoints externos requieren autenticación mínima por API key (header `X-API-Key`).

---

## Orden de implementación recomendado

1. **MongoDB primero** — configurar conexión, definir colecciones e índices.
2. **GPS polling** — implementar tarea de background con APScheduler, conectar a API del PG12, almacenar en MongoDB, evaluar zonas con PostGIS, generar alertas en PostgreSQL.
3. **NFC** — el más sencillo de los endpoints externos. Grabar pulseras, probar POST manual, validar en `lecturas_nfc`.
4. **Beacon** — implementar página de rondas del cuidador con Web Bluetooth, endpoint `/api/beacon/deteccion`.

---

## Escenarios requeridos por el profesor (5)

Deben documentarse y demostrarse con datos reales end-to-end:

1. **Escape de zona + escalación** — paciente sale de geofence → alerta → notificar cuidador + contacto de emergencia. Integridad: paciente, dispositivo, zona, lectura GPS, alerta, seguimiento.
2. **Transferencia de sede sin pérdida de historial** — paciente cambia de Sede Norte a Sede Sur. Control de rangos de fecha en `sede_pacientes`, continuidad de historial de alertas/visitas.
3. **Cambio de tratamiento + adherencia NFC** — médico modifica receta. Consistencia entre `recetas`, `receta_medicamentos`, asignación NFC, y lecturas NFC del período.
4. **Falla de batería + reemplazo de kit** — GPS reporta batería baja → dispositivo reemplazado. Sin duplicado de asignación activa por paciente + trazabilidad del reemplazo.
5. **Suministro crítico en múltiples sedes** — medicamento bajo mínimo en 2 sedes → órdenes a diferentes farmacias. Integridad en `inventario_medicinas`, `suministros`, `suministro_medicinas`, estado de entrega.
