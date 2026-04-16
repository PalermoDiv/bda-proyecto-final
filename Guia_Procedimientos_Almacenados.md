# Guía de Uso — Procedimientos Almacenados
## AlzMonitor · Módulo Recetas y NFC
### Base de datos: `alzheimer` · Archivo: `RecetasProcedures.sql`

---

Todos los procedimientos siguen la misma convención:

- Se invocan con `CALL nombre_procedimiento(param1, param2, ...);`
- Los IDs se asignan manualmente desde la aplicación (`COALESCE(MAX(id), 0) + 1`)
- Los errores se propagan con `RAISE EXCEPTION` y Flask los captura como excepciones Python
- Cada procedimiento corre dentro de una transacción implícita — si falla, no deja datos a medias

Desde la aplicación web todos están disponibles en sus respectivos formularios. Desde psql se pueden invocar directamente con los bloques `BEGIN / CALL / COMMIT` que se muestran abajo.

---

## 1. `sp_receta_crear`

**Qué hace:** Crea una nueva receta vacía para un paciente. La receta empieza sin medicamentos; se agregan después.

**Precondiciones:**
- El paciente debe existir y no estar dado de baja (`id_estado != 3`)
- El `id_receta` no debe estar en uso

**Parámetros:**

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `p_id_receta` | `INTEGER` | ID de la nueva receta (asignado por la app) |
| `p_id_paciente` | `INTEGER` | Paciente al que pertenece la receta |
| `p_fecha` | `DATE` | Fecha de emisión |

**Tablas modificadas:** `recetas`

**Desde la app:** Formulario en `/recetas/nueva`

**Uso directo:**
```sql
BEGIN;
CALL sp_receta_crear(10, 3, CURRENT_DATE);
COMMIT;
```

**Errores posibles:**
- `'Paciente X no encontrado o dado de baja.'`
- `'Ya existe una receta con ID X.'`

---

## 2. `sp_receta_agregar_medicamento`

**Qué hace:** Agrega un medicamento a una receta existente, especificando dosis y frecuencia de administración.

**Precondiciones:**
- La receta debe existir
- El GTIN debe existir en la tabla `medicamentos`
- La frecuencia debe ser mayor a cero

**Parámetros:**

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `p_id_detalle` | `INTEGER` | PK del renglón (asignado por la app) |
| `p_id_receta` | `INTEGER` | Receta a la que se agrega el medicamento |
| `p_gtin` | `VARCHAR` | Código GTIN del medicamento |
| `p_dosis` | `VARCHAR` | Dosis prescrita, ej. `'10mg'`, `'1 comprimido'` |
| `p_frecuencia_horas` | `INTEGER` | Cada cuántas horas se administra, ej. `8`, `12`, `24` |

**Tablas modificadas:** `receta_medicamentos`

**Desde la app:** Botón "Agregar" dentro del detalle de la receta (`/recetas/<id>`)

**Uso directo:**
```sql
BEGIN;
CALL sp_receta_agregar_medicamento(50, 10, '07501234567890', '10mg', 8);
COMMIT;
```

**Errores posibles:**
- `'Receta X no encontrada.'`
- `'Medicamento con GTIN X no encontrado.'`
- `'La frecuencia debe ser mayor a cero horas.'`

---

## 3. `sp_receta_quitar_medicamento`

**Qué hace:** Elimina un medicamento de una receta. Opera sobre el `id_detalle` (PK de `receta_medicamentos`), no sobre el GTIN, porque el mismo medicamento podría estar prescrito con distintas dosis.

**Precondiciones:**
- El renglón (`id_detalle`) debe existir y pertenecer a la receta indicada

**Parámetros:**

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `p_id_detalle` | `INTEGER` | ID del renglón de medicamento a eliminar |
| `p_id_receta` | `INTEGER` | Receta propietaria (validación de pertenencia) |

**Tablas modificadas:** `receta_medicamentos`

**Desde la app:** Botón "Quitar" por medicamento en el detalle de la receta

**Uso directo:**
```sql
BEGIN;
CALL sp_receta_quitar_medicamento(50, 10);
COMMIT;
```

**Errores posibles:**
- `'El detalle X no pertenece a la receta X.'`

