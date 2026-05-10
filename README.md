# AlzMonitor

Sistema de gestión clínica multisede para pacientes de Alzheimer, desarrollado como proyecto final de la materia de Bases de Datos Avanzadas (BDA). Integra PostgreSQL + PostGIS, procedimientos almacenados, triggers de base de datos y una arquitectura IoT de tres capas: GPS, beacons BLE y pulseras NFC.

> **Instrucciones dirigidas a evaluación en VM CentOS (GCP).** Se asume que se recibió el proyecto como archivo `.zip`.

---

## Índice

1. [Requisitos previos](#1-requisitos-previos)
2. [Extraer el proyecto](#2-extraer-el-proyecto)
3. [Instalar dependencias Python](#3-instalar-dependencias-python)
4. [Configurar PostgreSQL](#4-configurar-postgresql)
5. [Aplicar el esquema y los procedimientos](#5-aplicar-el-esquema-y-los-procedimientos)
6. [Instalar y configurar MongoDB](#6-instalar-y-configurar-mongodb)
7. [Configurar variables de entorno (.env)](#7-configurar-variables-de-entorno-env)
8. [Generar certificado TLS](#8-generar-certificado-tls)
9. [Abrir puertos en el firewall (GCP)](#9-abrir-puertos-en-el-firewall-gcp)
10. [Levantar la aplicación](#10-levantar-la-aplicación)
11. [Credenciales de prueba](#11-credenciales-de-prueba)
12. [Dispositivos IoT](#12-dispositivos-iot)
13. [Escenarios de demostración](#13-escenarios-de-demostración)

---

## 1. Requisitos previos

Instalar los paquetes base en CentOS:

```bash
sudo dnf install -y python3 python3-pip unzip openssl
```

### PostgreSQL + PostGIS

```bash
sudo dnf install -y postgresql-server postgresql-contrib
sudo postgresql-setup --initdb
sudo systemctl enable --now postgresql

# PostGIS — ajustar el número según la versión de PostgreSQL instalada
sudo dnf install -y postgis33_15
```

> Si el paquete `postgis33_15` no se encuentra, buscar el correcto con:
> ```bash
> sudo dnf search postgis
> ```

### MongoDB

```bash
sudo tee /etc/yum.repos.d/mongodb-org-8.0.repo <<'EOF'
[mongodb-org-8.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/8/mongodb-org/8.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-8.0.asc
EOF

sudo dnf install -y mongodb-org
sudo systemctl enable --now mongod
```

Verificar que está corriendo:
```bash
sudo systemctl status mongod
```

---

## 2. Extraer el proyecto

```bash
unzip proyecto-bda.zip -d ~/proyecto-bda
cd ~/proyecto-bda
```

---

## 3. Instalar dependencias Python

```bash
pip3 install -r requirements.txt
```

Dependencias incluidas: `Flask`, `psycopg` (v3), `python-dotenv`, `reportlab`, `bleak`, `requests`, `pymongo`.

---

## 4. Configurar PostgreSQL

### Crear usuario y base de datos

```bash
sudo -u postgres psql
```

Dentro de `psql`, ejecutar:

```sql
CREATE USER alzadmin WITH PASSWORD 'alzpass123';
CREATE DATABASE alzheimer OWNER alzadmin;
GRANT ALL PRIVILEGES ON DATABASE alzheimer TO alzadmin;
\q
```

### Habilitar PostGIS

```bash
sudo -u postgres psql -d alzheimer -c "CREATE EXTENSION IF NOT EXISTS postgis;"
```

### Permitir conexiones TCP con contraseña

```bash
sudo nano /var/lib/pgsql/data/pg_hba.conf
```

Buscar la línea con `127.0.0.1` y asegurarse de que el método sea `md5`:

```
host    all    all    127.0.0.1/32    md5
```

Reiniciar PostgreSQL:

```bash
sudo systemctl restart postgresql
```

---

## 5. Aplicar el esquema y los procedimientos

Desde el directorio del proyecto, ejecutar los archivos SQL en este orden exacto:

```bash
psql -U alzadmin -d alzheimer -f ProyectoFinalDDL.sql
psql -U alzadmin -d alzheimer -f RecetasProcedures.sql
psql -U alzadmin -d alzheimer -f BeaconProcedures.sql
psql -U alzadmin -d alzheimer -f AppProcedures.sql
psql -U alzadmin -d alzheimer -f TriggersDB.sql
psql -U alzadmin -d alzheimer -f DisableTriggers.sql
psql -U alzadmin -d alzheimer -f ViewsDB.sql
psql -U alzadmin -d alzheimer -f SelectProcedures.sql
```

Cada archivo imprimirá `NOTICE` de confirmación al terminar. Si alguno falla con error de permisos, ejecutar primero:

```bash
sudo -u postgres psql -d alzheimer -c "GRANT ALL ON SCHEMA public TO alzadmin;"
```

El archivo `ProyectoFinalDDL.sql` incluye datos semilla completos (pacientes, cuidadores, sedes, medicamentos, dispositivos, zonas seguras).

---

## 6. Instalar y configurar MongoDB

MongoDB almacena las lecturas IoT en tiempo real (GPS, NFC, Beacon). La base de datos y las colecciones se crean automáticamente al llegar el primer dato — no se requiere aplicar ningún esquema.

### Crear usuario de aplicación

```bash
mongosh
```

Dentro de `mongosh`:

```js
use admin
db.createUser({
  user: "alzadmin",
  pwd: "alzpass123",
  roles: [{ role: "readWrite", db: "alzmonitor" }]
})
exit
```

> Si MongoDB solicita autenticación al entrar (`mongosh`), usar:
> ```bash
> mongosh -u admin -p --authenticationDatabase admin
> ```
> e ingresar la contraseña del administrador del sistema MongoDB antes de ejecutar los comandos anteriores.

---

## 7. Configurar variables de entorno (.env)

Copiar el archivo de ejemplo y editarlo:

```bash
cp .env.example .env
nano .env
```

Contenido final del `.env`:

```env
SECRET_KEY=cualquier-cadena-aleatoria-aqui

ADMIN_USER=admin
ADMIN_PASSWORD=admin123

# PostgreSQL
DB_HOST=localhost
DB_PORT=5432
DB_NAME=alzheimer
DB_USER=alzadmin
DB_PASSWORD=alzpass123

# MongoDB
MONGO_URI=mongodb://alzadmin:alzpass123@localhost:27017/
MONGO_DB=alzmonitor
```

---

## 8. Generar certificado TLS

La app requiere HTTPS porque las APIs del navegador (Web NFC, Web Bluetooth) solo funcionan en contexto seguro. El certificado es autofirmado — el navegador mostrará advertencia al abrirlo por primera vez (es normal).

### Recomendación: usar una IP estática

Si la VM tiene una IP externa efímera (cambia al reiniciar), se recomienda reservar una IP estática en GCP antes de generar el certificado:

> **GCP Console → VPC Network → Direcciones IP → Reservar dirección externa estática**
> Seleccionar: Nivel de servicio **Estándar**, versión **IPv4**, tipo **Regional** (misma región que la VM).

Así el certificado generado sigue siendo válido aunque la VM se reinicie.

### Opción A — IP estática (recomendado)

Generar el certificado una sola vez con la IP fija:

```bash
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
  -days 365 -nodes \
  -subj "/CN=<IP_ESTATICA>" \
  -addext "subjectAltName=IP:<IP_ESTATICA>"
```

### Opción B — IP efímera (regenerar en cada reinicio)

Si no se reservó IP estática, obtener la IP actual y regenerar el certificado cada vez que la VM arranque:

```bash
MY_IP=$(curl -s ifconfig.me)
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
  -days 365 -nodes \
  -subj "/CN=$MY_IP" \
  -addext "subjectAltName=IP:$MY_IP"
```

Los archivos `cert.pem` y `key.pem` deben quedar en el directorio raíz del proyecto (donde está `app.py`).

---

## 9. Abrir puertos en el firewall (GCP)

La app usa dos puertos:

| Puerto | Protocolo | Uso |
|--------|-----------|-----|
| `5002` | HTTPS | Aplicación web principal |
| `5003` | HTTP | Receptor GPS (Traccar Client / OsmAnd) |

En GCP Console → VPC Network → Firewall:

1. Crear regla: nombre `allow-alz-5002`, protocolo TCP, puerto `5002`, destinos: todas las instancias
2. Crear regla: nombre `allow-alz-5003`, protocolo TCP, puerto `5003`, destinos: todas las instancias

Con `firewalld` en CentOS:

```bash
sudo firewall-cmd --permanent --add-port=5002/tcp
sudo firewall-cmd --permanent --add-port=5003/tcp
sudo firewall-cmd --reload
```

---

## 10. Levantar la aplicación

Desde el directorio raíz del proyecto:

```bash
python3 app.py
```

Salida esperada:

```
 * Traccar/OsmAnd HTTP listener on http://0.0.0.0:5003
 * Running on https://0.0.0.0:5002
```

Acceder desde el navegador:

```
https://<IP_DE_LA_VM>:5002
```

El navegador mostrará advertencia por certificado autofirmado. Para continuar:

- **Chrome / Edge:** clic en *Configuración avanzada* → *Acceder a X.X.X.X (no seguro)*
- **Firefox:** clic en *Avanzado* → *Aceptar el riesgo y continuar*
- **Safari:** clic en *Mostrar detalles* → *visitar este sitio web*

---

## 11. Credenciales de prueba

| Rol | Usuario / Email | Contraseña / PIN | URL de entrada |
|-----|----------------|-----------------|----------------|
| Administrador | `admin` | `admin123` | `/dashboard` |
| Personal clínico | `medico` | `medico123` | `/clinica` |
| Portal familiar | `lucia.garcia@demo.com` | `1234` | `/portal-familiar/login` |
| Portal familiar | `roberto.mendez@demo.com` | `1234` | `/portal-familiar/login` |

El rol administrador tiene acceso completo a todos los módulos. El rol médico tiene vista de solo lectura de su sede. El portal familiar muestra el estado del paciente vinculado al contacto.

---

## 12. Dispositivos IoT

El sistema integra tres capas de dispositivos. Cada uno debe estar registrado en **Admin → Dispositivos** antes de usarse.

---

### Capa 1 — GPS (teléfono Android con Traccar Client)

**Hardware:** teléfono Android con la app Traccar Client instalada (Google Play: *Traccar Client*).

**Registrar el dispositivo en la app:**
1. **Admin → Dispositivos → Nuevo dispositivo**
2. Tipo: `GPS`, ID: número entero libre, Serial: el identificador que se configure en Traccar Client (ej. `traccar-001`)

**Configurar Traccar Client en el teléfono:**
1. Abrir Traccar Client
2. **Identificador de dispositivo:** el mismo serial registrado en la app (ej. `traccar-001`)
3. **URL del servidor:** `http://<IP_DE_LA_VM>:5003` (HTTP, sin HTTPS)
4. Activar el seguimiento

El teléfono comenzará a enviar coordenadas GPS automáticamente. Las lecturas aparecen en **Admin → Dispositivos** (última batería) y activan los triggers de zona y batería baja.

**Simular GPS sin hardware (Admin → Sim GPS):**

También se puede enviar una lectura manualmente desde el panel de administración o por curl:

```bash
curl -k -X POST https://<IP>:5002/api/gps/lectura \
  -H "X-AlzMonitor-Key: alz-dev-2026" \
  -H "Content-Type: application/json" \
  -d '{
    "id_dispositivo": <ID_REGISTRADO>,
    "latitud": 19.4326,
    "longitud": -99.1332,
    "nivel_bateria": 80,
    "velocidad": 0,
    "altitud": 2240
  }'
```

Enviar `nivel_bateria` ≤ 15 dispara el trigger de batería baja → alerta automática en **Admin → Alertas**.

---

### Capa 2 — Beacon BLE (FeasyBeacon FSC-BP104D)

**Hardware:** beacon Bluetooth 5.1 iBeacon portado por el cuidador. UUID preconfigurado: `FDA50693-1000-1001`.

**Registrar el dispositivo en la app:**
1. **Admin → Dispositivos → Nuevo dispositivo**
2. Tipo: `BEACON`, ID: número entero libre, Serial: `FDA50693-1000-1001`

**Asignar beacon al cuidador:**
1. **Admin → Asignación de Beacons → Nueva asignación**
2. Seleccionar el beacon y el cuidador correspondiente

**Ejecutar el escáner BLE (`beacon_scanner.py`):**

> El escáner corre en la **computadora local** (Mac con Bluetooth), no en la VM. Requiere `bleak` y `requests`.

```bash
pip install bleak requests

# Apuntar al servidor en la VM
ALZMONITOR_URL="https://<IP_DE_LA_VM>:5002/api/beacon/deteccion" python3 beacon_scanner.py
```

Salida esperada cuando detecta el beacon:

```
==================================================
AlzMonitor — Escáner BLE
Reportando a: https://35.x.x.x:5002/api/beacon/deteccion
==================================================
[OK] Beacon 1001-1 | RSSI -68 dBm | Cuidador: Juan Martínez
```

Las detecciones aparecen en **Admin → Rondas**.

**Simular beacon sin hardware:**

```bash
curl -k -X POST https://<IP>:5002/api/beacon/deteccion \
  -H "X-AlzMonitor-Key: alz-dev-2026" \
  -H "Content-Type: application/json" \
  -d '{"uuid": "FDA50693-1000-1001", "major": 1001, "minor": 1, "rssi": -70}'
```

---

### Capa 3 — NFC (pulsera DESFire del paciente)

**Hardware:** pulsera NFC ISO 14443A portada por el paciente. El cuidador acerca su teléfono Android (Chrome) para registrar la toma de medicamentos.

**Registrar el dispositivo en la app:**
1. **Admin → Dispositivos → Nuevo dispositivo**
2. Tipo: `NFC`, ID: número entero libre, Serial: el UID de la pulsera (formato `04:XX:XX:XX:XX:XX`)

**Activar la pulsera en una receta:**
1. **Admin → Recetas → [receta del paciente] → Activar NFC**
2. Seleccionar el dispositivo NFC registrado

**Usar con hardware real (Chrome Android):**
1. El cuidador abre `https://<IP_DE_LA_VM>:5002/cuidador/escanear` en Chrome para Android
2. Acerca el teléfono a la pulsera del paciente → se registra la lectura automáticamente

> Web NFC solo funciona en Chrome para Android en contexto HTTPS.

**Simular NFC sin hardware:**

```bash
curl -k -X POST https://<IP>:5002/api/nfc/lectura \
  -H "X-AlzMonitor-Key: alz-dev-2026" \
  -H "Content-Type: application/json" \
  -d '{"serial": "<SERIAL_NFC>", "tipo_lectura": "Administración", "resultado": "Exitosa"}'
```

Las lecturas y el porcentaje de adherencia (últimos 30 días) se visualizan en el detalle de cada receta.

---

## 13. Escenarios de demostración

### Escenario 1 — Salida de zona y escalamiento de alertas

1. Ir a **Admin → Sim GPS**
2. Seleccionar un paciente con kit GPS asignado
3. Ingresar coordenadas fuera de cualquier zona segura del paciente
4. Ir a **Admin → Alertas** → aparece alerta `Salida de Zona` con origen IoT, regla disparada y cadena de contactos de emergencia con prioridad numerada

### Escenario 2 — Cambio de sede sin pérdida de historial

1. **Admin → Pacientes → [paciente] → Historial → Transferir sede**
2. Seleccionar sede destino → confirmar
3. El historial completo de sedes se conserva en la tabla `sede_pacientes`

### Escenario 3 — Cambio de tratamiento y adherencia NFC

1. **Admin → Recetas → Nueva receta** para un paciente
2. Agregar medicamentos con dosis y frecuencia
3. **Activar NFC** → asignar serial de pulsera
4. Simular lecturas NFC (ver sección 12 — Capa 3 para el comando curl)
5. El detalle de la receta muestra % de adherencia a 30 días por medicamento

### Escenario 4 — Falla de batería y reemplazo de kit GPS

1. **Admin → Sim GPS** → enviar lectura con `nivel_bateria = 10`
2. El trigger `trg_bateria_baja_gps` inserta alerta `Batería Baja` automáticamente
3. **Admin → Pacientes → Historial → Cambiar kit GPS** → seleccionar nuevo dispositivo
4. El kit anterior queda con `fecha_fin` en el historial; el nuevo queda activo

### Escenario 5 — Inventario crítico multisede

1. **Admin → Farmacia** → ver medicamentos con stock crítico resaltados en rojo por sede
2. Ajustar stock directamente desde la tabla
3. Crear orden de suministro para reabastecer

---

## Tecnologías

| Capa | Tecnología |
|------|-----------|
| Backend | Python 3.12 · Flask |
| Base de datos relacional | PostgreSQL 15 · PostGIS 3 |
| Base de datos documental | MongoDB 8 |
| Acceso a datos | `psycopg` v3 · `pymongo` · sin SQL embebido en Python |
| Procedimientos almacenados | 138 SPs `sp_sel_*` · 32 SPs DML · 10 SPs módulo receta/NFC |
| Vistas | 114 vistas de solo lectura |
| Triggers | 3 triggers de base de datos (zona GPS, batería baja, cobertura beacon) |
| Reportes PDF | ReportLab |
| Frontend | Jinja2 · CSS custom properties · Vanilla JS |
| IoT | GPS/GPRS via Traccar · BLE 5.1 via `bleak` · NFC ISO 14443A via Web NFC API |
| Mapas | Leaflet.js (portal familiar) · PostGIS `ST_DWithin` (validación de zonas) |
| TLS | Certificado autofirmado (openssl) |
