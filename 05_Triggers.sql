-- 05_Triggers.sql
-- Automatización de integridad de datos, reglas de negocio y bitácoras de auditoría

USE ecommerce_db;

-- ----------------------------------------------------
-- Tabla de auditoría requerida para cambios de precios
-- ----------------------------------------------------

CREATE TABLE IF NOT EXISTS log_cambios_precio (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    precio_anterior DECIMAL(10,2) NOT NULL,
    precio_nuevo DECIMAL(10,2) NOT NULL,
    fecha_cambio TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    usuario VARCHAR(100),
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE CASCADE
) ENGINE=InnoDB;

DELIMITER //

-- 1. Audita modificaciones al precio de lista registrando usuario y delta
DROP TRIGGER IF EXISTS trg_audit_precio_producto_after_update //
CREATE TRIGGER trg_audit_precio_producto_after_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF OLD.precio != NEW.precio THEN
        INSERT INTO log_cambios_precio (id_producto, precio_anterior, precio_nuevo, usuario)
        VALUES (NEW.id_producto, OLD.precio, NEW.precio, CURRENT_USER());
    END IF;
END //

-- 2. Valida stock suficiente antes de permitir la inserción del ítem en la venta
DROP TRIGGER IF EXISTS trg_check_stock_before_insert_venta //
CREATE TRIGGER trg_check_stock_before_insert_venta
BEFORE INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    DECLARE v_stock_disponible INT;
    
    SELECT stock INTO v_stock_disponible
    FROM productos
    WHERE id_producto = NEW.id_producto;
    
    IF v_stock_disponible < NEW.cantidad THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Stock insuficiente para procesar la línea de pedido.';
    END IF;
END //

-- 3. Descuenta automáticamente las unidades del inventario tras confirmar la línea de venta
DROP TRIGGER IF EXISTS trg_update_stock_after_insert_venta //
CREATE TRIGGER trg_update_stock_after_insert_venta
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE productos
    SET stock = stock - NEW.cantidad
    WHERE id_producto = NEW.id_producto;
END //

-- 4. Impide la eliminación física de categorías con artículos enlazados
DROP TRIGGER IF EXISTS trg_prevent_delete_categoria_with_products //
CREATE TRIGGER trg_prevent_delete_categoria_with_products
BEFORE DELETE ON categorias
FOR EACH ROW
BEGIN
    DECLARE v_articulos INT DEFAULT 0;
    
    SELECT COUNT(*) INTO v_articulos
    FROM productos
    WHERE id_categoria = OLD.id_categoria;
    
    IF v_articulos > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Integridad referencial: No se puede eliminar una categoría con productos asignados.';
    END IF;
END //

-- 5. Bitácora de altas de usuarios para trazabilidad comercial
DROP TRIGGER IF EXISTS trg_log_new_customer_after_insert //
CREATE TRIGGER trg_log_new_customer_after_insert
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
    INSERT INTO log_clientes_nuevos (id_cliente, nombre, email, fecha_registro)
    VALUES (NEW.id_cliente, NEW.nombre, NEW.email, NEW.fecha_registro);
END //

-- 6. Actualiza el acumulador de gasto de por vida (LTV) del cliente al registrarse una venta
DROP TRIGGER IF EXISTS trg_update_total_gastado_cliente //
CREATE TRIGGER trg_update_total_gastado_cliente
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    UPDATE clientes
    SET total_gastado = total_gastado + NEW.total,
        fecha_ultima_compra = NEW.fecha_venta
    WHERE id_cliente = NEW.id_cliente;
END //

-- 7. Actualiza explícitamente el timestamp de modificación del producto
DROP TRIGGER IF EXISTS trg_set_fecha_modificacion_producto //
CREATE TRIGGER trg_set_fecha_modificacion_producto
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    SET NEW.fecha_modificacion = CURRENT_TIMESTAMP;
END //

-- 8. Doble barrera para evitar que actualizaciones directas dejen stock negativo
DROP TRIGGER IF EXISTS trg_prevent_negative_stock //
CREATE TRIGGER trg_prevent_negative_stock
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error de inventario: El stock no puede ser un valor negativo.';
    END IF;
END //

-- 9. Normaliza nombres y apellidos aplicando formato de nombre propio
DROP TRIGGER IF EXISTS trg_capitalize_nombre_cliente //
CREATE TRIGGER trg_capitalize_nombre_cliente
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    SET NEW.nombre = CONCAT(UPPER(LEFT(NEW.nombre, 1)), LOWER(SUBSTRING(NEW.nombre, 2)));
    SET NEW.apellido = CONCAT(UPPER(LEFT(NEW.apellido, 1)), LOWER(SUBSTRING(NEW.apellido, 2)));
END //

-- 10. Recalcula el monto total de la venta si se actualiza un detalle
DROP TRIGGER IF EXISTS trg_recalculate_total_venta_on_detalle_change //
CREATE TRIGGER trg_recalculate_total_venta_on_detalle_change
AFTER UPDATE ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
    SET total = (
        SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0.00)
        FROM detalle_ventas
        WHERE id_venta = NEW.id_venta
    )
    WHERE id_venta = NEW.id_venta;
END //

-- 11. Auditoría del ciclo de vida de pedidos (seguimiento logístico)
DROP TRIGGER IF EXISTS trg_log_order_status_change //
CREATE TRIGGER trg_log_order_status_change
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF OLD.estado != NEW.estado THEN
        INSERT INTO log_estados_pedido (id_venta, estado_anterior, estado_nuevo, usuario)
        VALUES (NEW.id_venta, OLD.estado, NEW.estado, CURRENT_USER());
    END IF;
END //

