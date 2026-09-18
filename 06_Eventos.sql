-- 06_Eventos.sql
-- Automatización de rutinas de mantenimiento, agregación periódica y depuración

USE ecommerce_db;

-- Habilitar el motor de programación de eventos del servidor MySQL
SET GLOBAL event_scheduler = ON;

-- ----------------------------------------------------
-- Tabla de reportes periódicos requerida por el módulo
-- ----------------------------------------------------

CREATE TABLE IF NOT EXISTS reporte_ventas_semanales (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    semana_inicio DATE NOT NULL,
    semana_fin DATE NOT NULL,
    total_ventas DECIMAL(12,2) NOT NULL,
    cantidad_ventas INT NOT NULL,
    productos_vendidos INT NOT NULL,
    fecha_generacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

DELIMITER //

-- 1. Consolida la facturación y volumen de despacho semanal cada domingo a las 23:30
DROP EVENT IF EXISTS evt_generate_weekly_sales_report //
CREATE EVENT evt_generate_weekly_sales_report
ON SCHEDULE EVERY 1 WEEK
STARTS '2024-01-07 23:30:00'
DO
BEGIN
    DECLARE v_inicio DATE;
    DECLARE v_fin DATE;
    DECLARE v_total DECIMAL(12,2);
    DECLARE v_pedidos INT;
    DECLARE v_articulos INT;
    
    SET v_inicio = DATE_SUB(CURDATE(), INTERVAL 6 DAY);
    SET v_fin = CURDATE();
    
    SELECT 
        COALESCE(SUM(v.total), 0.00),
        COUNT(DISTINCT v.id_venta),
        COALESCE(SUM(dv.cantidad), 0)
    INTO v_total, v_pedidos, v_articulos
    FROM ventas v
    INNER JOIN detalle_ventas dv ON v.id_venta = dv.id_venta
    WHERE DATE(v.fecha_venta) BETWEEN v_inicio AND v_fin
      AND v.estado != 'Cancelado';
    
    INSERT INTO reporte_ventas_semanales (semana_inicio, semana_fin, total_ventas, cantidad_ventas, productos_vendidos)
    VALUES (v_inicio, v_fin, v_total, v_pedidos, v_articulos);
END //

-- 2. Limpieza de tablas temporales y alertas resueltas con más de 90 días
DROP EVENT IF EXISTS evt_cleanup_temp_tables_daily //
CREATE EVENT evt_cleanup_temp_tables_daily
ON SCHEDULE EVERY 1 DAY
STARTS '2024-01-01 02:00:00'
DO
BEGIN
    DELETE FROM alertas 
    WHERE resuelta = TRUE 
      AND fecha_alerta < DATE_SUB(NOW(), INTERVAL 90 DAY);
END //

-- 3. Depura registros de auditoría operativa con antigüedad superior a 6 meses
DROP EVENT IF EXISTS evt_archive_old_logs_monthly //
CREATE EVENT evt_archive_old_logs_monthly
ON SCHEDULE EVERY 1 MONTH
STARTS '2024-02-01 03:00:00'
DO
BEGIN
    DELETE FROM log_cambios_precio WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH);
    DELETE FROM log_estados_pedido WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH);
    DELETE FROM log_permisos WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH);
END //

-- 4. Inactiva códigos de descuento cuya vigencia ha expirado
DROP EVENT IF EXISTS evt_deactivate_expired_promotions_hourly //
CREATE EVENT evt_deactivate_expired_promotions_hourly
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    UPDATE promociones
    SET activa = FALSE
    WHERE activa = TRUE 
      AND fecha_fin < CURDATE();
END //

-- 5. Sincroniza acumulados de compra y lealtad de clientes cada medianoche
DROP EVENT IF EXISTS evt_recalculate_customer_loyalty_tiers_nightly //
CREATE EVENT evt_recalculate_customer_loyalty_tiers_nightly
ON SCHEDULE EVERY 1 DAY
STARTS '2024-01-01 01:00:00'
DO
BEGIN
    UPDATE clientes c
    SET c.total_gastado = (
        SELECT COALESCE(SUM(v.total), 0.00)
        FROM ventas v
        WHERE v.id_cliente = c.id_cliente 
          AND v.estado != 'Cancelado'
    ),
    c.fecha_ultima_compra = (
        SELECT MAX(v.fecha_venta)
        FROM ventas v
        WHERE v.id_cliente = c.id_cliente 
          AND v.estado != 'Cancelado'
    );
END //

