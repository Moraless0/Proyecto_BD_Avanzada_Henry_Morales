-- 02_Consultas_Avanzadas.sql
-- Consultas analíticas y reportes de inteligencia de negocio

USE ecommerce_db;

SELECT * FROM ventas;

-- 1. Top 10 Productos Más Vendidos por facturación total
SELECT 
    p.id_producto,
    p.nombre,
    p.sku,
    c.nombre AS categoria,
    SUM(dv.cantidad) AS unidades_vendidas,
    SUM(dv.cantidad * dv.precio_unitario_congelado) AS facturacion_total
FROM productos p
INNER JOIN categorias c ON p.id_categoria = c.id_categoria
INNER JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
INNER JOIN ventas v ON dv.id_venta = v.id_venta
WHERE v.estado != 'Cancelado'
GROUP BY p.id_producto, p.nombre, p.sku, c.nombre
ORDER BY facturacion_total DESC
LIMIT 10;

-- 2. Productos con Bajas Ventas (percentil inferior del 10% para evaluación de descontinuación)
WITH ventas_producto AS (
    SELECT 
        p.id_producto,
        p.nombre,
        p.sku,
        COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0.00) AS total_ingresos,
        PERCENT_RANK() OVER (ORDER BY COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0.00) ASC) AS percentil_ventas
    FROM productos p
    LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
    LEFT JOIN ventas v ON dv.id_venta = v.id_venta AND v.estado != 'Cancelado'
    GROUP BY p.id_producto, p.nombre, p.sku
)
SELECT 
    id_producto,
    nombre,
    sku,
    total_ingresos,
    ROUND(percentil_ventas * 100, 2) AS percentil_acumulado
FROM ventas_producto
WHERE percentil_ventas <= 0.10
ORDER BY total_ingresos ASC;

-- 3. Clientes VIP (top 5 según LifeTime Value - LTV histórico)
SELECT 
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    c.email,
    COUNT(DISTINCT v.id_venta) AS pedidos_totales,
    COALESCE(SUM(v.total), 0.00) AS ltv_historico,
    MAX(v.fecha_venta) AS ultima_compra
FROM clientes c
INNER JOIN ventas v ON c.id_cliente = v.id_cliente
WHERE v.estado != 'Cancelado'
GROUP BY c.id_cliente, c.nombre, c.apellido, c.email
ORDER BY ltv_historico DESC
LIMIT 5;

-- 4. Análisis de Ventas Mensuales (facturación, volumen y ticket promedio)
SELECT 
    YEAR(v.fecha_venta) AS anio,
    MONTH(v.fecha_venta) AS mes,
    DATE_FORMAT(v.fecha_venta, '%M %Y') AS periodo,
    COUNT(DISTINCT v.id_venta) AS total_ordenes,
    COUNT(DISTINCT v.id_cliente) AS compradores_unicos,
    SUM(v.total) AS facturacion_total,
    ROUND(AVG(v.total), 2) AS ticket_promedio
FROM ventas v
WHERE v.estado != 'Cancelado'
GROUP BY YEAR(v.fecha_venta), MONTH(v.fecha_venta), DATE_FORMAT(v.fecha_venta, '%M %Y')
ORDER BY anio DESC, mes DESC;

-- 5. Crecimiento de Clientes (altas registradas por trimestre)
SELECT 
    YEAR(fecha_registro) AS anio,
    QUARTER(fecha_registro) AS trimestre,
    CONCAT('Q', QUARTER(fecha_registro), '-', YEAR(fecha_registro)) AS periodo,
    COUNT(*) AS nuevos_registros
FROM clientes
GROUP BY YEAR(fecha_registro), QUARTER(fecha_registro)
ORDER BY anio DESC, trimestre DESC;

-- 6. Tasa de Compra Repetida (porcentaje de clientes con más de una transacción)
WITH pedidos_por_cliente AS (
    SELECT 
        c.id_cliente,
        COUNT(DISTINCT v.id_venta) AS total_compras
    FROM clientes c
    LEFT JOIN ventas v ON c.id_cliente = v.id_cliente AND v.estado != 'Cancelado'
    GROUP BY c.id_cliente
)
SELECT 
    COUNT(*) AS base_total_clientes,
    COUNT(CASE WHEN total_compras > 1 THEN 1 END) AS clientes_recurrentes,
    ROUND((COUNT(CASE WHEN total_compras > 1 THEN 1 END) * 100.0 / COUNT(*)), 2) AS tasa_recompra_pct