---

## 4. `sp_receta_actualizar_medicamento`

**Qué hace:** Modifica la dosis y/o la frecuencia de un medicamento ya prescrito en una receta activa. No cambia el medicamento en sí — para eso hay que quitar y volver a agregar.

**Precondiciones:**
- La receta debe estar en estado `'Activa'`
- El renglón debe pertenecer a esa receta
- La nueva frecuencia debe ser mayor a cero

**Parámetros:**

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `p_id_detalle` | `INTEGER` | ID del renglón a actualizar |
| `p_id_receta` | `INTEGER` | Receta propietaria |
| `p_dosis` | `VARCHAR` | Nueva dosis |
| `p_frecuencia_horas` | `INTEGER` | Nueva frecuencia en horas |

**Tablas modificadas:** `receta_medicamentos`

**Desde la app:** Botón "Editar" por medicamento en el detalle de la receta

**Uso directo:**
```sql
BEGIN;
CALL sp_receta_actualizar_medicamento(50, 10, '20mg', 12);
COMMIT;
```

**Errores posibles:**
- `'Receta X no está activa.'`
- `'El detalle X no pertenece a la receta X.'`
- `'La frecuencia debe ser mayor a cero horas.'`

---

## 5. `sp_receta_activar_nfc`

**Qué hace:** Vincula un dispositivo NFC (pulsera) a una receta, iniciando el seguimiento de adherencia terapéutica. A partir de este momento, cuando el cuidador escanea la pulsera, las lecturas quedan ligadas a esta receta.

**Precondiciones:**
- La receta debe existir
- El dispositivo debe ser de tipo `'NFC'`
- La receta **no** debe tener ya un vínculo NFC activo (una sola pulsera por receta)

**Parámetros:**

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `p_id_receta` | `INTEGER` | Receta a vincular |
| `p_id_dispositivo` | `INTEGER` | Dispositivo NFC |
| `p_fecha_inicio` | `DATE` | Fecha de inicio del vínculo |

**Tablas modificadas:** `receta_nfc`

**Desde la app:** Botón "Asignar pulsera" en el detalle de la receta (aparece cuando la receta no tiene NFC activo)

**Uso directo:**
```sql
BEGIN;
CALL sp_receta_activar_nfc(10, 5, CURRENT_DATE);
COMMIT;
```

**Errores posibles:**
- `'Receta X no encontrada.'`
- `'El dispositivo X no es de tipo NFC o no existe.'`
- `'La receta X ya tiene un dispositivo NFC activo. Ciérralo primero.'`

---

## 6. `sp_receta_cerrar_nfc`

**Qué hace:** Cierra el vínculo activo entre una receta y su pulsera NFC, registrando la fecha de fin. Las lecturas anteriores se conservan en el historial.

**Cuándo usarlo:** Cuando la pulsera se pierde, se daña, o cuando se quiere reemplazar por otra sin usar el procedimiento de cambio atómico.

**Precondiciones:**
- Debe existir un vínculo activo (`fecha_fin_gestion IS NULL`) entre esa receta y ese dispositivo

**Parámetros:**

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `p_id_receta` | `INTEGER` | Receta propietaria |
| `p_id_dispositivo` | `INTEGER` | Dispositivo NFC a desvincular |
| `p_fecha_fin` | `DATE` | Fecha de cierre del vínculo |

**Tablas modificadas:** `receta_nfc` (UPDATE — escribe `fecha_fin_gestion`)

**Desde la app:** Botón "Desvincular" en el detalle de la receta (aparece cuando hay pulsera activa)

**Uso directo:**
```sql
BEGIN;
CALL sp_receta_cerrar_nfc(10, 5, CURRENT_DATE);
COMMIT;
```

**Errores posibles:**
- `'No hay vínculo NFC activo entre receta X y dispositivo X.'`

---

## 7. `sp_receta_cambiar_nfc`

**Qué hace:** Reemplaza la pulsera NFC de una receta en un solo paso atómico — cierra el vínculo con la pulsera actual e inmediatamente abre uno nuevo con la pulsera de reemplazo. Garantiza que no haya ningún momento sin cobertura NFC en el historial.

