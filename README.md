# AlzMonitor

Sistema de gestión clínica multisede para pacientes de Alzheimer, desarrollado como proyecto final de la materia de Bases de Datos Avanzadas (BDA). Integra PostgreSQL + PostGIS, procedimientos almacenados, triggers de base de datos y una arquitectura IoT de tres capas: GPS, beacons BLE y pulseras NFC.

---

## Índice

1. [Requisitos previos](#1-requisitos-previos)
2. [Instalación de dependencias Python](#2-instalación-de-dependencias-python)
3. [Instalar y configurar MongoDB](#3-instalar-y-configurar-mongodb)
4. [Configurar PostgreSQL](#4-configurar-postgresql)
5. [Aplicar el esquema y los procedimientos](#5-aplicar-el-esquema-y-los-procedimientos)
6. [Configurar variables de entorno (.env)](#6-configurar-variables-de-entorno-env)
7. [Generar certificado TLS](#7-generar-certificado-tls)
8. [Abrir puertos en el firewall](#8-abrir-puertos-en-el-firewall)
9. [Levantar la aplicación](#9-levantar-la-aplicación)
10. [Credenciales de prueba](#10-credenciales-de-prueba)
11. [beacon_scanner.py — escáner BLE local](#11-beacon_scannerpy--escáner-ble-local)
12. [Agregar dispositivos propios y probarlos](#12-agregar-dispositivos-propios-y-probarlos)
13. [Escenarios de demostración](#13-escenarios-de-demostración)

---

## 1. Requisitos previos

| Software | Versión mínima | Notas |
|----------|---------------|-------|
| Python | 3.10+ | |
| PostgreSQL | 14+ | Con extensión PostGIS |
| PostGIS | 3.x | Ver instrucciones abajo |
| OpenSSL | cualquiera | Incluido en Linux/macOS |

### Instalar PostGIS

**Ubuntu / Debian (GCP):**
```bash
sudo apt update
sudo apt install -y postgresql postgresql-contrib python3-pip
# PostGIS — ajustar versión según `psql --version`
sudo apt install -y postgresql-15-postgis-3
# Si el comando anterior falla, buscar el paquete correcto:
apt-cache search postgis
```

**CentOS / RHEL:**
```bash
sudo dnf install -y postgresql-server postgresql-contrib
sudo postgresql-setup --initdb
sudo systemctl enable --now postgresql
sudo dnf install -y postgis33_15   # ajustar según versión de PG
```

**macOS:**
```bash
brew install postgresql@15 postgis
brew services start postgresql@15
```

---

## 2. Instalación de dependencias Python

Desde el directorio del proyecto:
```bash
pip install -r requirements.txt
```

Dependencias incluidas: `Flask`, `psycopg` (v3), `python-dotenv`, `reportlab`, `bleak`, `requests`, `pymongo`.

---

## 3. Instalar y configurar MongoDB

MongoDB se usa como almacén secundario para las lecturas IoT (GPS, Beacon, NFC). Si MongoDB no está disponible, la aplicación sigue funcionando — las escrituras fallidas se registran solo en el log.

### Instalar MongoDB Community Edition

**Ubuntu / Debian (GCP):**
```bash
sudo apt install -y gnupg curl
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo apt update
sudo apt install -y mongodb-org
sudo systemctl enable --now mongod
```

**CentOS / RHEL:**
```bash
cat <<EOF | sudo tee /etc/yum.repos.d/mongodb-org-7.0.repo
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
EOF
sudo dnf install -y mongodb-org
sudo systemctl enable --now mongod
```

**macOS:**
```bash
brew tap mongodb/brew
brew install mongodb-community
brew services start mongodb-community
```

### Verificar que MongoDB esté corriendo

```bash
mongosh --eval "db.runCommand({ ping: 1 })"
# Debe responder: { ok: 1 }
```

No se requiere crear la base de datos manualmente — la app la crea automáticamente al insertar la primera lectura.

---

## 4. Configurar PostgreSQL

### Crear usuario y base de datos

```bash
# Entrar como superusuario de PostgreSQL
sudo -u postgres psql

# Dentro de psql:
CREATE USER alzadmin WITH PASSWORD 'alzpass123';
CREATE DATABASE alzheimer OWNER alzadmin;
GRANT ALL PRIVILEGES ON DATABASE alzheimer TO alzadmin;
\q
```

> Se puede usar cualquier nombre de usuario y contraseña — solo recordarlos para el `.env` del paso 6.

### Verificar que PostGIS esté disponible

```bash
sudo -u postgres psql -d alzheimer -c "CREATE EXTENSION IF NOT EXISTS postgis;"
```

Si da error, la extensión PostGIS no está instalada — volver al paso 1.

### Permitir conexiones TCP locales (si aplica)

En la mayoría de instalaciones, `localhost` con contraseña ya funciona. Si psql da error de autenticación, editar `pg_hba.conf`:

```bash
# Ubuntu
sudo nano /etc/postgresql/15/main/pg_hba.conf

# CentOS
sudo nano /var/lib/pgsql/data/pg_hba.conf
```

Buscar la línea de `127.0.0.1` y cambiar el método a `md5` (o `trust` para simplificar en entorno de pruebas):
```
host    all    all    127.0.0.1/32    md5
```

Luego reiniciar PostgreSQL:
```bash
sudo systemctl restart postgresql
```

---

## 5. Aplicar el esquema y los procedimientos

Ejecutar los archivos SQL en este orden exacto. Reemplazar `alzadmin` con el usuario creado en el paso 3.

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

## 6. Configurar variables de entorno (.env)

Copiar el archivo de ejemplo y editarlo:

```bash
cp .env.example .env
nano .env   # o el editor de preferencia
```

Contenido a ajustar:

```env
SECRET_KEY=cualquier-cadena-aleatoria-aqui

ADMIN_USER=admin
ADMIN_PASSWORD=admin123

DB_HOST=localhost
DB_PORT=5432
DB_NAME=alzheimer
DB_USER=alzadmin        # usuario creado en el paso 4
DB_PASSWORD=alzpass123  # contraseña del paso 4

MONGO_URI=mongodb://localhost:27017/
MONGO_DB=alzmonitor
```

> Si se usó Unix socket en lugar de TCP (macOS con Homebrew, o instalación local sin contraseña), cambiar `DB_HOST` al path del socket:
> - macOS Homebrew: `DB_HOST=/tmp`
> - Ubuntu: `DB_HOST=/var/run/postgresql`
> - Y dejar `DB_PASSWORD=` vacío

---

## 7. Generar certificado TLS

La app requiere HTTPS porque las APIs del navegador (Web NFC, Web Bluetooth) solo funcionan en contexto seguro. El certificado es autofirmado — el navegador mostrará advertencia de seguridad (es normal).

```bash
# Reemplazar <IP_O_HOSTNAME> con la IP de la máquina o localhost
openssl req -x509 -newkey rsa:2048 \
  -keyout key.pem -out cert.pem \
  -days 365 -nodes \
  -subj "/CN=<IP_O_HOSTNAME>" \
  -addext "subjectAltName=IP:<IP_O_HOSTNAME>"
```

Ejemplos:
```bash
# Si se accede desde la misma máquina (localhost)
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
  -days 365 -nodes -subj "/CN=127.0.0.1" \
  -addext "subjectAltName=IP:127.0.0.1"

# Si se accede desde otra máquina / red (poner la IP de esta VM)
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
  -days 365 -nodes -subj "/CN=34.x.x.x" \
  -addext "subjectAltName=IP:34.x.x.x"
```

Los archivos `cert.pem` y `key.pem` deben quedar en el directorio raíz del proyecto (donde está `app.py`).

---

## 8. Abrir puertos en el firewall

La app usa dos puertos:

| Puerto | Protocolo | Uso |
|--------|-----------|-----|
| `5002` | HTTPS | Aplicación web principal |
| `5003` | HTTP | Receptor GPS (Traccar Client / OsmAnd) |

### En GCP (Google Cloud Platform)

1. Ir a **VPC Network → Firewall** en GCP Console
2. Crear regla: nombre `allow-alz-5002`, protocolo TCP, puerto `5002`, targets: all instances
3. Crear regla: nombre `allow-alz-5003`, protocolo TCP, puerto `5003`, targets: all instances

### En Ubuntu con ufw

```bash
sudo ufw allow 5002/tcp
sudo ufw allow 5003/tcp
```

### En CentOS con firewalld

```bash
sudo firewall-cmd --permanent --add-port=5002/tcp
sudo firewall-cmd --permanent --add-port=5003/tcp
sudo firewall-cmd --reload
```

---

## 9. Levantar la aplicación

```bash
python app.py
```

Salida esperada:
```
 * Traccar/OsmAnd HTTP listener on http://0.0.0.0:5003
 * Running on https://0.0.0.0:5002
```

### Acceder desde el navegador

```
https://<IP_DE_LA_VM>:5002
```

El navegador mostrará advertencia por certificado autofirmado. Para continuar:

- **Chrome / Edge:** clic en *Configuración avanzada* → *Acceder a X.X.X.X (no seguro)*
- **Firefox:** clic en *Avanzado* → *Aceptar el riesgo y continuar*
- **Safari:** clic en *Mostrar detalles* → *visitar este sitio web*

---

## 10. Credenciales de prueba

| Rol | Usuario / Email | Contraseña / PIN | URL de entrada |
|-----|----------------|-----------------|----------------|
| Administrador | `admin` | `admin123` | `/dashboard` |
| Personal clínico | `medico` | `medico123` | `/clinica` |
| Portal familiar | `lucia.garcia@demo.com` | `1234` | `/portal-familiar/login` |
| Portal familiar | `roberto.mendez@demo.com` | `1234` | `/portal-familiar/login` |

El rol administrador tiene acceso completo a todos los módulos. El rol médico tiene vista de solo lectura de su sede. El portal familiar muestra el estado del paciente vinculado al contacto.

---

## 11. beacon_scanner.py — escáner BLE local

Este script corre en una **Mac local** con Bluetooth (no en la VM), detecta beacons BLE de los cuidadores y los reporta a la app.

### Requisitos

```bash
pip install bleak requests
```

### Ejecutar apuntando a la VM

```bash
ALZMONITOR_URL="https://<IP_DE_LA_VM>:5002/api/beacon/deteccion" python beacon_scanner.py
```

### Qué hace

Escanea en busca de beacons iBeacon continuamente. Cuando detecta el beacon registrado (`FeasyBeacon FSC-BP104D`, UUID `FDA50693-1000-1001`), POSTea a la app y la detección aparece en **Admin → Rondas**.

Salida esperada:
```
==================================================
AlzMonitor — Escáner BLE
Reportando a: https://34.x.x.x:5002/api/beacon/deteccion
Intervalo de escaneo: 5s
==================================================
[OK] Beacon 1001-1 | RSSI -68 dBm | Cuidador: Juan Martínez
```

---

## 12. Agregar dispositivos propios y probarlos

### Registrar el dispositivo

**Admin → Dispositivos → Nuevo dispositivo**

| Campo | GPS | Beacon BLE | Pulsera NFC |
|-------|-----|-----------|-------------|
| Tipo | `GPS` | `BEACON` | `NFC` |
| ID | número entero libre | número entero libre | número entero libre |
| Serial | IMEI o identificador | UUID del beacon | `04:XX:XX:XX:XX:XX` |

### Probar GPS (sin hardware físico)

Usar el simulador en **Admin → Sim GPS** o via API:

```bash
curl -k -X POST https://localhost:5002/api/gps/lectura \
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

Enviar `nivel_bateria` ≤ 15 dispara el trigger `trg_bateria_baja_gps` → alerta automática en **Admin → Alertas**.

### Probar NFC (sin pulsera física)

```bash
curl -k -X POST https://localhost:5002/api/nfc/lectura \
  -H "X-AlzMonitor-Key: alz-dev-2026" \
  -H "Content-Type: application/json" \
  -d '{"serial": "<SERIAL_NFC>", "tipo_lectura": "Administración", "resultado": "Exitosa"}'
```

### Probar beacon (sin hardware BLE)

```bash
curl -k -X POST https://localhost:5002/api/beacon/deteccion \
  -H "X-AlzMonitor-Key: alz-dev-2026" \
  -H "Content-Type: application/json" \
  -d '{"uuid": "FDA50693-1000-1001", "major": 1001, "minor": 1, "rssi": -70}'
```

### Asignar dispositivo a paciente

- **Kit GPS:** Admin → Pacientes → [paciente] → Historial → Asignar kit GPS
- **Pulsera NFC:** Admin → Recetas → [receta] → Activar NFC
- **Beacon a cuidador:** Admin → Asignación de Beacons

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
4. Simular lecturas NFC con el comando curl de la sección anterior
5. El detalle de la receta muestra % de adherencia a 30 días por medicamento

### Escenario 4 — Falla de batería y reemplazo de kit GPS

1. **Sim GPS** → enviar lectura con `nivel_bateria = 10`
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
| Base de datos | PostgreSQL 15 · PostGIS 3 |
| Acceso a datos | `psycopg` v3 · `RealDictCursor` · sin SQL embebido en Python |
| Procedimientos almacenados | 138 SPs `sp_sel_*` · 32 SPs DML · 10 SPs módulo receta/NFC |
| Vistas | 114 vistas de solo lectura |
| Triggers | 3 triggers de base de datos (zona GPS, batería baja, cobertura beacon) |
| Reportes PDF | ReportLab |
| Frontend | Jinja2 · CSS custom properties · Vanilla JS |
| IoT | GPS/GPRS via Traccar · BLE 5.1 via `bleak` · NFC ISO 14443A via Web NFC API |
| Mapas | Leaflet.js (portal familiar) · PostGIS `ST_DWithin` (validación de zonas) |
| TLS | Certificado autofirmado (openssl) |

### Guía interactiva de procedimientos almacenados

Con sesión de admin: `https://<IP>:5002/procedimientos`

Muestra todos los SPs con parámetros, ubicación en el código y sintaxis CALL lista para copiar.