FROM pedidos_por_cliente;

-- 7. Productos Comprados Juntos Frecuentemente (afinidad en cesta de compra)
SELECT 
    p1.nombre AS producto_a,
    p2.nombre AS producto_b,
    COUNT(*) AS frecuencia_conjunta
FROM detalle_ventas dv1
INNER JOIN detalle_ventas dv2 ON dv1.id_venta = dv2.id_venta AND dv1.id_producto < dv2.id_producto
INNER JOIN productos p1 ON dv1.id_producto = p1.id_producto
INNER JOIN productos p2 ON dv2.id_producto = p2.id_producto
INNER JOIN ventas v ON dv1.id_venta = v.id_venta
WHERE v.estado != 'Cancelado'
GROUP BY p1.id_producto, p1.nombre, p2.id_producto, p2.nombre
HAVING COUNT(*) >= 1
ORDER BY frecuencia_conjunta DESC, producto_a ASC
LIMIT 10;

-- 8. Rotación de Inventario por categoría (unidades despachadas sobre inventario existente)
SELECT 
    c.id_categoria,
    c.nombre AS categoria,
    COALESCE(SUM(dv.cantidad), 0) AS unidades_despachadas,
    COALESCE(SUM(p.stock), 0) AS stock_disponible,
    CASE 
        WHEN SUM(p.stock) > 0 THEN ROUND(SUM(dv.cantidad) / SUM(p.stock), 2)
        ELSE 0.00
    END AS indice_rotacion
FROM categorias c
LEFT JOIN productos p ON c.id_categoria = p.id_categoria
LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
LEFT JOIN ventas v ON dv.id_venta = v.id_venta AND v.estado != 'Cancelado'
GROUP BY c.id_categoria, c.nombre
ORDER BY indice_rotacion DESC;

-- 9. Productos que Necesitan Reabastecimiento (existencias por debajo del umbral mínimo de seguridad)
SELECT 
    p.id_producto,
    p.nombre,
    p.sku,
    c.nombre AS categoria,
    pr.nombre AS proveedor,
    p.stock AS stock_actual,
    p.stock_minimo,
    (p.stock_minimo - p.stock) AS unidades_a_reordenar
FROM productos p
INNER JOIN categorias c ON p.id_categoria = c.id_categoria
INNER JOIN proveedores pr ON p.id_proveedor = pr.id_proveedor
WHERE p.stock <= p.stock_minimo AND p.activo = TRUE
ORDER BY (p.stock_minimo - p.stock) DESC;

-- 10. Análisis de Carrito Abandonado (cuantificación de intención de compra no concretada)
SELECT 
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    c.email,
    p.nombre AS producto_abandonado,
    ca.cantidad,
    ROUND(ca.cantidad * p.precio, 2) AS valor_potencial,
    ca.fecha_abandono
FROM carritos_abandonados ca
INNER JOIN clientes c ON ca.id_cliente = c.id_cliente
INNER JOIN productos p ON ca.id_producto = p.id_producto
ORDER BY ca.fecha_abandono DESC;

-- 11. Rendimiento de Proveedores (facturación y volumen de unidades colocadas)
SELECT 
    pr.id_proveedor,
    pr.nombre AS proveedor,
    COUNT(DISTINCT p.id_producto) AS catalogo_activo,
    COALESCE(SUM(dv.cantidad), 0) AS unidades_comercializadas,
    COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0.00) AS facturacion_generada
FROM proveedores pr
LEFT JOIN productos p ON pr.id_proveedor = p.id_proveedor
LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
LEFT JOIN ventas v ON dv.id_venta = v.id_venta AND v.estado != 'Cancelado'
GROUP BY pr.id_proveedor, pr.nombre
ORDER BY facturacion_generada DESC;

-- 12. Análisis Geográfico de Ventas (distribución por plaza comercial de sucursal)
SELECT 
    s.ciudad,
    s.nombre AS sucursal,
    COUNT(DISTINCT v.id_venta) AS total_ordenes,
    COUNT(DISTINCT v.id_cliente) AS compradores_unicos,
    SUM(v.total) AS ingresos_totales,
    ROUND(AVG(v.total), 2) AS ticket_promedio
FROM ventas v
INNER JOIN sucursales s ON v.id_sucursal = s.id_sucursal
WHERE v.estado != 'Cancelado'
GROUP BY s.id_sucursal, s.ciudad, s.nombre
ORDER BY ingresos_totales DESC;

