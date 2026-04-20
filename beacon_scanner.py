#!/usr/bin/env python3
"""
AlzMonitor BLE Beacon Scanner
Runs on the central computer alongside Flask.
Detects caregiver beacons and reports detections to the Flask API.

Usage:
    python beacon_scanner.py

Requirements:
    pip install bleak requests
"""

import asyncio
import struct
import time
import requests
from bleak import BleakScanner

FLASK_URL      = "http://136.112.31.69:5000/api/beacon/deteccion"
API_KEY        = "alz-dev-2026"
SCAN_INTERVAL  = 5    # seconds per scan cycle
REPORT_COOLDOWN = 10  # seconds before re-reporting the same beacon
IBEACON_COMPANY_ID = 0x004C

last_reported = {}


def parse_ibeacon(manufacturer_data):
    apple_data = manufacturer_data.get(IBEACON_COMPANY_ID)
    if not apple_data or len(apple_data) < 23:
        return None
    if apple_data[0] != 0x02 or apple_data[1] != 0x15:
        return None

    uuid_bytes = apple_data[2:18]
    uuid = '-'.join([
        uuid_bytes[0:4].hex(),
        uuid_bytes[4:6].hex(),
        uuid_bytes[6:8].hex(),
        uuid_bytes[8:10].hex(),
        uuid_bytes[10:16].hex()
    ]).upper()

    major = struct.unpack('>H', apple_data[18:20])[0]
    minor = struct.unpack('>H', apple_data[20:22])[0]
    return uuid, major, minor


def report_detection(uuid, major, minor, rssi):
    beacon_key = f"{major}-{minor}"
    now = time.time()

    if beacon_key in last_reported and (now - last_reported[beacon_key]) < REPORT_COOLDOWN:
        return

    last_reported[beacon_key] = now

    try:
        response = requests.post(
            FLASK_URL,
            json={
                "uuid": uuid,
                "major": major,
                "minor": minor,
                "rssi": rssi,
                "gateway_id": "central",
            },
            headers={"X-AlzMonitor-Key": API_KEY},
            verify=False,
            timeout=5
        )

        if response.status_code == 200:
            data = response.json()
            print(f"[OK] Beacon {major}-{minor} | RSSI {rssi} dBm | Cuidador: {data.get('caregiver_name', '?')}")
        elif response.status_code == 400:
            print(f"[--] Beacon {major}-{minor} no registrado en el sistema")
        else:
            print(f"[ERR] Servidor respondió {response.status_code}")

    except requests.exceptions.ConnectionError:
        print("[ERR] No se puede conectar a Flask — ¿está corriendo el servidor?")
    except Exception as e:
        print(f"[ERR] {e}")


def detection_callback(device, advertisement_data):
    if not advertisement_data.manufacturer_data:
        return
    result = parse_ibeacon(advertisement_data.manufacturer_data)
    if result is None:
        return
    uuid, major, minor = result
    report_detection(uuid, major, minor, advertisement_data.rssi)


async def main():
    print("=" * 50)
    print("AlzMonitor — Escáner BLE")
    print(f"Reportando a: {FLASK_URL}")
    print(f"Intervalo de escaneo: {SCAN_INTERVAL}s")
    print("=" * 50)
    print("Escaneando beacons... (Ctrl+C para detener)\n")

    scanner = BleakScanner(detection_callback)

    while True:
        await scanner.start()
        await asyncio.sleep(SCAN_INTERVAL)
        await scanner.stop()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nEscáner detenido.")
