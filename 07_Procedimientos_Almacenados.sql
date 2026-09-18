-- 07_Procedimientos_Almacenados.sql
-- Rutinas transaccionales complejas con control de excepciones y consistencia ACID

USE ecommerce_db;

DELIMITER //

-- 1. Procesa una venta completa con múltiples artículos vía JSON de forma atómica
DROP PROCEDURE IF EXISTS sp_RealizarNuevaVenta //
CREATE PROCEDURE sp_RealizarNuevaVenta(
    IN p_id_cliente INT,
    IN p_id_sucursal INT,
    IN p_items_json JSON,
    OUT p_id_venta INT,
    OUT p_mensaje VARCHAR(255)
)
proc_label: BEGIN
    DECLARE v_i INT DEFAULT 0;
    DECLARE v_total_items INT DEFAULT 0;
    DECLARE v_id_prod INT;
    DECLARE v_cant INT;
    DECLARE v_precio DECIMAL(10,2);
    DECLARE v_stock INT;
    DECLARE v_monto_acumulado DECIMAL(12,2) DEFAULT 0.00;
    DECLARE v_cliente_existe INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_id_venta = NULL;
        SET p_mensaje = 'Error transaccional: Excepción SQL durante el procesamiento de la venta.';
    END;

    -- Validar existencia del cliente
    SELECT COUNT(*) INTO v_cliente_existe FROM clientes WHERE id_cliente = p_id_cliente AND activo = TRUE;
    IF v_cliente_existe = 0 THEN
        SET p_id_venta = NULL;
        SET p_mensaje = 'Error de validación: El cliente especificado no existe o está inactivo.';
        LEAVE proc_label;
    END IF;

    SET v_total_items = JSON_LENGTH(p_items_json);
    IF v_total_items IS NULL OR v_total_items = 0 THEN
        SET p_id_venta = NULL;
        SET p_mensaje = 'Error de validación: La orden debe contener al menos un artículo.';
        LEAVE proc_label;
    END IF;

    START TRANSACTION;

    INSERT INTO ventas (fecha_venta, estado, total, id_cliente, id_sucursal)
    VALUES (NOW(), 'Pendiente de Pago', 0.00, p_id_cliente, p_id_sucursal);
    
    SET p_id_venta = LAST_INSERT_ID();

    WHILE v_i < v_total_items DO
        SET v_id_prod = JSON_UNQUOTE(JSON_EXTRACT(p_items_json, CONCAT('$[', v_i, '].id_producto')));
        SET v_cant = JSON_UNQUOTE(JSON_EXTRACT(p_items_json, CONCAT('$[', v_i, '].cantidad')));

        SELECT stock, precio INTO v_stock, v_precio
        FROM productos
        WHERE id_producto = v_id_prod
        FOR UPDATE;

        IF v_stock IS NULL THEN
            ROLLBACK;
            SET p_id_venta = NULL;
            SET p_mensaje = CONCAT('Error de inventario: El producto ID ', v_id_prod, ' no existe.');
            LEAVE proc_label;
        END IF;

        IF v_stock < v_cant THEN
            ROLLBACK;
            SET p_id_venta = NULL;
            SET p_mensaje = CONCAT('Error de inventario: Stock insuficiente para producto ID ', v_id_prod);
            LEAVE proc_label;
        END IF;

        -- El trigger trg_update_stock_after_insert_venta (05_Triggers.sql) descuenta
        -- el stock automaticamente al insertar la linea, por eso aqui NO se resta stock
        -- manualmente (antes se restaba dos veces).
        INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
        VALUES (p_id_venta, v_id_prod, v_cant, v_precio);

        SET v_monto_acumulado = v_monto_acumulado + (v_cant * v_precio);
        SET v_i = v_i + 1;
    END WHILE;

    UPDATE ventas 
    SET total = v_monto_acumulado 
    WHERE id_venta = p_id_venta;

    -- El trigger trg_update_total_gastado_cliente (05_Triggers.sql) solo se dispara con
    -- INSERT ON ventas, y en ese momento el total todavia era 0.00. Por eso aqui se
    -- actualiza el acumulado del cliente con el monto real ya calculado.
    UPDATE clientes
    SET total_gastado = total_gastado + v_monto_acumulado,
        fecha_ultima_compra = NOW()
    WHERE id_cliente = p_id_cliente;

    COMMIT;
    SET p_mensaje = 'Venta registrada exitosamente con reserva de inventario.';
