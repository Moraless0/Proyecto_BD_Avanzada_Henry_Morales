USE ecommerce_db;

-- Tabla para registrar las devoluciones de productos
DROP TABLE IF EXISTS devoluciones;

CREATE TABLE devoluciones (
    id_devolucion INT AUTO_INCREMENT PRIMARY KEY,
    id_venta INT NOT NULL,
    id_producto INT NOT NULL,
    cantidad INT NOT NULL CHECK (cantidad > 0),
    motivo VARCHAR(255) NOT NULL,
    fecha_devolucion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    monto_reembolsado DECIMAL(10,2) NOT NULL CHECK (monto_reembolsado >= 0),
    FOREIGN KEY (id_venta) REFERENCES ventas(id_venta) ON DELETE RESTRICT,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE RESTRICT
) ENGINE=InnoDB;

DELIMITER //

DROP PROCEDURE IF EXISTS sp_ProcesarDevolucion//

CREATE PROCEDURE sp_ProcesarDevolucion(
    IN p_id_venta INT,
    IN p_id_producto INT,
    IN p_cantidad_devuelta INT,
    IN p_motivo VARCHAR(255)
)
BEGIN
    DECLARE v_cantidad_comprada INT;
    DECLARE v_precio_unitario DECIMAL(10,2);
    DECLARE v_monto_reembolso DECIMAL(10,2);
    DECLARE v_total_venta DECIMAL(12,2);
    DECLARE v_cantidad_total_devuelta INT;
    DECLARE v_error_message VARCHAR(255);
    
    -- Iniciar transacción para asegurar atomicidad
    START TRANSACTION;
    
    -- Bloque de manejo de errores
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
    END;
    
    -- Validar que la venta existe
    IF NOT EXISTS (SELECT 1 FROM ventas WHERE id_venta = p_id_venta) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La venta no existe';
    END IF;
    
    -- Validar que el producto existe
    IF NOT EXISTS (SELECT 1 FROM productos WHERE id_producto = p_id_producto) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto no existe';
    END IF;
    
    -- Obtener cantidad comprada y precio unitario del detalle de venta
    SELECT cantidad, precio_unitario_congelado 
    INTO v_cantidad_comprada, v_precio_unitario
    FROM detalle_ventas
    WHERE id_venta = p_id_venta AND id_producto = p_id_producto;
    
    -- Validar que el producto estaba en esa venta
    IF v_cantidad_comprada IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto no pertenece a esta venta';
    END IF;
    
    -- Validar que la cantidad a devolver no exceda la cantidad comprada
    IF p_cantidad_devuelta > v_cantidad_comprada THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad a devolver excede la cantidad comprada';
    END IF;
    
    -- Validar que la cantidad sea positiva
    IF p_cantidad_devuelta <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad a devolver debe ser mayor a cero';
    END IF;
    
    -- Calcular monto del reembolso
    SET v_monto_reembolso = p_cantidad_devuelta * v_precio_unitario;
    
    -- Incrementar stock del producto
    UPDATE productos 
    SET stock = stock + p_cantidad_devuelta
    WHERE id_producto = p_id_producto;
    
    -- Calcular total de la venta
    SELECT total INTO v_total_venta FROM ventas WHERE id_venta = p_id_venta;
    
    -- Calcular cantidad total ya devuelta para este producto en esta venta
    SELECT COALESCE(SUM(cantidad), 0) INTO v_cantidad_total_devuelta
    FROM devoluciones
    WHERE id_venta = p_id_venta AND id_producto = p_id_producto;
    
    -- Determinar nuevo estado de la venta
    IF (v_cantidad_total_devuelta + p_cantidad_devuelta) = v_cantidad_comprada THEN
        -- Todo el producto fue devuelto, verificar si es la única devolución
        -- Si es la única devolución y cubre todo, marcar como devuelto totalmente
        UPDATE ventas 
        SET estado = 'Devuelto Totalmente'
        WHERE id_venta = p_id_venta;
    ELSE
        -- Devolución parcial
        UPDATE ventas 
        SET estado = 'Devolución Parcial'
        WHERE id_venta = p_id_venta;
    END IF;
    
    -- Registrar la devolución en la tabla
    INSERT INTO devoluciones (id_venta, id_producto, cantidad, motivo, monto_reembolsado)
    VALUES (p_id_venta, p_id_producto, p_cantidad_devuelta, p_motivo, v_monto_reembolso);
    
    -- Confirmar transacción
    COMMIT;
    
END//

DELIMITER ;