-- 6. Emite alertas matutinas de compras para productos bajo el stock mínimo
DROP EVENT IF EXISTS evt_generate_reorder_list_daily //
CREATE EVENT evt_generate_reorder_list_daily
ON SCHEDULE EVERY 1 DAY
STARTS '2024-01-01 07:00:00'
DO
BEGIN
    INSERT INTO alertas (id_producto, tipo_alerta, mensaje, stock_actual)
    SELECT 
        p.id_producto,
        'REABASTECIMIENTO',
        CONCAT('Reorden requerida para: ', p.nombre, '. Stock actual: ', p.stock, ', mínimo: ', p.stock_minimo),
        p.stock
    FROM productos p
    WHERE p.stock <= p.stock_minimo 
      AND p.activo = TRUE
      AND NOT EXISTS (
          SELECT 1 FROM alertas a
          WHERE a.id_producto = p.id_producto
            AND a.tipo_alerta = 'REABASTECIMIENTO'
            AND a.resuelta = FALSE
      );
END //

-- 7. Actualiza estadísticas de índices del optimizador en tablas transaccionales
DROP EVENT IF EXISTS evt_rebuild_indexes_weekly //
CREATE EVENT evt_rebuild_indexes_weekly
ON SCHEDULE EVERY 1 WEEK
STARTS '2024-01-07 04:00:00'
DO
BEGIN
    ANALYZE TABLE productos;
    ANALYZE TABLE ventas;
    ANALYZE TABLE detalle_ventas;
    ANALYZE TABLE clientes;
END //

-- 8. Suspende cuentas que no hayan registrado actividad de compra en más de 12 meses
DROP EVENT IF EXISTS evt_suspend_inactive_accounts_quarterly //
CREATE EVENT evt_suspend_inactive_accounts_quarterly
ON SCHEDULE EVERY 3 MONTH
STARTS '2024-04-01 05:00:00'
DO
BEGIN
    UPDATE clientes
    SET activo = FALSE
    WHERE activo = TRUE
      AND (
          (fecha_ultima_compra IS NOT NULL AND fecha_ultima_compra < DATE_SUB(NOW(), INTERVAL 1 YEAR))
          OR (fecha_ultima_compra IS NULL AND fecha_registro < DATE_SUB(NOW(), INTERVAL 1 YEAR))
      );
END //

-- 9. Agrega métricas diarias de cierre en tabla histórica al finalizar cada jornada
DROP EVENT IF EXISTS evt_aggregate_daily_sales_data //
CREATE EVENT evt_aggregate_daily_sales_data
ON SCHEDULE EVERY 1 DAY
STARTS '2024-01-01 23:55:00'
DO
BEGIN
    INSERT INTO resumen_ventas_diario (fecha, total_ventas, cantidad_ventas, clientes_unicos)
    SELECT 
        CURDATE(),
        COALESCE(SUM(total), 0.00),
        COUNT(DISTINCT id_venta),
        COUNT(DISTINCT id_cliente)
    FROM ventas
    WHERE DATE(fecha_venta) = CURDATE()
      AND estado != 'Cancelado'
    ON DUPLICATE KEY UPDATE
        total_ventas = VALUES(total_ventas),
        cantidad_ventas = VALUES(cantidad_ventas),
        clientes_unicos = VALUES(clientes_unicos);
END //

-- 10. Auditoría de integridad nocturna: detecta órdenes huérfanas sin partidas de detalle
DROP EVENT IF EXISTS evt_check_data_consistency_nightly //
CREATE EVENT evt_check_data_consistency_nightly
ON SCHEDULE EVERY 1 DAY
STARTS '2024-01-01 02:30:00'
DO
BEGIN
    INSERT INTO alertas (tipo_alerta, mensaje)
    SELECT 
        'INCONSISTENCIA',
        CONCAT('Venta ID ', v.id_venta, ' no contiene líneas de detalle registradas.')
    FROM ventas v
    LEFT JOIN detalle_ventas dv ON v.id_venta = dv.id_venta
    WHERE dv.id_detalle IS NULL 
      AND v.estado != 'Cancelado'
      AND v.fecha_venta < DATE_SUB(NOW(), INTERVAL 2 HOUR);
END //

-- 11. Identifica cumpleañeros de la fecha para campañas de fidelización
DROP EVENT IF EXISTS evt_send_birthday_greetings_daily //
CREATE EVENT evt_send_birthday_greetings_daily
ON SCHEDULE EVERY 1 DAY
STARTS '2024-01-01 08:30:00'
DO
BEGIN
    INSERT INTO alertas (tipo_alerta, mensaje)
    SELECT 
        'CUMPLEAÑOS',
        CONCAT('Generar cupón de aniversario para cliente: ', c.nombre, ' ', c.apellido, ' (', c.email, ')')
    FROM clientes c
    WHERE MONTH(c.fecha_nacimiento) = MONTH(CURDATE())
      AND DAY(c.fecha_nacimiento) = DAY(CURDATE())
      AND c.activo = TRUE;