-- 13. Ventas por Hora del Día (detección de ventanas horarias pico para pautas y personal)
SELECT 
    HOUR(fecha_venta) AS franja_horaria,
    COUNT(*) AS total_transacciones,
    SUM(total) AS monto_total,
    ROUND(AVG(total), 2) AS ticket_promedio
FROM ventas
WHERE estado != 'Cancelado'
GROUP BY HOUR(fecha_venta)
ORDER BY franja_horaria ASC;

-- 14. Impacto de Promociones (comparativa ventana móvil 30 días antes, durante y 30 días después)
SELECT 
    p.codigo AS promocion,
    p.descuento_porcentaje,
    p.fecha_inicio,
    p.fecha_fin,
    COALESCE(SUM(CASE 
        WHEN v.fecha_venta < p.fecha_inicio 
        AND v.fecha_venta >= DATE_SUB(p.fecha_inicio, INTERVAL 30 DAY) THEN v.total 
    END), 0.00) AS facturacion_previa_30d,
    COALESCE(SUM(CASE 
        WHEN v.fecha_venta BETWEEN p.fecha_inicio AND p.fecha_fin THEN v.total 
    END), 0.00) AS facturacion_en_campaña,
    COALESCE(SUM(CASE 
        WHEN v.fecha_venta > p.fecha_fin 
        AND v.fecha_venta <= DATE_ADD(p.fecha_fin, INTERVAL 30 DAY) THEN v.total 
    END), 0.00) AS facturacion_posterior_30d
FROM promociones p
LEFT JOIN ventas v ON v.estado != 'Cancelado'
GROUP BY p.id_promocion, p.codigo, p.descuento_porcentaje, p.fecha_inicio, p.fecha_fin
ORDER BY p.fecha_inicio DESC;

-- 15. Análisis de Cohort (retención de clientes mes a mes a partir del primer pedido)
WITH primer_pedido AS (
    SELECT 
        id_cliente,
        DATE_FORMAT(MIN(fecha_venta), '%Y-%m-01') AS fecha_cohorte
    FROM ventas
    WHERE estado != 'Cancelado'
    GROUP BY id_cliente
),
actividad_mensual AS (
    SELECT 
        v.id_cliente,
        pp.fecha_cohorte,
        PERIOD_DIFF(EXTRACT(YEAR_MONTH FROM v.fecha_venta), EXTRACT(YEAR_MONTH FROM pp.fecha_cohorte)) AS meses_transcurridos
    FROM ventas v
    INNER JOIN primer_pedido pp ON v.id_cliente = pp.id_cliente
    WHERE v.estado != 'Cancelado'
)
SELECT 
    DATE_FORMAT(fecha_cohorte, '%Y-%m') AS cohorte,
    meses_transcurridos AS mes_relativo,
    COUNT(DISTINCT id_cliente) AS clientes_activos
FROM actividad_mensual
GROUP BY fecha_cohorte, meses_transcurridos
ORDER BY fecha_cohorte ASC, meses_transcurridos ASC;

-- 16. Margen de Beneficio por Producto (cálculo de rentabilidad bruta unitaria y porcentual)
SELECT 
    p.id_producto,
    p.nombre,
    p.sku,
    c.nombre AS categoria,
    p.costo,
    p.precio,
    (p.precio - p.costo) AS margen_bruto_unitario,
    ROUND(((p.precio - p.costo) / p.precio) * 100, 2) AS margen_porcentual
FROM productos p
INNER JOIN categorias c ON p.id_categoria = c.id_categoria
WHERE p.activo = TRUE
ORDER BY margen_porcentual DESC;

-- 17. Tiempo Promedio Entre Compras (intervalo de recompra de clientes recurrentes)
WITH ordenes_secuenciales AS (
    SELECT 
        id_cliente,
        fecha_venta,
        LAG(fecha_venta) OVER (PARTITION BY id_cliente ORDER BY fecha_venta ASC) AS fecha_compra_previa
    FROM ventas
    WHERE estado != 'Cancelado'
)
SELECT 
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    COUNT(*) AS recompras_computadas,
    ROUND(AVG(DATEDIFF(os.fecha_venta, os.fecha_compra_previa)), 1) AS dias_promedio_recompra
FROM ordenes_secuenciales os
INNER JOIN clientes c ON os.id_cliente = c.id_cliente
WHERE os.fecha_compra_previa IS NOT NULL
GROUP BY c.id_cliente, c.nombre, c.apellido
ORDER BY dias_promedio_recompra ASC;