-- 12. Regla comercial: rechaza fijación de precios iguales o menores a cero
DROP TRIGGER IF EXISTS trg_prevent_price_zero_or_less //
CREATE TRIGGER trg_prevent_price_zero_or_less
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error comercial: El precio unitario debe ser estrictamente mayor a cero.';
    END IF;
END //

-- 13. Genera notificación de reabastecimiento cuando el stock perfora el umbral mínimo
DROP TRIGGER IF EXISTS trg_send_stock_alert_on_low_stock //
CREATE TRIGGER trg_send_stock_alert_on_low_stock
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock <= NEW.stock_minimo AND OLD.stock > NEW.stock_minimo THEN
        INSERT INTO alertas (id_producto, tipo_alerta, mensaje, stock_actual)
        VALUES (
            NEW.id_producto, 
            'STOCK_BAJO', 
            CONCAT('Producto ', NEW.nombre, ' (SKU: ', NEW.sku, ') por debajo del umbral mínimo de ', NEW.stock_minimo, ' unidades.'),
            NEW.stock
        );
    END IF;
END //

-- 14. Soft-delete o respaldo forense: archiva pedidos antes de su eliminación física
DROP TRIGGER IF EXISTS trg_archive_deleted_venta //
CREATE TRIGGER trg_archive_deleted_venta
BEFORE DELETE ON ventas
FOR EACH ROW
BEGIN
    INSERT INTO ventas_archivadas (id_venta_original, fecha_venta, total, id_cliente, motivo)
    VALUES (OLD.id_venta, OLD.fecha_venta, OLD.total, OLD.id_cliente, 'Eliminación manual desde módulo administrativo');
END //

-- 15. Validación de sintaxis de correo electrónico previo al guardado del cliente
DROP TRIGGER IF EXISTS trg_validate_email_format_on_customer //
CREATE TRIGGER trg_validate_email_format_on_customer
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NEW.email NOT REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Validación fallida: Formato de correo electrónico inválido.';
    END IF;
END //

-- 16. Actualiza la fecha de última interacción transaccional del cliente
DROP TRIGGER IF EXISTS trg_update_last_order_date_customer //
CREATE TRIGGER trg_update_last_order_date_customer
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    UPDATE clientes
    SET fecha_ultima_compra = NEW.fecha_venta
    WHERE id_cliente = NEW.id_cliente;
END //

-- 17. Previene autorreferenciación fraudulenta en el programa de afiliados
DROP TRIGGER IF EXISTS trg_prevent_self_referral //
CREATE TRIGGER trg_prevent_self_referral
BEFORE INSERT ON programa_referidos
FOR EACH ROW
BEGIN
    IF NEW.id_cliente_referente = NEW.id_cliente_referido THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Fraude detectado: Un cliente no puede referirse a sí mismo.';
    END IF;
END //

-- 18. Registra modificaciones en las asignaciones de usuarios a sucursales
DROP TRIGGER IF EXISTS trg_log_permission_changes //
CREATE TRIGGER trg_log_permission_changes
AFTER UPDATE ON usuario_sucursal
FOR EACH ROW
BEGIN
    INSERT INTO log_permisos (usuario, accion, permiso)
    VALUES (
        CURRENT_USER(), 
        'MODIFICAR_SUCURSAL_USUARIO', 
        CONCAT('Usuario: ', NEW.usuario, ' reasignado de sucursal ', OLD.id_sucursal, ' a ', NEW.id_sucursal)
    );
END //

-- 19. Asigna categoría por defecto "General" ante inserciones con categoría nula
DROP TRIGGER IF EXISTS trg_assign_default_category_on_null //
CREATE TRIGGER trg_assign_default_category_on_null
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    DECLARE v_id_general INT;
    
    IF NEW.id_categoria IS NULL THEN
        SELECT id_categoria INTO v_id_general
        FROM categorias
        WHERE nombre = 'General'
        LIMIT 1;
        
        IF v_id_general IS NULL THEN
            INSERT INTO categorias (nombre, descripcion)
            VALUES ('General', 'Categoría comodín para artículos sin clasificar');
            SET v_id_general = LAST_INSERT_ID();
        END IF;
        
        SET NEW.id_categoria = v_id_general;
    END IF;
END //

-- 20. Mantiene sincronizado el contador de productos asignados por categoría
DROP TRIGGER IF EXISTS trg_update_producto_count_in_categoria //
CREATE TRIGGER trg_update_producto_count_in_categoria
AFTER INSERT ON productos
FOR EACH ROW
BEGIN
    IF NEW.id_categoria IS NOT NULL THEN
        UPDATE categorias
        SET total_productos = total_productos + 1
        WHERE id_categoria = NEW.id_categoria;
    END IF;
END //

DELIMITER ;

-- ============================================================================
-- NOTAS DE APRENDIZAJE
-- ============================================================================
-- Lo más difícil de este archivo:
-- - Entender la diferencia entre BEFORE y AFTER
-- - Uso de OLD y NEW: cuándo usar cada uno
-- - Evitar loops infinitos cuando un trigger dispara otro trigger
--
-- Lo más interesante:
-- - Ver cómo los triggers automatizan reglas de negocio
-- - SIGNAL SQLSTATE: cómo crear errores personalizados
-- - Doble barrera de seguridad: CHECK constraints + triggers
--
-- Errores que cometí:
-- - Al principio ponía triggers AFTER para validaciones (deberían ser BEFORE)
-- - En algunos triggers usaba solo NEW cuando necesitaba OLD también
-- - Me faltaba la condición IF OLD.precio != NEW.precio en el trigger de auditoría
--
-- Nota: Los triggers son muy potentes pero también pueden causar problemas si no
-- se diseñan bien. A veces es mejor combinar varios triggers en uno solo para
-- evitar conflictos.