**Cuándo usarlo:** Cuando la pulsera se daña y ya se tiene una de reemplazo disponible. Preferir este procedimiento sobre hacer `cerrar_nfc` + `activar_nfc` por separado.

**Precondiciones:**
- La receta debe tener un vínculo NFC activo
- El nuevo dispositivo debe ser de tipo `'NFC'`

**Parámetros:**

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `p_id_receta` | `INTEGER` | Receta propietaria |
| `p_id_dispositivo_nuevo` | `INTEGER` | Nueva pulsera NFC |
| `p_fecha_cambio` | `DATE` | Fecha del reemplazo |

**Tablas modificadas:** `receta_nfc` (UPDATE del registro actual + INSERT del nuevo)

**Desde la app:** Botón "Cambiar" en el detalle de la receta (aparece cuando hay pulsera activa)

**Uso directo:**
```sql
BEGIN;
CALL sp_receta_cambiar_nfc(10, 7, CURRENT_DATE);
COMMIT;
```

**Errores posibles:**
- `'La receta X no tiene un NFC activo para reemplazar.'`
- `'El dispositivo X no es de tipo NFC o no existe.'`

---

## 8. `sp_nfc_registrar_lectura`

**Qué hace:** Registra una lectura NFC de administración de medicamento. Es el procedimiento central del módulo de adherencia terapéutica. Valida que el vínculo entre la pulsera y la receta esté activo antes de insertar.

**Cuándo se llama:** Automáticamente cuando el cuidador toca la pulsera del paciente con su teléfono Android en la webapp `/cuidador/escanear`. El endpoint `POST /api/nfc/lectura` resuelve el dispositivo por serial y llama a este procedimiento.

**Precondiciones:**
- Debe existir un vínculo activo en `receta_nfc` entre el dispositivo y la receta
- `tipo_lectura` debe ser `'Administración'` o `'Verificación'`
- `resultado` debe ser `'Exitosa'` o `'Fallida'`

**Parámetros:**

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `p_id_lectura_nfc` | `INTEGER` | PK de la lectura (asignado por la app) |
| `p_id_dispositivo` | `INTEGER` | Dispositivo NFC que se leyó |
| `p_id_receta` | `INTEGER` | Receta vinculada al dispositivo |
| `p_fecha_hora` | `TIMESTAMP` | Momento de la lectura (normalmente `NOW()`) |
| `p_tipo_lectura` | `VARCHAR` | `'Administración'` — medicamento administrado; `'Verificación'` — solo confirmación de presencia |
| `p_resultado` | `VARCHAR` | `'Exitosa'` — lectura correcta; `'Fallida'` — error en el escaneo |

**Tablas modificadas:** `lecturas_nfc`

**Desde la app:** `POST /api/nfc/lectura` (caregiver scanner) — no hay formulario manual

**Uso directo:**
```sql
BEGIN;
CALL sp_nfc_registrar_lectura(200, 5, 10, NOW(), 'Administración', 'Exitosa');
COMMIT;
```

**Errores posibles:**
- `'No hay vínculo NFC activo entre receta X y dispositivo X.'`
- `'tipo_lectura inválido: X. Usar Administración o Verificación.'`
- `'resultado inválido: X. Usar Exitosa o Fallida.'`

---

## 9. `sp_receta_cerrar`

**Qué hace:** Cierra completamente una receta. Escribe `fecha_fin_gestion` en todos los vínculos NFC activos de esa receta. La receta y su historial de lecturas se conservan — no se elimina nada.

**Cuándo usarlo:** Cuando el paciente completa su tratamiento, cambia de esquema terapéutico, o es dado de alta.

**Precondiciones:**
- La receta debe existir

**Parámetros:**

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `p_id_receta` | `INTEGER` | Receta a cerrar |
| `p_fecha_fin` | `DATE` | Fecha de cierre (normalmente `CURRENT_DATE`) |

**Tablas modificadas:** `receta_nfc` (UPDATE — cierra todos los vínculos NFC activos)

**Desde la app:** Botón "Cerrar receta" en el encabezado del detalle de la receta (solo aparece si la receta está Activa)

**Uso directo:**
```sql
BEGIN;
CALL sp_receta_cerrar(10, CURRENT_DATE);
COMMIT;
```