-- 18. Productos Más Vistos vs. Comprados (tasa de conversión efectiva sobre visualizaciones)
SELECT 
    p.id_producto,
    p.nombre,
    p.vistas AS total_visitas,
    COALESCE(SUM(dv.cantidad), 0) AS unidades_vendidas,
    ROUND(
        CASE 
            WHEN p.vistas > 0 THEN (COALESCE(SUM(dv.cantidad), 0) * 100.0 / p.vistas)
            ELSE 0.00
        END, 2
    ) AS conversion_rate_pct
FROM productos p
LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
LEFT JOIN ventas v ON dv.id_venta = v.id_venta AND v.estado != 'Cancelado'
GROUP BY p.id_producto, p.nombre, p.vistas
ORDER BY p.vistas DESC;

-- 19. Segmentación de Clientes RFM (Recencia, Frecuencia y Monetario mediante NTILE)
WITH rfm_base AS (
    SELECT 
        c.id_cliente,
        CONCAT(c.nombre, ' ', c.apellido) AS cliente,
        DATEDIFF('2024-03-31', MAX(v.fecha_venta)) AS recencia_dias,
        COUNT(DISTINCT v.id_venta) AS frecuencia,
        COALESCE(SUM(v.total), 0.00) AS monetario
    FROM clientes c
    LEFT JOIN ventas v ON c.id_cliente = v.id_cliente AND v.estado != 'Cancelado'
    GROUP BY c.id_cliente, c.nombre, c.apellido
),
rfm_scores AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY recencia_dias ASC) AS r_score,
        NTILE(4) OVER (ORDER BY frecuencia DESC) AS f_score,
        NTILE(4) OVER (ORDER BY monetario DESC) AS m_score
    FROM rfm_base
)
SELECT 
    id_cliente,
    cliente,
    recencia_dias,
    frecuencia,
    monetario,
    CONCAT(r_score, f_score, m_score) AS rfm_score,
    CASE 
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Campeón / VIP'
        WHEN r_score >= 3 AND f_score >= 2 THEN 'Leal Potencial'
        WHEN r_score <= 2 AND f_score >= 2 THEN 'Cliente en Riesgo'
        WHEN r_score <= 1 AND f_score <= 1 THEN 'Inactivo / Perdido'
        ELSE 'Regular'
    END AS segmento_cliente
FROM rfm_scores
ORDER BY monetario DESC;

-- 20. Predicción de Demanda Simple (proyección para el próximo mes por promedio móvil)
WITH historico_demanda AS (
    SELECT 
        c.nombre AS categoria,
        DATE_FORMAT(v.fecha_venta, '%Y-%m') AS periodo,
        SUM(dv.cantidad) AS unidades_vendidas
    FROM detalle_ventas dv
    INNER JOIN productos p ON dv.id_producto = p.id_producto
    INNER JOIN categorias c ON p.id_categoria = c.id_categoria
    INNER JOIN ventas v ON dv.id_venta = v.id_venta
    WHERE v.estado != 'Cancelado'
    GROUP BY c.nombre, DATE_FORMAT(v.fecha_venta, '%Y-%m')
)
SELECT 
    categoria,
    ROUND(AVG(unidades_vendidas), 0) AS proyeccion_base_unidades,
    ROUND(AVG(unidades_vendidas) * 1.10, 0) AS proyeccion_crecimiento_10pct
FROM historico_demanda
GROUP BY categoria
ORDER BY proyeccion_base_unidades DESC;

-- ============================================================================
-- NOTAS DE APRENDIZAJE
-- ============================================================================
-- Lo más difícil de este archivo:
-- - NTILE y PERCENT_RANK: entender cómo dividen los datos en cuartiles fue complicado
-- - Análisis de cohort: la lógica de calcular retención mes a mes me costó
-- - Self-join: entender cómo una tabla se une consigo misma para productos comprados juntos
-- 
-- Lo más interesante:
-- - Ver cómo las CTEs hacen el código mucho más legible
-- - El análisis RFM: entender que agrupa clientes por comportamiento
-- - Las funciones de ventana: WINDOW FUNCTIONS son muy potentes
--
-- Errores que cometí:
-- - Al principio olvidaba filtrar ventas canceladas en algunas consultas
-- - Usaba PERCENTILE que no funciona en todas las versiones de MySQL, tuve que cambiar a PERCENT_RANK
-- - En el self-join, no ponía la condición dv1.id_detalle < dv2.id_detalle y duplicaba resultados