END //

-- 12. Regenera el ranking de productos líderes por ventas acumuladas
DROP EVENT IF EXISTS evt_update_product_rankings_hourly //
CREATE EVENT evt_update_product_rankings_hourly
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    DELETE FROM productos_ranking;
    
    INSERT INTO productos_ranking (id_producto, posicion, ventas_totales)
    SELECT 
        p.id_producto,
        ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0.00) DESC) AS posicion,
        COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0.00) AS ventas_totales
    FROM productos p
    LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
    LEFT JOIN ventas v ON dv.id_venta = v.id_venta AND v.estado != 'Cancelado'
    GROUP BY p.id_producto
    ORDER BY ventas_totales DESC
    LIMIT 20;
END //

-- 13. Métrica de volumetría de almacenamiento para monitoreo de crecimiento
DROP EVENT IF EXISTS evt_backup_critical_tables_daily //
CREATE EVENT evt_backup_critical_tables_daily
ON SCHEDULE EVERY 1 DAY
STARTS '2024-01-01 03:15:00'
DO
BEGIN
    INSERT INTO log_tamanio_bd (tamanio_mb, tablas_principales)
    SELECT 
        ROUND(SUM(data_length + index_length) / 1024 / 1024, 2),
        'ventas, detalle_ventas, productos, clientes'
    FROM information_schema.tables
    WHERE table_schema = 'ecommerce_db';
END //

-- 14. Purga sesiones de compra abandonadas con antigüedad mayor a 72 horas
DROP EVENT IF EXISTS evt_clear_abandoned_carts_daily //
CREATE EVENT evt_clear_abandoned_carts_daily
ON SCHEDULE EVERY 1 DAY
STARTS '2024-01-01 04:30:00'
DO
BEGIN
    DELETE FROM carritos_abandonados
    WHERE fecha_abandono < DATE_SUB(NOW(), INTERVAL 72 HOUR);
END //

-- 15. Calcula indicadores clave de rendimiento (KPI) del mes previo
DROP EVENT IF EXISTS evt_calculate_monthly_kpis //
CREATE EVENT evt_calculate_monthly_kpis
ON SCHEDULE EVERY 1 MONTH
STARTS '2024-02-01 00:05:00'
DO
BEGIN
    DECLARE v_mes INT;
    DECLARE v_anio INT;
    DECLARE v_total DECIMAL(12,2);
    DECLARE v_nuevos INT;
    DECLARE v_articulos INT;
    DECLARE v_ticket DECIMAL(10,2);
    
    SET v_mes = MONTH(DATE_SUB(CURDATE(), INTERVAL 1 DAY));
    SET v_anio = YEAR(DATE_SUB(CURDATE(), INTERVAL 1 DAY));
    
    SELECT 
        COALESCE(SUM(v.total), 0.00),
        COALESCE(SUM(dv.cantidad), 0),
        COALESCE(AVG(v.total), 0.00)
    INTO v_total, v_articulos, v_ticket
    FROM ventas v
    INNER JOIN detalle_ventas dv ON v.id_venta = dv.id_venta
    WHERE MONTH(v.fecha_venta) = v_mes 
      AND YEAR(v.fecha_venta) = v_anio
      AND v.estado != 'Cancelado';
    
    SELECT COUNT(*) INTO v_nuevos
    FROM clientes
    WHERE MONTH(fecha_registro) = v_mes 
      AND YEAR(fecha_registro) = v_anio;
    
    INSERT INTO kpis_mensuales (mes, anio, total_ventas, nuevos_clientes, productos_vendidos, ticket_promedio)
    VALUES (v_mes, v_anio, v_total, v_nuevos, v_articulos, v_ticket)
    ON DUPLICATE KEY UPDATE
        total_ventas = VALUES(total_ventas),
        nuevos_clientes = VALUES(nuevos_clientes),
        productos_vendidos = VALUES(productos_vendidos),
        ticket_promedio = VALUES(ticket_promedio);
END //

-- 16. Refresco programado de tablas agregadas de alto consumo analítico
DROP EVENT IF EXISTS evt_refresh_materialized_views_nightly //
CREATE EVENT evt_refresh_materialized_views_nightly
ON SCHEDULE EVERY 1 DAY
STARTS '2024-01-01 01:45:00'
DO
BEGIN
    DELETE FROM productos_ranking;
    
    INSERT INTO productos_ranking (id_producto, posicion, ventas_totales)
    SELECT 
        p.id_producto,
        ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0.00) DESC),
        COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0.00)
    FROM productos p
    LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
    LEFT JOIN ventas v ON dv.id_venta = v.id_venta AND v.estado != 'Cancelado'
    GROUP BY p.id_producto;
