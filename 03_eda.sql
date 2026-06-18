-- BLOQUE A · CALIDAD DE DATOS

-- ────────────────────────────────────────────────────────────
-- A1. Detección y eliminación de pedidos duplicados
-- Método 1: GROUP BY + HAVING para localizar qué pedidos
--           están repetidos y cuántas veces aparecen.
-- Método 2: RANK() OVER (PARTITION BY) para ver exactamente
--           qué filas son el duplicado con todos sus datos.
-- ────────────────────────────────────────────────────────────

-- Método 1: ¿qué números de pedido aparecen más de una vez?
SELECT
    numero_pedido,
    COUNT(*) AS veces_pedido
FROM fact_ventas
GROUP BY numero_pedido
HAVING COUNT(*) > 1;

-- Método 2: inspeccionamos las filas duplicadas con sus datos
SELECT *
FROM (
    SELECT
        id_venta,
        numero_pedido,
        id_fecha,
        id_cliente,
        id_producto,
        importe_neto,
        RANK() OVER (PARTITION BY numero_pedido ORDER BY id_venta) AS rk
    FROM fact_ventas
)
WHERE rk > 1;

-- Corrección: eliminamos la fila duplicada conservando el original
BEGIN;
DELETE FROM fact_ventas
 WHERE id_venta IN (
    SELECT id_venta
    FROM (
        SELECT
            id_venta,
            ROW_NUMBER() OVER (
                PARTITION BY numero_pedido
                ORDER BY id_venta
            ) AS rn
        FROM fact_ventas
    )
    WHERE rn > 1
);
COMMIT;

-- Verificamos que ya no hay duplicados
SELECT numero_pedido, COUNT(*) AS veces_pedido
  FROM fact_ventas
 GROUP BY numero_pedido
HAVING COUNT(*) > 1;


-- ────────────────────────────────────────────────────────────
-- A2. Detección y corrección de cantidades negativas
-- Una cantidad negativa es imposible en una venta: es un
-- error al registrar los datos (signo invertido).
-- ────────────────────────────────────────────────────────────

-- Detectamos los registros con cantidad inválida
SELECT
    id_venta,
    numero_pedido,
    cantidad,
    importe_neto,
    id_fecha
FROM fact_ventas
WHERE cantidad < 0;

-- Corrección: invertimos el signo y recalculamos el importe
BEGIN;
UPDATE fact_ventas
   SET cantidad = -1 * cantidad,
       importe_neto = ROUND(-1 * cantidad * precio_unitario, 2)
 WHERE cantidad < 0;
COMMIT;

-- Verificamos que no quedan negativos
SELECT COUNT(*) AS negativos_restantes
  FROM fact_ventas
 WHERE cantidad < 0;


-- ────────────────────────────────────────────────────────────
-- A3. Detección de fechas fuera de rango
-- ────────────────────────────────────────────────────────────

-- Fechas huérfanas: sin entrada en dim_calendario
SELECT
    fv.id_venta,
    fv.id_fecha,
    dc.id_fecha AS fecha_en_calendario
FROM fact_ventas fv
LEFT JOIN dim_calendario dc ON fv.id_fecha = dc.id_fecha
WHERE dc.id_fecha IS NULL;

-- Fechas fuera del periodo 2023-2024
SELECT
    CAST(id_venta AS TEXT) AS id_venta_texto,
    id_fecha
FROM fact_ventas
WHERE id_fecha < '2023-01-01' OR id_fecha > '2024-12-31';



-- BLOQUE B · EDA DESCRIPTIVO


-- ────────────────────────────────────────────────────────────
-- B1. Conteo general del modelo
-- ────────────────────────────────────────────────────────────
SELECT 'fact_ventas'   AS tabla, COUNT(*) AS filas FROM fact_ventas   UNION ALL
SELECT 'dim_producto', COUNT(*) FROM dim_producto  UNION ALL
SELECT 'dim_cliente', COUNT(*)  FROM dim_cliente   UNION ALL
SELECT 'dim_cultivo', COUNT(*) FROM dim_cultivo   UNION ALL
SELECT 'dim_provincia', COUNT(*) FROM dim_provincia UNION ALL
SELECT 'dim_calendario', COUNT(*) FROM dim_calendario;


