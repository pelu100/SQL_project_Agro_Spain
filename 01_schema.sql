DROP TABLE IF EXISTS fact_ventas;
DROP TABLE IF EXISTS dim_cliente;
DROP TABLE IF EXISTS dim_producto;
DROP TABLE IF EXISTS dim_cultivo;
DROP TABLE IF EXISTS dim_provincia;
DROP TABLE IF EXISTS dim_calendario;

-- ============================================================
-- DIMENSIÓN: dim_provincia
-- Granularidad: 1 fila = 1 provincia española
-- PK surrogate: independiente de cambios administrativos
-- codigo_ine: clave natural oficial (INE), UNIQUE + NOT NULL
-- ============================================================
CREATE TABLE IF NOT EXISTS dim_provincia (
    id_provincia       INTEGER PRIMARY KEY AUTOINCREMENT,
    codigo_ine         TEXT    NOT NULL UNIQUE,
    nombre             TEXT    NOT NULL,
    comunidad_autonoma TEXT    NOT NULL
);

-- ============================================================
-- DIMENSIÓN: dim_cultivo
-- Granularidad: 1 fila = 1 tipo de cultivo
-- CHECK en ciclo: solo 'Anual' o 'Perenne' son valores válidos
-- ============================================================
CREATE TABLE IF NOT EXISTS dim_cultivo (
    id_cultivo  INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre      TEXT    NOT NULL UNIQUE,
    familia     TEXT    NOT NULL,
    ciclo       TEXT    NOT NULL CHECK(ciclo IN ('Anual','Perenne'))
);

-- ============================================================
-- DIMENSIÓN: dim_producto
-- Granularidad: 1 fila = 1 referencia comercial
-- activo: soft-delete (1=activo, 0=descatalogado)
-- precio_pvp > 0: constraint para evitar precios inválidos
-- ============================================================
CREATE TABLE IF NOT EXISTS dim_producto (
    id_producto     INTEGER PRIMARY KEY AUTOINCREMENT,
    codigo_producto TEXT    NOT NULL UNIQUE,
    nombre          TEXT    NOT NULL,
    categoria       TEXT    NOT NULL
                    CHECK(categoria IN ('Fungicida','Herbicida','Insecticida',
                                        'Biocontrol','Bioestimulante','Fertilizante')),
    tipo            TEXT    NOT NULL DEFAULT 'Convencional'
                    CHECK(tipo IN ('Convencional','Ecológico')),
    unidad_medida   TEXT    NOT NULL DEFAULT 'L'
                    CHECK(unidad_medida IN ('L','Kg','Un')),
    precio_pvp      REAL    NOT NULL CHECK(precio_pvp > 0),
    activo          INTEGER NOT NULL DEFAULT 1 CHECK(activo IN (0,1))
);

-- ============================================================
-- DIMENSIÓN: dim_cliente
-- Granularidad: 1 fila = 1 cuenta comercial
-- FK a dim_provincia para localización geográfica
-- fecha_alta: DEFAULT (DATE('now')) para inserciones sin fecha
-- ============================================================
CREATE TABLE IF NOT EXISTS dim_cliente (
    id_cliente     INTEGER PRIMARY KEY AUTOINCREMENT,
    codigo_cliente TEXT    NOT NULL UNIQUE,
    nombre         TEXT    NOT NULL,
    tipo_cliente   TEXT    NOT NULL
                   CHECK(tipo_cliente IN ('Cooperativa','Distribuidor','Agricultor')),
    id_provincia   INTEGER NOT NULL
                   REFERENCES dim_provincia(id_provincia),
    segmento       TEXT    NOT NULL DEFAULT 'Medium'
                   CHECK(segmento IN ('Small','Medium','Large')),
    fecha_alta     TEXT    NOT NULL DEFAULT (DATE('now'))
);

-- ============================================================
-- DIMENSIÓN: dim_calendario
-- Granularidad: 1 fila = 1 día (2023-01-01 a 2024-12-31)
-- PK natural: la propia fecha en formato ISO 8601 (TEXT)
-- ============================================================
CREATE TABLE IF NOT EXISTS dim_calendario (
    id_fecha      TEXT    PRIMARY KEY,
    anio          INTEGER NOT NULL,
    mes           INTEGER NOT NULL CHECK(mes BETWEEN 1 AND 12),
    trimestre     INTEGER NOT NULL CHECK(trimestre BETWEEN 1 AND 4),
    semana        INTEGER NOT NULL CHECK(semana BETWEEN 0 AND 53),
    nombre_mes    TEXT    NOT NULL,
    nombre_dia    TEXT    NOT NULL,
    es_fin_semana INTEGER NOT NULL DEFAULT 0 CHECK(es_fin_semana IN (0,1)),
    temporada     TEXT    NOT NULL
                  CHECK(temporada IN ('Primavera','Verano','Otoño','Invierno'))
);