**Errores posibles:**
- `'Receta X no encontrada.'`

---

## 10. `sp_nfc_asignar`

**Qué hace:** Asigna (o reasigna) un dispositivo NFC directamente a un paciente en la tabla `asignacion_nfc`. Esta asignación es la identidad física del paciente — vincula la pulsera con la persona, independientemente de cualquier receta. Cierra automáticamente cualquier asignación activa previa del paciente o del dispositivo antes de crear la nueva.

**Diferencia con `sp_receta_activar_nfc`:**
- `sp_nfc_asignar` vincula la pulsera al **paciente** (identidad)
- `sp_receta_activar_nfc` vincula la pulsera a una **receta** (adherencia terapéutica)
- Ambas pueden coexistir y son independientes

**Precondiciones:**
- El paciente debe existir y no estar dado de baja
- El dispositivo debe ser de tipo `'NFC'`

**Parámetros:**

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `p_id_paciente` | `INTEGER` | Paciente receptor |
| `p_id_dispositivo` | `INTEGER` | Dispositivo NFC |

**Tablas modificadas:** `asignacion_nfc` (cierra asignación anterior si existe, luego INSERT)

**Desde la app:** Botón "Asignar NFC" en el historial del paciente (`/pacientes/<id>/historial`)

**Uso directo:**
```sql
BEGIN;
CALL sp_nfc_asignar(3, 5);
COMMIT;
```

**Errores posibles:**
- `'Paciente X no encontrado o dado de baja.'`
- `'Dispositivo X no es de tipo NFC o no existe.'`

---

## Flujo completo de ejemplo

El siguiente flujo muestra el ciclo de vida completo de una receta con adherencia NFC:

```sql
-- 1. Crear la receta para el paciente #3
BEGIN;
CALL sp_receta_crear(10, 3, CURRENT_DATE);
COMMIT;

-- 2. Agregar dos medicamentos
BEGIN;
CALL sp_receta_agregar_medicamento(50, 10, '07501234567890', '10mg', 8);
CALL sp_receta_agregar_medicamento(51, 10, '07509876543210', '5mg', 12);
COMMIT;

-- 3. Asignar la pulsera NFC al paciente (identidad física)
BEGIN;
CALL sp_nfc_asignar(3, 5);
COMMIT;

-- 4. Vincular la pulsera a la receta (seguimiento de adherencia)
BEGIN;
CALL sp_receta_activar_nfc(10, 5, CURRENT_DATE);
COMMIT;

-- 5. [En producción: el cuidador escanea → POST /api/nfc/lectura → llama automáticamente:]
BEGIN;
CALL sp_nfc_registrar_lectura(200, 5, 10, NOW(), 'Administración', 'Exitosa');
COMMIT;

-- 6. Semanas después, se cambia la pulsera por una de reemplazo
BEGIN;
CALL sp_receta_cambiar_nfc(10, 7, CURRENT_DATE);
COMMIT;

-- 7. El tratamiento concluye
BEGIN;
CALL sp_receta_cerrar(10, CURRENT_DATE);
COMMIT;
```

---

## Referencia rápida

| # | Procedimiento | Tabla principal | Acción |
|---|--------------|----------------|--------|
| 1 | `sp_receta_crear` | `recetas` | INSERT |
| 2 | `sp_receta_agregar_medicamento` | `receta_medicamentos` | INSERT |
| 3 | `sp_receta_quitar_medicamento` | `receta_medicamentos` | DELETE |
| 4 | `sp_receta_actualizar_medicamento` | `receta_medicamentos` | UPDATE |
| 5 | `sp_receta_activar_nfc` | `receta_nfc` | INSERT |
| 6 | `sp_receta_cerrar_nfc` | `receta_nfc` | UPDATE |
| 7 | `sp_receta_cambiar_nfc` | `receta_nfc` | UPDATE + INSERT |
| 8 | `sp_nfc_registrar_lectura` | `lecturas_nfc` | INSERT |
| 9 | `sp_receta_cerrar` | `receta_nfc` | UPDATE (todos) |
| 10 | `sp_nfc_asignar` | `asignacion_nfc` | UPDATE + INSERT |
