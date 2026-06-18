Este proyecto modela el sistema de **ventas de productos fitosanitarios, bioestimulantes y biocontrol** de una empresa agrotech en el mercado español.  

El sector agrotech es uno de los más relevantes para la economía española (tercer productor agrícola de la UE), y la gestión de productos fitosanitarios supone retos analíticos reales: estacionalidad marcada, segmentación de clientes (cooperativas, distribuidores, agricultores), diversidad de cultivos y creciente regulación de productos convencionales vs. ecológicos.

---

## 1. Modelo de datos

### Arquitectura estrella (Star Schema)

```
dim_calendario ──┐
dim_producto   ──┤
                 ├──► fact_ventas
dim_cliente    ──┤
  └── dim_provincia
dim_cultivo    ──┘
```

### Tablas y granularidad

| Tabla | Tipo | Granularidad | Filas |
|---|---|---|---|
| `fact_ventas` | Hecho | 1 línea de pedido | ~260 |
| `dim_producto` | Dimensión | 1 referencia comercial | 25 |
| `dim_cliente` | Dimensión | 1 cuenta comercial | 40 |
| `dim_cultivo` | Dimensión | 1 tipo de cultivo | 15 |
| `dim_provincia` | Dimensión | 1 provincia española | 20 |
| `dim_calendario` | Dimensión | 1 día (2023–2024) | 731 |


## 2. Datos

Los datos son **sintéticos pero realistas**, generados con Python siguiendo patrones del mercado español:
- **Estacionalidad:** fungicidas e insecticidas predominan en primavera/verano; herbicidas y fertilizantes en otoño/invierno.
- **Segmentación de clientes:** cooperativas generan pedidos grandes (50–500 u), agricultores individuales compras pequeñas (1–50 u).
- **Provincias:** Andalucía, Levante, Extremadura y Castilla-La Mancha como zonas agrícolas principales.
- **Problemas de calidad introducidos intencionalmente** para el EDA:
  - 15 filas con `descuento_pct = NULL`
  - 3 filas con `cantidad` negativa (error de signo)
  - 1 pedido duplicado (`numero_pedido` repetido)

---

## 3. Estructura de ficheros

```
├── 01_schema.sql   — DDL: CREATE TABLE, índices, vistas (ejecutar primero)
├── 02_data.sql     — DML: INSERT, UPDATE, DELETE con transacciones
├── 03_eda.sql      — CORE: calidad de datos + EDA + insights de negocio
├── README.md       — Este fichero
└── diagrama_ER.png — Diagrama del modelo realizado
```
---
## 4. Instrucciones de ejecución (DBeaver + SQLite)

1. Abrir DBeaver → Nueva conexión → SQLite → Crear nueva base de datos (ej. `agroventas.db`)
2. Abrir y ejecutar `01_schema.sql` 
3. Ejecutar `02_data.sql`
4. Ejecutar `03_eda.sql` bloque a bloque