-- ────────────────────────────────────────────────────────────
-- B2. Ventas por categoría de producto
-- ¿Qué categorías generan más volumen e importe?
-- ────────────────────────────────────────────────────────────
SELECT
    dp.categoria,
    dp.tipo  AS tipo_producto,
    COUNT(fv.id_venta) AS num_ventas,
    ROUND(SUM(fv.cantidad), 1) AS volumen_total,
    ROUND(SUM(fv.importe_neto), 2) AS importe_total,
    ROUND(AVG(fv.importe_neto), 2) AS ticket_medio,
    ROUND(SUM(fv.importe_neto) * 100.0 /
          (SELECT SUM(importe_neto) FROM fact_ventas), 2) AS pct_sobre_total
FROM fact_ventas fv
INNER JOIN dim_producto dp ON fv.id_producto = dp.id_producto
GROUP BY dp.categoria, dp.tipo
ORDER BY importe_total DESC;


-- ────────────────────────────────────────────────────────────
-- B3. Ventas por tipo de cliente y segmento
-- ¿Las cooperativas o los distribuidores facturan más?
-- ────────────────────────────────────────────────────────────
SELECT
    cli.tipo_cliente,
    cli.segmento,
    COUNT(DISTINCT cli.id_cliente) AS n_clientes_activos,
    COUNT(fv.id_venta)             AS n_ventas,
    ROUND(SUM(fv.importe_neto), 2) AS importe_total,
    ROUND(AVG(fv.importe_neto), 2) AS ticket_medio
FROM fact_ventas fv
INNER JOIN dim_cliente cli ON fv.id_cliente = cli.id_cliente
GROUP BY cli.tipo_cliente, cli.segmento
ORDER BY cli.tipo_cliente, importe_total DESC;


-- ────────────────────────────────────────────────────────────
-- B4. Estacionalidad: ventas por temporada y año
-- ¿En qué época del año se concentra la demanda?
-- ────────────────────────────────────────────────────────────
SELECT
    dc.anio,
    dc.temporada,
    COUNT(fv.id_venta) AS num_ventas,
    ROUND(SUM(fv.importe_neto), 2) AS importe_total,
    ROUND(AVG(fv.importe_neto), 2) AS ticket_medio
FROM fact_ventas fv
INNER JOIN dim_calendario dc ON fv.id_fecha = dc.id_fecha
GROUP BY dc.anio, dc.temporada
ORDER BY dc.anio,
    CASE dc.temporada
        WHEN 'Invierno'  THEN 1
        WHEN 'Primavera' THEN 2
        WHEN 'Verano'    THEN 3
        WHEN 'Otoño'     THEN 4
    END;


-- BLOQUE C · INSIGHTS DE NEGOCIO

-- ────────────────────────────────────────────────────────────
-- C1. Ranking de provincias por facturación
-- ¿Qué territorios son prioritarios para la fuerza comercial?
-- CTE 1: agrupa ventas por provincia.
-- CTE 2: añade ranking nacional y por CCAA con RANK().
-- ────────────────────────────────────────────────────────────
WITH ventas_provincia AS (
    SELECT
        pr.nombre AS provincia_cliente,
        pr.comunidad_autonoma,
        COUNT(fv.id_venta) AS n_ventas,
        COUNT(DISTINCT cli.codigo_cliente) AS n_clientes_activos,
        ROUND(SUM(fv.importe_neto), 2) AS facturacion
    FROM fact_ventas fv
    INNER JOIN dim_cliente cli ON fv.id_cliente = cli.id_cliente
    INNER JOIN dim_provincia pr ON cli.id_provincia = pr.id_provincia
    GROUP BY pr.nombre, pr.comunidad_autonoma
),
ranking_provincia AS (
    SELECT
        provincia_cliente,
        comunidad_autonoma,
        n_ventas,
        n_clientes_activos,
        facturacion,
        RANK() OVER (
            PARTITION BY comunidad_autonoma
            ORDER BY facturacion DESC
        ) AS rank_en_ccaa,
        RANK() OVER (
            ORDER BY facturacion DESC
        ) AS rank_nacional
    FROM ventas_provincia
)
SELECT *
  FROM ranking_provincia
 ORDER BY rank_nacional;

-- ────────────────────────────────────────────────────────────
-- C2. Evolución mensual acumulada (YTD)
-- ¿Cuánto llevamos facturado en lo que va de año?
-- ────────────────────────────────────────────────────────────
WITH mensual AS (
    SELECT
        dc.anio,
        dc.mes,
        dc.nombre_mes,
        ROUND(SUM(fv.importe_neto), 2) AS facturacion_mes
    FROM fact_ventas fv
    INNER JOIN dim_calendario dc ON fv.id_fecha = dc.id_fecha
    GROUP BY dc.anio, dc.mes, dc.nombre_mes
)
SELECT
    anio,
    mes,
    nombre_mes,
    facturacion_mes,
    ROUND(
        SUM(facturacion_mes) OVER (PARTITION BY anio ORDER BY mes), 2
    ) AS facturacion_ytd,
    ROUND(
        facturacion_mes * 100.0 / SUM(facturacion_mes) OVER (PARTITION BY anio), 2
    ) AS pct_del_anio