-- ============================================================
-- TABLA DE HECHOS: fact_ventas
-- Granularidad: 1 fila = 1 línea de pedido
-- FK a todas las dimensiones; cantidad sin CHECK para poder
-- insertar errores intencionados y detectarlos en el EDA
-- ============================================================
CREATE TABLE IF NOT EXISTS fact_ventas (
    id_venta        INTEGER PRIMARY KEY AUTOINCREMENT,
    id_fecha        TEXT    NOT NULL REFERENCES dim_calendario(id_fecha),
    id_producto     INTEGER NOT NULL REFERENCES dim_producto(id_producto),
    id_cliente      INTEGER NOT NULL REFERENCES dim_cliente(id_cliente),
    id_cultivo      INTEGER NOT NULL REFERENCES dim_cultivo(id_cultivo),
    numero_pedido   TEXT    NOT NULL,
    cantidad        REAL    NOT NULL,
    precio_unitario REAL    NOT NULL CHECK(precio_unitario > 0),
    importe_neto    REAL    NOT NULL CHECK(importe_neto >= 0),
    canal_venta     TEXT    NOT NULL DEFAULT 'Directo'
                    CHECK(canal_venta IN ('Directo','Online','Distribuidor'))
);

-- ============================================================
-- ÍNDICES
-- ============================================================

-- Índice compuesto en fact_ventas (id_fecha, id_producto):
CREATE INDEX IF NOT EXISTS idx_ventas_fecha_prod
    ON fact_ventas(id_fecha, id_producto);

-- Índice en dim_cliente por provincia: 
CREATE INDEX IF NOT EXISTS idx_cliente_provincia
    ON dim_cliente(id_provincia);

-- ============================================================
-- VISTAS DE NEGOCIO
-- ============================================================

-- Vista 1: Detalle completo de ventas con todas las dimensiones
-- Evita repetir los mismos JOINs en cada query del EDA
CREATE VIEW IF NOT EXISTS vw_ventas_detalle AS
SELECT
    fv.id_venta,
    fv.numero_pedido,
    fv.id_fecha,
    dc.anio,
    dc.mes,
    dc.trimestre,
    dc.nombre_mes,
    dc.temporada,
    dp.codigo_producto,
    dp.nombre AS nombre_producto,
    dp.categoria,
    dp.tipo AS tipo_producto,
    dp.unidad_medida,
    cli.codigo_cliente,
    cli.nombre AS nombre_cliente,
    cli.tipo_cliente,
    cli.segmento,
    pr.nombre  AS provincia_cliente,
    pr.comunidad_autonoma,
    cu.nombre AS cultivo,
    cu.familia AS familia_cultivo,
    cu.ciclo,
    fv.cantidad,
    fv.precio_unitario,
    fv.importe_neto,
    fv.canal_venta
FROM fact_ventas     fv
INNER JOIN dim_calendario dc ON fv.id_fecha = dc.id_fecha
INNER JOIN dim_producto dp ON fv.id_producto = dp.id_producto
INNER JOIN dim_cliente cli ON fv.id_cliente  = cli.id_cliente
INNER JOIN dim_provincia pr ON cli.id_provincia = pr.id_provincia
INNER JOIN dim_cultivo cu ON fv.id_cultivo = cu.id_cultivo;

-- Vista 2: KPIs mensuales por categoría de producto
CREATE VIEW IF NOT EXISTS vw_kpi_mensual_categoria AS
SELECT
    dc.anio,
    dc.mes,
    dc.nombre_mes,
    dc.trimestre,
    dp.categoria,
    dp.tipo AS tipo_producto,
    COUNT(fv.id_venta) AS num_pedidos,
    ROUND(SUM(fv.cantidad), 2) AS volumen_total,
    ROUND(SUM(fv.importe_neto), 2) AS importe_total,
    ROUND(AVG(fv.importe_neto), 2) AS ticket_medio
FROM fact_ventas     fv
INNER JOIN dim_calendario dc ON fv.id_fecha = dc.id_fecha
INNER JOIN dim_producto dp ON fv.id_producto = dp.id_producto
WHERE fv.cantidad > 0
GROUP BY dc.anio, dc.mes, dc.nombre_mes, dc.trimestre, dp.categoria, dp.tipo;