END //

-- 17. Registro semanal del tamaño global de base de datos
DROP EVENT IF EXISTS evt_log_database_size_weekly //
CREATE EVENT evt_log_database_size_weekly
ON SCHEDULE EVERY 1 WEEK
STARTS '2024-01-07 06:00:00'
DO
BEGIN
    INSERT INTO log_tamanio_bd (tamanio_mb, tablas_principales)
    SELECT 
        ROUND(SUM(data_length + index_length) / 1024 / 1024, 2),
        GROUP_CONCAT(table_name SEPARATOR ', ')
    FROM information_schema.tables
    WHERE table_schema = 'ecommerce_db';
END //

-- 18. Detección horaria de patrones irregulares: clientes con 3 o más pedidos cancelados en la última hora
DROP EVENT IF EXISTS evt_detect_fraudulent_activity_hourly //
CREATE EVENT evt_detect_fraudulent_activity_hourly
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    INSERT INTO alertas (tipo_alerta, mensaje)
    SELECT 
        'FRAUDE_SOSPECHA',
        CONCAT('Cliente ID ', id_cliente, ' superó el umbral con ', COUNT(*), ' cancelaciones en la última hora.')
    FROM ventas
    WHERE estado = 'Cancelado'
      AND fecha_venta >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
    GROUP BY id_cliente
    HAVING COUNT(*) >= 3;
END //

-- 19. Evaluación mensual del volumen de colocación por proveedor
DROP EVENT IF EXISTS evt_generate_supplier_performance_report_monthly //
CREATE EVENT evt_generate_supplier_performance_report_monthly
ON SCHEDULE EVERY 1 MONTH
STARTS '2024-02-01 07:00:00'
DO
BEGIN
    DECLARE v_periodo VARCHAR(20);
    SET v_periodo = DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL 1 MONTH), '%Y-%m');
    
    DELETE FROM proveedor_rendimiento WHERE periodo = v_periodo;
    
    INSERT INTO proveedor_rendimiento (id_proveedor, ventas_totales, productos_activos, periodo)
    SELECT 
        pr.id_proveedor,
        COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0.00),
        COUNT(DISTINCT p.id_producto),
        v_periodo
    FROM proveedores pr
    LEFT JOIN productos p ON pr.id_proveedor = p.id_proveedor
    LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
    LEFT JOIN ventas v ON dv.id_venta = v.id_venta 
      AND DATE_FORMAT(v.fecha_venta, '%Y-%m') = v_periodo
      AND v.estado != 'Cancelado'
    GROUP BY pr.id_proveedor;
END //

-- 20. Purgado definitivo de ventas archivadas que superan 1 año de permanencia
DROP EVENT IF EXISTS evt_purge_soft_deleted_records_weekly //
CREATE EVENT evt_purge_soft_deleted_records_weekly
ON SCHEDULE EVERY 1 WEEK
STARTS '2024-01-07 05:00:00'
DO
BEGIN
    DELETE FROM ventas_archivadas
    WHERE fecha_archivo < DATE_SUB(NOW(), INTERVAL 1 YEAR);
END //

DELIMITER ;

-- ============================================================================
-- NOTAS DE APRENDIZAJE
-- ============================================================================
-- Lo más difícil de este archivo:
-- - Calcular fechas exactas para ejecuciones recurrentes (STARTS, EVERY)
-- - Entender ON DUPLICATE KEY UPDATE en eventos
-- - Simular vistas materializadas con tablas físicas
--
-- Lo más interesante:
-- - Ver cómo los eventos automatizan tareas que antes hacía manualmente
-- - evt_refresh_materialized_views_nightly: simulación de vistas materializadas
-- - evt_detect_fraudulent_activity_hourly: detección automática de patrones sospechosos
--
-- Errores que cometí:
-- - Me faltaba SET GLOBAL event_scheduler = ON al principio
-- - En algunos eventos usaba STARTS CONCAT(...) que es inválido
-- - No entendía bien la diferencia entre diario, semanal, mensual, trimestral
--
-- Nota: El event_scheduler debe estar activado para que los eventos funcionen.
-- Si no se activa, los eventos se crean pero nunca se ejecutan. MySQL no tiene
-- vistas materializadas nativas como PostgreSQL, por eso las simulé con tablas
-- físicas que se actualizan periódicamente.