FROM mensual
ORDER BY anio, mes;


-- ────────────────────────────────────────────────────────────
-- C3. Top 3 productos por categoría
-- ¿Cuál es el producto estrella dentro de cada línea?
-- ────────────────────────────────────────────────────────────
WITH prod_ranking AS (
    SELECT
        dp.categoria,
        dp.nombre AS producto,
        dp.tipo,
        ROUND(SUM(fv.importe_neto), 2) AS importe_total,
        COUNT(fv.id_venta) AS n_ventas,
        RANK() OVER (
            PARTITION BY dp.categoria
            ORDER BY SUM(fv.importe_neto) DESC
        ) AS rank_cat
    FROM fact_ventas fv
    INNER JOIN dim_producto dp ON fv.id_producto = dp.id_producto
    GROUP BY dp.categoria, dp.nombre, dp.tipo
)
SELECT *
  FROM prod_ranking
 WHERE rank_cat <= 3
 ORDER BY categoria, rank_cat;


-- ────────────────────────────────────────────────────────────
-- C4. Comparativa de facturación 2023 vs 2024
-- ¿Cuánto ha crecido cada categoría respecto al año anterior?
-- ────────────────────────────────────────────────────────────
WITH anual AS (
    SELECT
        dp.categoria,
        dp.tipo AS tipo_producto,
        dc.anio,
        ROUND(SUM(fv.importe_neto), 2) AS facturacion
    FROM fact_ventas fv
    INNER JOIN dim_producto dp ON fv.id_producto = dp.id_producto
    INNER JOIN dim_calendario dc ON fv.id_fecha = dc.id_fecha
    GROUP BY dp.categoria, dp.tipo, dc.anio
)
SELECT
    categoria,
    tipo_producto,
    MAX(CASE WHEN anio = 2023 THEN facturacion END) AS facturacion_2023,
    MAX(CASE WHEN anio = 2024 THEN facturacion END) AS facturacion_2024,
    ROUND(
        (MAX(CASE WHEN anio = 2024 THEN facturacion END) -
         MAX(CASE WHEN anio = 2023 THEN facturacion END)) * 100.0 /
        NULLIF(MAX(CASE WHEN anio = 2023 THEN facturacion END), 0), 2
    ) AS variacion_pct
FROM anual
GROUP BY categoria, tipo_producto
ORDER BY variacion_pct DESC;


-- ────────────────────────────────────────────────────────────
-- C5. Clientes sin ninguna compra registrada
-- ¿Hay cuentas dadas de alta que nunca han comprado?
-- ────────────────────────────────────────────────────────────
SELECT
    cli.codigo_cliente,
    cli.nombre,
    cli.tipo_cliente,
    cli.segmento,
    pr.nombre   AS provincia,
    cli.fecha_alta,
    DATE('now') AS fecha_consulta,
    CASE
        WHEN cli.fecha_alta < DATE('now', '-2 year') THEN 'Antiguo (>2 años sin comprar)'
        WHEN cli.fecha_alta < DATE('now', '-1 year') THEN 'Reciente (1-2 años)'
        ELSE 'Nuevo (<1 año de alta)'
    END AS antiguedad
FROM dim_cliente cli
INNER JOIN dim_provincia pr ON cli.id_provincia = pr.id_provincia
LEFT JOIN  fact_ventas   fv ON cli.id_cliente = fv.id_cliente
WHERE fv.id_venta IS NULL
ORDER BY cli.fecha_alta ASC;


-- ────────────────────────────────────────────────────────────
-- C6. Transacción: ajuste de precio con ROLLBACK
-- Simulamos una promoción del -10 % en herbicidas.
-- ────────────────────────────────────────────────────────────
BEGIN;

UPDATE dim_producto
   SET precio_pvp = ROUND(precio_pvp * 0.90, 2)
 WHERE categoria = 'Herbicida'
   AND activo = 1;

SELECT codigo_producto, nombre, precio_pvp
  FROM dim_producto
 WHERE categoria = 'Herbicida';

ROLLBACK;