END //

-- 2. Alta de producto con SKU generado automáticamente y validación de márgenes
DROP PROCEDURE IF EXISTS sp_AgregarNuevoProducto //
CREATE PROCEDURE sp_AgregarNuevoProducto(
    IN p_nombre VARCHAR(200),
    IN p_descripcion TEXT,
    IN p_precio DECIMAL(10,2),
    IN p_costo DECIMAL(10,2),
    IN p_stock INT,
    IN p_stock_minimo INT,
    IN p_peso DECIMAL(8,2),
    IN p_id_categoria INT,
    IN p_id_proveedor INT,
    OUT p_id_producto INT,
    OUT p_sku_generado VARCHAR(50)
)
BEGIN
    DECLARE v_sku VARCHAR(50);
    
    SET v_sku = fn_GenerarSKU(p_nombre, p_id_categoria);
    
    INSERT INTO productos (
        nombre, descripcion, precio, costo, stock, stock_minimo, 
        sku, peso, id_categoria, id_proveedor
    )
    VALUES (
        p_nombre, p_descripcion, p_precio, p_costo, p_stock, 
        COALESCE(p_stock_minimo, 10), COALESCE(p_peso, 0.00), 
        v_sku, p_id_categoria, p_id_proveedor
    );
    
    SET p_id_producto = LAST_INSERT_ID();
    SET p_sku_generado = v_sku;
END //

-- 3. Actualización de datos domiciliarios del cliente
DROP PROCEDURE IF EXISTS sp_ActualizarDireccionCliente //
CREATE PROCEDURE sp_ActualizarDireccionCliente(
    IN p_id_cliente INT,
    IN p_nueva_direccion TEXT,
    IN p_ciudad VARCHAR(100),
    OUT p_filas_afectadas INT
)
BEGIN
    UPDATE clientes
    SET direccion_envio = p_nueva_direccion,
        ciudad = COALESCE(p_ciudad, ciudad)
    WHERE id_cliente = p_id_cliente;
    
    SET p_filas_afectadas = ROW_COUNT();
END //

-- 4. Procesamiento transaccional de devoluciones de producto con reintegro de stock
DROP PROCEDURE IF EXISTS sp_ProcesarDevolucion //
CREATE PROCEDURE sp_ProcesarDevolucion(
    IN p_id_detalle INT,
    IN p_cantidad_devuelta INT,
    IN p_motivo VARCHAR(255),
    OUT p_id_devolucion INT,
    OUT p_mensaje VARCHAR(255)
)
proc_label: BEGIN
    DECLARE v_id_venta INT;
    DECLARE v_id_producto INT;
    DECLARE v_cant_comprada INT;
    DECLARE v_precio_congelado DECIMAL(10,2);
    DECLARE v_monto_reembolso DECIMAL(10,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_id_devolucion = NULL;
        SET p_mensaje = 'Error transaccional al procesar la devolución.';
    END;

    SELECT id_venta, id_producto, cantidad, precio_unitario_congelado
    INTO v_id_venta, v_id_producto, v_cant_comprada, v_precio_congelado
    FROM detalle_ventas
    WHERE id_detalle = p_id_detalle;

    IF v_id_venta IS NULL THEN
        SET p_id_devolucion = NULL;
        SET p_mensaje = 'Error: La partida de venta especificada no existe.';
        LEAVE proc_label;
    END IF;

    IF p_cantidad_devuelta <= 0 OR p_cantidad_devuelta > v_cant_comprada THEN
        SET p_id_devolucion = NULL;
        SET p_mensaje = 'Error: La cantidad a devolver excede lo facturado o es menor a 1.';
        LEAVE proc_label;
    END IF;

    SET v_monto_reembolso = p_cantidad_devuelta * v_precio_congelado;

    START TRANSACTION;

    INSERT INTO devoluciones (id_venta, id_producto, cantidad, motivo, monto_reembolsado)
    VALUES (v_id_venta, v_id_producto, p_cantidad_devuelta, p_motivo, v_monto_reembolso);

    SET p_id_devolucion = LAST_INSERT_ID();

    UPDATE productos
    SET stock = stock + p_cantidad_devuelta
    WHERE id_producto = v_id_producto;

    IF p_cantidad_devuelta = v_cant_comprada THEN
        -- Se borra la linea completa: no existe trigger AFTER DELETE en detalle_ventas
        -- que recalcule el total, asi que aqui SI hay que restarlo manualmente.
        DELETE FROM detalle_ventas WHERE id_detalle = p_id_detalle;

        UPDATE ventas
        SET total = total - v_monto_reembolso
        WHERE id_venta = v_id_venta;
    ELSE
        -- Devolucion parcial: el trigger trg_recalculate_total_venta_on_detalle_change
        -- (05_Triggers.sql) ya recalcula ventas.total al hacer este UPDATE, por eso
        -- NO se resta el reembolso de nuevo aqui (antes se restaba dos veces).
        UPDATE detalle_ventas
        SET cantidad = cantidad - p_cantidad_devuelta
        WHERE id_detalle = p_id_detalle;
    END IF;

    COMMIT;
    SET p_mensaje = CONCAT('Devolución procesada exitosamente. Reembolso: Q', v_monto_reembolso);
END //

-- 5. Consulta consolidada de historial de órdenes de un cliente
DROP PROCEDURE IF EXISTS sp_ObtenerHistorialComprasCliente //
CREATE PROCEDURE sp_ObtenerHistorialComprasCliente(
    IN p_id_cliente INT
)
BEGIN
    SELECT 
        v.id_venta,
        v.fecha_venta,
        v.estado,
        v.total,
        s.nombre AS sucursal,
        COUNT(dv.id_detalle) AS lineas_compradas,
        COALESCE(SUM(dv.cantidad), 0) AS unidades_totales
    FROM ventas v
    LEFT JOIN sucursales s ON v.id_sucursal = s.id_sucursal
    LEFT JOIN detalle_ventas dv ON v.id_venta = dv.id_venta
    WHERE v.id_cliente = p_id_cliente
    GROUP BY v.id_venta, v.fecha_venta, v.estado, v.total, s.nombre
    ORDER BY v.fecha_venta DESC;
END //

-- 6. Ajuste manual de existencias con registro mandatorio de auditoría
DROP PROCEDURE IF EXISTS sp_AjustarNivelStock //
CREATE PROCEDURE sp_AjustarNivelStock(
    IN p_id_producto INT,
    IN p_nuevo_stock INT,
    IN p_motivo VARCHAR(255),
    OUT p_mensaje VARCHAR(255)
)
BEGIN
    DECLARE v_stock_anterior INT;

    IF p_nuevo_stock < 0 THEN
        SET p_mensaje = 'Error: El nivel de stock no puede fijarse en un valor negativo.';
    ELSE
        SELECT stock INTO v_stock_anterior 
        FROM productos 
        WHERE id_producto = p_id_producto;

        UPDATE productos
        SET stock = p_nuevo_stock
        WHERE id_producto = p_id_producto;

        INSERT INTO alertas (id_producto, tipo_alerta, mensaje, stock_actual)
        VALUES (
            p_id_producto,
            'AJUSTE_INVENTARIO',
            CONCAT('Ajuste manual: ', p_motivo, '. Delta: ', (p_nuevo_stock - v_stock_anterior)),
            p_nuevo_stock
        );

        SET p_mensaje = CONCAT('Stock actualizado de ', v_stock_anterior, ' a ', p_nuevo_stock);
    END IF;
END //

-- 7. Anonimización de datos personales por derecho al olvido respetando integridad referencial
DROP PROCEDURE IF EXISTS sp_EliminarClienteDeFormaSegura //
CREATE PROCEDURE sp_EliminarClienteDeFormaSegura(
    IN p_id_cliente INT,
    OUT p_mensaje VARCHAR(255)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_mensaje = 'Error: No fue posible anonimizar el registro del cliente.';
    END;

    START TRANSACTION;

    UPDATE clientes
    SET nombre = 'Cliente',
        apellido = 'Anonimizado',
        email = CONCAT('anon_', p_id_cliente, '@deleted.local'),
        contraseña = '$2y$10$deletedaccountxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
        direccion_envio = 'DIRECCION_PURGADA',
        ciudad = 'CONFIDENCIAL',
        activo = FALSE
    WHERE id_cliente = p_id_cliente;

    COMMIT;
    SET p_mensaje = 'Cliente anonimizado y cuenta desactivada correctamente.';
END //

-- 8. Aplicación de descuento lineal por categoría de catálogo
DROP PROCEDURE IF EXISTS sp_AplicarDescuentoPorCategoria //
CREATE PROCEDURE sp_AplicarDescuentoPorCategoria(
    IN p_id_categoria INT,
    IN p_porcentaje DECIMAL(5,2),
    OUT p_articulos_afectados INT
)
BEGIN
    IF p_porcentaje <= 0 OR p_porcentaje > 90 THEN
        SET p_articulos_afectados = 0;
    ELSE
        UPDATE productos
        SET precio = ROUND(precio * (1 - (p_porcentaje / 100)), 2)
        WHERE id_categoria = p_id_categoria AND activo = TRUE;
        
        SET p_articulos_afectados = ROW_COUNT();
    END IF;
END //

-- 9. Emisión de informe contable mensual consolidado
DROP PROCEDURE IF EXISTS sp_GenerarReporteMensualVentas //
CREATE PROCEDURE sp_GenerarReporteMensualVentas(
    IN p_mes INT,
    IN p_anio INT
)
BEGIN
    SELECT 
        v.id_venta,
        v.fecha_venta,
        v.estado,
        v.total,
        CONCAT(c.nombre, ' ', c.apellido) AS cliente,
        s.nombre AS sucursal,
        SUM(dv.cantidad) AS total_piezas
    FROM ventas v
    INNER JOIN clientes c ON v.id_cliente = c.id_cliente
    LEFT JOIN sucursales s ON v.id_sucursal = s.id_sucursal
    LEFT JOIN detalle_ventas dv ON v.id_venta = dv.id_venta
    WHERE MONTH(v.fecha_venta) = p_mes 
      AND YEAR(v.fecha_venta) = p_anio
      AND v.estado != 'Cancelado'
    GROUP BY v.id_venta, v.fecha_venta, v.estado, v.total, c.nombre, c.apellido, s.nombre
    ORDER BY v.fecha_venta ASC;

    SELECT 
        COUNT(DISTINCT v.id_venta) AS total_pedidos,
        COALESCE(SUM(v.total), 0.00) AS ingresos_netos,
        ROUND(COALESCE(AVG(v.total), 0.00), 2) AS ticket_promedio,
        COUNT(DISTINCT v.id_cliente) AS compradores_distintos
    FROM ventas v
    WHERE MONTH(v.fecha_venta) = p_mes 
      AND YEAR(v.fecha_venta) = p_anio
      AND v.estado != 'Cancelado';
END //

-- 10. Transición formal de estado de pedido con log de auditoría
DROP PROCEDURE IF EXISTS sp_CambiarEstadoPedido //
CREATE PROCEDURE sp_CambiarEstadoPedido(
    IN p_id_venta INT,
    IN p_nuevo_estado VARCHAR(50),
    OUT p_mensaje VARCHAR(255)
)
BEGIN
    DECLARE v_estado_actual VARCHAR(50);

    SELECT estado INTO v_estado_actual 
    FROM ventas 
    WHERE id_venta = p_id_venta;

    IF v_estado_actual IS NULL THEN
        SET p_mensaje = 'Error: Pedido no localizado.';
    ELSE
        UPDATE ventas
        SET estado = p_nuevo_estado
        WHERE id_venta = p_id_venta;

        SET p_mensaje = CONCAT('Pedido actualizado de "', v_estado_actual, '" a "', p_nuevo_estado, '".');
    END IF;
END //

-- 11. Registro de nuevo cliente con validación previa de unicidad
DROP PROCEDURE IF EXISTS sp_RegistrarNuevoCliente //
CREATE PROCEDURE sp_RegistrarNuevoCliente(
    IN p_nombre VARCHAR(100),
    IN p_apellido VARCHAR(100),
    IN p_email VARCHAR(150),
    IN p_contrasena VARCHAR(255),
    IN p_direccion TEXT,
    IN p_ciudad VARCHAR(100),
    IN p_fecha_nacimiento DATE,
    IN p_id_sucursal INT,
    OUT p_id_cliente INT,
    OUT p_mensaje VARCHAR(255)
)
BEGIN
    DECLARE v_conteo INT DEFAULT 0;

    SELECT COUNT(*) INTO v_conteo FROM clientes WHERE email = p_email;

    IF v_conteo > 0 THEN
        SET p_id_cliente = NULL;
        SET p_mensaje = 'Error: El correo electrónico ya se encuentra registrado.';
    ELSE
        INSERT INTO clientes (
            nombre, apellido, email, contraseña, direccion_envio, 
            ciudad, fecha_nacimiento, id_sucursal
        )
        VALUES (
            p_nombre, p_apellido, p_email, p_contrasena, p_direccion, 
            p_ciudad, p_fecha_nacimiento, p_id_sucursal
        );

        SET p_id_cliente = LAST_INSERT_ID();
        SET p_mensaje = 'Cliente registrado satisfactoriamente.';
    END IF;
END //

-- 12. Ficha técnica integral de producto combinando categoría y proveedor
DROP PROCEDURE IF EXISTS sp_ObtenerDetallesProductoCompleto //
CREATE PROCEDURE sp_ObtenerDetallesProductoCompleto(
    IN p_id_producto INT
)
BEGIN
    SELECT 
        p.id_producto,
        p.nombre AS producto,
        p.sku,
        p.descripcion,
        p.precio,
        p.costo,
        (p.precio - p.costo) AS margen_bruto,
        ROUND(((p.precio - p.costo) / p.precio) * 100, 2) AS margen_pct,
        p.stock,
        p.stock_minimo,
        p.peso,
        p.activo,
        c.nombre AS categoria,
        pr.nombre AS proveedor,
        pr.email_contacto AS email_proveedor,
        pr.telefono_contacto AS telefono_proveedor
    FROM productos p
    LEFT JOIN categorias c ON p.id_categoria = c.id_categoria
    LEFT JOIN proveedores pr ON p.id_proveedor = pr.id_proveedor
    WHERE p.id_producto = p_id_producto;
END //

-- 13. Fusión transaccional de perfiles de clientes duplicados
DROP PROCEDURE IF EXISTS sp_FusionarCuentasCliente //
CREATE PROCEDURE sp_FusionarCuentasCliente(
    IN p_id_cliente_principal INT,
    IN p_id_cliente_duplicado INT,
    OUT p_mensaje VARCHAR(255)
)
proc_label: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_mensaje = 'Error transaccional al ejecutar la fusión de cuentas.';
    END;

    IF p_id_cliente_principal = p_id_cliente_duplicado THEN
        SET p_mensaje = 'Error: Las cuentas principal y duplicada deben ser distintas.';
        LEAVE proc_label;
    END IF;

    START TRANSACTION;

    -- Reasignar compras y carritos
    UPDATE ventas SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;
    UPDATE carritos_abandonados SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;
    UPDATE IGNORE reseñas SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;
    DELETE FROM reseñas WHERE id_cliente = p_id_cliente_duplicado;

    -- Recalcular LTV del cliente resultante
    UPDATE clientes
    SET total_gastado = (
        SELECT COALESCE(SUM(total), 0.00) 
        FROM ventas 
        WHERE id_cliente = p_id_cliente_principal AND estado != 'Cancelado'
    )
    WHERE id_cliente = p_id_cliente_principal;

    -- Purgar registro duplicado
    DELETE FROM clientes WHERE id_cliente = p_id_cliente_duplicado;

    COMMIT;
    SET p_mensaje = 'Cuentas fusionadas e histórico consolidado con éxito.';
END //

-- 14. Modificación controlada del proveedor de un producto
DROP PROCEDURE IF EXISTS sp_AsignarProductoAProveedor //
CREATE PROCEDURE sp_AsignarProductoAProveedor(
    IN p_id_producto INT,
    IN p_id_proveedor INT,
    OUT p_mensaje VARCHAR(255)
)
BEGIN
    DECLARE v_existe_prov INT DEFAULT 0;

    SELECT COUNT(*) INTO v_existe_prov FROM proveedores WHERE id_proveedor = p_id_proveedor;

    IF v_existe_prov = 0 THEN
        SET p_mensaje = 'Error: El proveedor especificado no existe.';
    ELSE
        UPDATE productos
        SET id_proveedor = p_id_proveedor
        WHERE id_producto = p_id_producto;

        SET p_mensaje = 'Proveedor asignado al producto exitosamente.';
    END IF;
END //

-- 15. Motor de búsqueda avanzada de artículos con filtros multicriterio
DROP PROCEDURE IF EXISTS sp_BuscarProductos //
CREATE PROCEDURE sp_BuscarProductos(
    IN p_termino VARCHAR(100),
    IN p_id_categoria INT,
    IN p_precio_min DECIMAL(10,2),
    IN p_precio_max DECIMAL(10,2),
    IN p_solo_disponibles BOOLEAN
)
BEGIN
    SELECT 
        p.id_producto,
        p.nombre,
        p.sku,
        p.precio,
        p.stock,
        c.nombre AS categoria,
        pr.nombre AS proveedor
    FROM productos p
    LEFT JOIN categorias c ON p.id_categoria = c.id_categoria
    LEFT JOIN proveedores pr ON p.id_proveedor = pr.id_proveedor
    WHERE (p_termino IS NULL OR p.nombre LIKE CONCAT('%', p_termino, '%') OR p.descripcion LIKE CONCAT('%', p_termino, '%'))
      AND (p_id_categoria IS NULL OR p.id_categoria = p_id_categoria)
      AND (p_precio_min IS NULL OR p.precio >= p_precio_min)
      AND (p_precio_max IS NULL OR p.precio <= p_precio_max)
      AND (p_solo_disponibles IS NULL OR p_solo_disponibles = FALSE OR p.stock > 0)
      AND p.activo = TRUE
    ORDER BY p.nombre ASC;
END //

-- 16. Tablero gerencial con métricas en tiempo real de operaciones
DROP PROCEDURE IF EXISTS sp_ObtenerDashboardAdmin //
CREATE PROCEDURE sp_ObtenerDashboardAdmin()
BEGIN
    SELECT 
        (SELECT COUNT(*) FROM ventas WHERE DATE(fecha_venta) = CURDATE() AND estado != 'Cancelado') AS pedidos_hoy,
        (SELECT COALESCE(SUM(total), 0.00) FROM ventas WHERE DATE(fecha_venta) = CURDATE() AND estado != 'Cancelado') AS facturacion_hoy,
        (SELECT COUNT(*) FROM ventas WHERE estado = 'Pendiente de Pago') AS ordenes_por_cobrar,
        (SELECT COUNT(*) FROM productos WHERE stock <= stock_minimo AND activo = TRUE) AS articulos_alerta_stock,
        (SELECT COUNT(*) FROM clientes WHERE DATE(fecha_registro) = CURDATE()) AS registros_hoy;
END //

-- 17. Simulación de liquidación y pasarela de cobro
DROP PROCEDURE IF EXISTS sp_ProcesarPago //
CREATE PROCEDURE sp_ProcesarPago(
    IN p_id_venta INT,
    IN p_metodo VARCHAR(50),
    IN p_referencia VARCHAR(100),
    OUT p_aprobado BOOLEAN,
    OUT p_mensaje VARCHAR(255)
)
proc_label: BEGIN
    DECLARE v_estado VARCHAR(50);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_aprobado = FALSE;
        SET p_mensaje = 'Error transaccional al liquidar el pago.';
    END;

    SELECT estado INTO v_estado FROM ventas WHERE id_venta = p_id_venta;

    IF v_estado IS NULL THEN
        SET p_aprobado = FALSE;
        SET p_mensaje = 'Error: Orden no localizada.';
        LEAVE proc_label;
    END IF;

    IF v_estado != 'Pendiente de Pago' THEN
        SET p_aprobado = FALSE;
        SET p_mensaje = CONCAT('Error: La orden ya no admite cobro. Estado actual: ', v_estado);
        LEAVE proc_label;
    END IF;

    START TRANSACTION;

    UPDATE ventas
    SET estado = 'Procesando'
    WHERE id_venta = p_id_venta;

    INSERT INTO alertas (tipo_alerta, mensaje)
    VALUES ('PAGO_RECIBIDO', CONCAT('Venta #', p_id_venta, ' liquidada con ', p_metodo, '. Ref: ', p_referencia));

    COMMIT;
    SET p_aprobado = TRUE;
    SET p_mensaje = 'Transacción de pago aprobada correctamente.';
END //

-- 18. Registro de opinión con validación estricta de compra verificada previa
DROP PROCEDURE IF EXISTS sp_AñadirReseñaProducto //
CREATE PROCEDURE sp_AñadirReseñaProducto(
    IN p_id_producto INT,
    IN p_id_cliente INT,
    IN p_calificacion INT,
    IN p_comentario TEXT,
    OUT p_mensaje VARCHAR(255)
)
proc_label: BEGIN
    DECLARE v_compras INT DEFAULT 0;

    IF p_calificacion < 1 OR p_calificacion > 5 THEN
        SET p_mensaje = 'Error: La puntuación debe estar comprendida entre 1 y 5 estrellas.';
        LEAVE proc_label;
    END IF;

    SELECT COUNT(*) INTO v_compras
    FROM detalle_ventas dv
    INNER JOIN ventas v ON dv.id_venta = v.id_venta
    WHERE dv.id_producto = p_id_producto 
      AND v.id_cliente = p_id_cliente 
      AND v.estado != 'Cancelado';

    IF v_compras = 0 THEN
        SET p_mensaje = 'Rechazado: Solo clientes con compra verificada pueden calificar este artículo.';
        LEAVE proc_label;
    END IF;

    INSERT INTO reseñas (id_producto, id_cliente, calificacion, comentario)
    VALUES (p_id_producto, p_id_cliente, p_calificacion, p_comentario)
    ON DUPLICATE KEY UPDATE
        calificacion = VALUES(calificacion),
        comentario = VALUES(comentario),
        fecha_reseña = CURRENT_TIMESTAMP;

    SET p_mensaje = 'Reseña registrada con éxito.';
END //

-- 19. Recomendación de catálogo basada en co-ocurrencia de pedidos cruzados
DROP PROCEDURE IF EXISTS sp_ObtenerProductosRelacionados //
CREATE PROCEDURE sp_ObtenerProductosRelacionados(
    IN p_id_producto INT,
    IN p_limite INT
)
BEGIN
    SELECT 
        p.id_producto,
        p.nombre,
        p.precio,
        p.stock,
        COUNT(*) AS frecuencia_conjunta
    FROM detalle_ventas dv_base
    INNER JOIN detalle_ventas dv_rel ON dv_base.id_venta = dv_rel.id_venta
    INNER JOIN productos p ON dv_rel.id_producto = p.id_producto
    WHERE dv_base.id_producto = p_id_producto
      AND dv_rel.id_producto != p_id_producto
      AND p.activo = TRUE
    GROUP BY p.id_producto, p.nombre, p.precio, p.stock
    ORDER BY frecuencia_conjunta DESC
    LIMIT p_limite;
END //

-- 20. Reclasificación masiva o individual de artículos entre categorías
DROP PROCEDURE IF EXISTS sp_MoverProductosEntreCategorias //
CREATE PROCEDURE sp_MoverProductosEntreCategorias(
    IN p_id_categoria_origen INT,
    IN p_id_categoria_destino INT,
    IN p_id_producto_especifico INT,
    OUT p_filas_afectadas INT,
    OUT p_mensaje VARCHAR(255)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_filas_afectadas = 0;
        SET p_mensaje = 'Error transaccional durante la reclasificación de categorías.';
    END;

    START TRANSACTION;

    IF p_id_producto_especifico IS NOT NULL THEN
        UPDATE productos
        SET id_categoria = p_id_categoria_destino
        WHERE id_producto = p_id_producto_especifico 
          AND id_categoria = p_id_categoria_origen;
    ELSE
        UPDATE productos
        SET id_categoria = p_id_categoria_destino
        WHERE id_categoria = p_id_categoria_origen;
    END IF;

    SET p_filas_afectadas = ROW_COUNT();

    -- Sincronizar contadores de ambas categorías
    UPDATE categorias
    SET total_productos = (SELECT COUNT(*) FROM productos WHERE id_categoria = p_id_categoria_origen AND activo = TRUE)
    WHERE id_categoria = p_id_categoria_origen;

    UPDATE categorias
    SET total_productos = (SELECT COUNT(*) FROM productos WHERE id_categoria = p_id_categoria_destino AND activo = TRUE)
    WHERE id_categoria = p_id_categoria_destino;

    COMMIT;
    SET p_mensaje = CONCAT('Reclasificación completada. ', p_filas_afectadas, ' producto(s) trasladados.');
END //

DELIMITER ;

-- ----------------------------------------------------
-- Permisos de ejecucion sobre procedimientos (antes estaban en 04_Seguridad.sql,
-- pero se movieron aqui porque estos procedimientos no existian todavia en ese punto)
-- ----------------------------------------------------
GRANT EXECUTE ON PROCEDURE ecommerce_db.sp_GenerarReporteMensualVentas TO 'Gerente_Marketing';
GRANT EXECUTE ON PROCEDURE ecommerce_db.sp_ObtenerDashboardAdmin TO 'Gerente_Marketing';

-- ============================================================================
-- NOTAS DE APRENDIZAJE
-- ============================================================================
-- Lo más difícil de este archivo:
-- - Entender el orden de DECLARE (deben ir al principio del bloque)
-- - Manejo de errores con DECLARE EXIT HANDLER FOR SQLEXCEPTION
-- - Uso de JSON para pasar múltiples productos en un solo parámetro
--
-- Lo más interesante:
-- - Ver cómo las transacciones garantizan integridad ACID
-- - sp_RealizarNuevaVenta: procesar venta completa con múltiples productos
-- - sp_FusionarCuentasCliente: fusión de cuentas duplicadas con preservación de datos
--
-- Errores que cometí:
-- - Al principio ponía DECLARE después de ejecutable statements (inválido en MySQL)
-- - Me faltaba FOR UPDATE en SELECT para bloquear filas durante transacciones
-- - En algunos procedimientos no usaba ROLLBACK cuando había error
--
-- Nota: Los procedimientos con transacciones son los más complejos pero también los
-- más importantes. Si algo falla a la mitad, todo se deshace automáticamente. Esto
-- es crítico para operaciones como ventas donde no podemos tener datos inconsistentes.
-- El uso de JSON fue una solución elegante para pasar múltiples productos como
-- parámetro, en lugar de tener múltiples parámetros separados.
