-- 03_Funciones.sql
-- Funciones definidas por el usuario (UDF) para lógica de negocio reutilizable

USE ecommerce_db;

DELIMITER //

-- 1. Calcula el total liquidado de una orden sumando las líneas de detalle_ventas
DROP FUNCTION IF EXISTS fn_CalcularTotalVenta //
CREATE FUNCTION fn_CalcularTotalVenta(p_id_venta INT) 
RETURNS DECIMAL(12,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2);
    
    SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0.00) INTO v_total
    FROM detalle_ventas
    WHERE id_venta = p_id_venta;
    
    RETURN v_total;
END //

-- 2. Valida existencias antes de comprometer inventario
DROP FUNCTION IF EXISTS fn_VerificarDisponibilidadStock //
CREATE FUNCTION fn_VerificarDisponibilidadStock(p_id_producto INT, p_cantidad INT) 
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_stock_actual INT DEFAULT 0;
    
    SELECT stock INTO v_stock_actual
    FROM productos
    WHERE id_producto = p_id_producto;
    
    RETURN (v_stock_actual >= p_cantidad);
END //

-- 3. Retorna el precio de lista vigente de un producto
DROP FUNCTION IF EXISTS fn_ObtenerPrecioProducto //
CREATE FUNCTION fn_ObtenerPrecioProducto(p_id_producto INT) 
RETURNS DECIMAL(10,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_precio DECIMAL(10,2) DEFAULT 0.00;
    
    SELECT precio INTO v_precio
    FROM productos
    WHERE id_producto = p_id_producto;
    
    RETURN v_precio;
END //

-- 4. Cálculo de edad en base a fecha de nacimiento
DROP FUNCTION IF EXISTS fn_CalcularEdadCliente //
CREATE FUNCTION fn_CalcularEdadCliente(p_fecha_nacimiento DATE) 
RETURNS INT
DETERMINISTIC
NO SQL
BEGIN
    IF p_fecha_nacimiento IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN TIMESTAMPDIFF(YEAR, p_fecha_nacimiento, CURDATE());
END //

-- 5. Formatea nombre completo bajo estándar "Nombre Apellido"
DROP FUNCTION IF EXISTS fn_FormatearNombreCompleto //
CREATE FUNCTION fn_FormatearNombreCompleto(p_nombre VARCHAR(100), p_apellido VARCHAR(100)) 
RETURNS VARCHAR(201)
DETERMINISTIC
NO SQL
BEGIN
    RETURN TRIM(CONCAT(COALESCE(p_nombre, ''), ' ', COALESCE(p_apellido, '')));
END //

-- 6. Evalúa si la primera compra del cliente ocurrió en los últimos 30 días
DROP FUNCTION IF EXISTS fn_EsClienteNuevo //
CREATE FUNCTION fn_EsClienteNuevo(p_id_cliente INT) 
RETURNS BOOLEAN
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_primera_compra TIMESTAMP;
    
    SELECT MIN(fecha_venta) INTO v_primera_compra
    FROM ventas
    WHERE id_cliente = p_id_cliente AND estado != 'Cancelado';
    
    IF v_primera_compra IS NULL THEN
        RETURN FALSE;
    END IF;
    
    RETURN (v_primera_compra >= DATE_SUB(NOW(), INTERVAL 30 DAY));
END //

-- 7. Costo logístico: tarifa base (Q25.00) + Q5.00 por kilogramo adicional
DROP FUNCTION IF EXISTS fn_CalcularCostoEnvio //
CREATE FUNCTION fn_CalcularCostoEnvio(p_id_venta INT) 
RETURNS DECIMAL(10,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_peso_total DECIMAL(10,2) DEFAULT 0.00;
    
    SELECT COALESCE(SUM(p.peso * dv.cantidad), 0.00) INTO v_peso_total
    FROM detalle_ventas dv
    INNER JOIN productos p ON dv.id_producto = p.id_producto
    WHERE dv.id_venta = p_id_venta;
    
    RETURN 25.00 + (v_peso_total * 5.00);
END //

-- 8. Aplica descuento porcentual sobre un monto base
DROP FUNCTION IF EXISTS fn_AplicarDescuento //
CREATE FUNCTION fn_AplicarDescuento(p_monto DECIMAL(12,2), p_porcentaje DECIMAL(5,2)) 
RETURNS DECIMAL(12,2)
DETERMINISTIC
NO SQL
BEGIN
    IF p_porcentaje <= 0 THEN
        RETURN p_monto;
    END IF;
    RETURN ROUND(p_monto * (1 - (p_porcentaje / 100)), 2);
END //

-- 9. Retorna la marca de tiempo de la orden confirmada más reciente
DROP FUNCTION IF EXISTS fn_ObtenerUltimaFechaCompra //
CREATE FUNCTION fn_ObtenerUltimaFechaCompra(p_id_cliente INT) 
RETURNS TIMESTAMP
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_ultima_compra TIMESTAMP;
    
    SELECT MAX(fecha_venta) INTO v_ultima_compra
    FROM ventas
    WHERE id_cliente = p_id_cliente AND estado != 'Cancelado';
    
    RETURN v_ultima_compra;
END //

-- 10. Validación sintáctica de email mediante expresión regular RFC-compliant básica
DROP FUNCTION IF EXISTS fn_ValidarFormatoEmail //
CREATE FUNCTION fn_ValidarFormatoEmail(p_email VARCHAR(150)) 
RETURNS BOOLEAN
DETERMINISTIC
NO SQL
BEGIN
    RETURN (p_email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$');
END //

-- 11. Resuelve el nombre descriptivo de la categoría de un producto dado
DROP FUNCTION IF EXISTS fn_ObtenerNombreCategoria //
CREATE FUNCTION fn_ObtenerNombreCategoria(p_id_producto INT) 
RETURNS VARCHAR(100)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_categoria VARCHAR(100);
    
    SELECT c.nombre INTO v_categoria
    FROM productos p
    INNER JOIN categorias c ON p.id_categoria = c.id_categoria
    WHERE p.id_producto = p_id_producto;
    
    RETURN v_categoria;
END //

-- 12. Contador de transacciones efectivas históricas del cliente
DROP FUNCTION IF EXISTS fn_ContarVentasCliente //
CREATE FUNCTION fn_ContarVentasCliente(p_id_cliente INT) 
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT DEFAULT 0;
    
    SELECT COUNT(*) INTO v_total
    FROM ventas
    WHERE id_cliente = p_id_cliente AND estado != 'Cancelado';
    
    RETURN v_total;
END //

-- 13. Días de recencia desde la última transacción (retorna NULL si no registra compras)
DROP FUNCTION IF EXISTS fn_CalcularDiasDesdeUltimaCompra //
CREATE FUNCTION fn_CalcularDiasDesdeUltimaCompra(p_id_cliente INT) 
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_ultima_fecha TIMESTAMP;
    
    SELECT MAX(fecha_venta) INTO v_ultima_fecha
    FROM ventas
    WHERE id_cliente = p_id_cliente AND estado != 'Cancelado';
    
    IF v_ultima_fecha IS NULL THEN
        RETURN NULL;
    END IF;
    
    RETURN DATEDIFF(CURDATE(), v_ultima_fecha);
END //

-- 14. Segmentación de cliente según consumo monetario acumulado
DROP FUNCTION IF EXISTS fn_DeterminarEstadoLealtad //
CREATE FUNCTION fn_DeterminarEstadoLealtad(p_id_cliente INT) 
RETURNS VARCHAR(20)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_gasto_total DECIMAL(12,2) DEFAULT 0.00;
    
    SELECT COALESCE(SUM(total), 0.00) INTO v_gasto_total
    FROM ventas
    WHERE id_cliente = p_id_cliente AND estado != 'Cancelado';
    
    IF v_gasto_total >= 4000.00 THEN
        RETURN 'Oro';
    ELSEIF v_gasto_total >= 1500.00 THEN
        RETURN 'Plata';
    ELSE
        RETURN 'Bronce';
    END IF;
END //

-- 15. Generación algorítmica de SKU: [CAT]-[NOMBRE]-[HASH_CORTO]
DROP FUNCTION IF EXISTS fn_GenerarSKU //
CREATE FUNCTION fn_GenerarSKU(p_nombre VARCHAR(200), p_id_categoria INT) 
RETURNS VARCHAR(50)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_cat_abrev VARCHAR(4);
    DECLARE v_nom_abrev VARCHAR(6);
    DECLARE v_sufijo VARCHAR(4);
    
    SELECT UPPER(SUBSTRING(COALESCE(nombre, 'GEN'), 1, 3)) INTO v_cat_abrev
    FROM categorias
    WHERE id_categoria = p_id_categoria;
    
    IF v_cat_abrev IS NULL THEN
        SET v_cat_abrev = 'GEN';
    END IF;
    
    SET v_nom_abrev = UPPER(REGEXP_REPLACE(LEFT(p_nombre, 5), '[^a-zA-Z0-9]', ''));
    SET v_sufijo = LPAD(MOD(CONV(SUBSTRING(MD5(p_nombre), 1, 4), 16, 10), 1000), 3, '0');
    
    RETURN CONCAT(v_cat_abrev, '-', v_nom_abrev, '-', v_sufijo);
END //

-- 16. Desglose de impuesto al valor agregado (IVA 12% régimen general)
DROP FUNCTION IF EXISTS fn_CalcularIVA //
CREATE FUNCTION fn_CalcularIVA(p_monto DECIMAL(12,2)) 
RETURNS DECIMAL(12,2)
DETERMINISTIC
NO SQL
BEGIN
    RETURN ROUND(p_monto * 0.12, 2);
END //

-- 17. Total de unidades físicas disponibles por categoría para control de inventario
DROP FUNCTION IF EXISTS fn_ObtenerStockTotalPorCategoria //
CREATE FUNCTION fn_ObtenerStockTotalPorCategoria(p_id_categoria INT) 
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_stock_total INT DEFAULT 0;
    
    SELECT COALESCE(SUM(stock), 0) INTO v_stock_total
    FROM productos
    WHERE id_categoria = p_id_categoria AND activo = TRUE;
    
    RETURN v_stock_total;
END //

-- 18. SLA de entrega según municipio/ciudad de la sucursal de despacho
DROP FUNCTION IF EXISTS fn_EstimarFechaEntrega //
CREATE FUNCTION fn_EstimarFechaEntrega(p_id_venta INT) 
RETURNS DATE
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_ciudad VARCHAR(100);
    DECLARE v_dias INT DEFAULT 3;
    
    SELECT s.ciudad INTO v_ciudad
    FROM ventas v
    INNER JOIN sucursales s ON v.id_sucursal = s.id_sucursal
    WHERE v.id_venta = p_id_venta;
    
    IF v_ciudad = 'Ciudad de Guatemala' THEN
        SET v_dias = 1;
    ELSEIF v_ciudad IN ('Villa Nueva', 'Mixco', 'San Lucas') THEN
        SET v_dias = 2;
    ELSE
        SET v_dias = 4;
    END IF;
    
    RETURN DATE_ADD(CURDATE(), INTERVAL v_dias DAY);
END //

-- 19. Conversión de moneda (ej. GTQ a USD o EUR) con tasa paramétrica
DROP FUNCTION IF EXISTS fn_ConvertirMoneda //
CREATE FUNCTION fn_ConvertirMoneda(p_monto DECIMAL(12,2), p_tasa_cambio DECIMAL(10,4)) 
RETURNS DECIMAL(12,2)
DETERMINISTIC
NO SQL
BEGIN
    IF p_tasa_cambio <= 0 THEN
        RETURN 0.00;
    END IF;
    RETURN ROUND(p_monto * p_tasa_cambio, 2);
END //

-- 20. Política de seguridad: mínimo 8 caracteres, al menos 1 mayúscula, 1 minúscula, 1 número y 1 símbolo
DROP FUNCTION IF EXISTS fn_ValidarComplejidadContraseña //
CREATE FUNCTION fn_ValidarComplejidadContraseña(p_contrasena VARCHAR(255)) 
RETURNS BOOLEAN
DETERMINISTIC
NO SQL
BEGIN
    IF CHAR_LENGTH(p_contrasena) < 8 THEN
        RETURN FALSE;
    END IF;
    
    IF p_contrasena NOT REGEXP '[A-Z]' THEN
        RETURN FALSE;
    END IF;
    
    IF p_contrasena NOT REGEXP '[a-z]' THEN
        RETURN FALSE;
    END IF;
    
    IF p_contrasena NOT REGEXP '[0-9]' THEN
        RETURN FALSE;
    END IF;
    
    IF p_contrasena NOT REGEXP '[\$!@#%^&*()_+\\-=\\[\\]{};:\'",.<>/?~`|\\\\]' THEN
        RETURN FALSE;
    END IF;
    
    RETURN TRUE;
END //

DELIMITER ;

-- ============================================================================
-- NOTAS DE APRENDIZAJE
-- ============================================================================
-- Lo más difícil de este archivo:
-- - REGEXP: aprender la sintaxis de expresiones regulares fue un reto
-- - fn_GenerarSKU: combinar MD5, conversión de bases y padding fue técnico
-- - Entender DETERMINISTIC vs NOT DETERMINISTIC: cuándo usar cada uno
--
-- Lo más interesante:
-- - Ver cómo las funciones encapsulan lógica reutilizable
-- - fn_ValidarComplejidadContraseña: entender validaciones paso a paso
-- - fn_CalcularCostoEnvio: cómo se calculan costos basados en peso
--
-- Errores que cometí:
-- - Al principio usaba DETERMINISTIC en funciones que leen de la BD (incorrecto)
-- - En fn_GenerarSKU, olvidaba el caso cuando la categoría no existe
-- - En REGEXP, tenía problemas con caracteres especiales que necesitan escape
--
-- Nota: Para poder usar estas funciones en procedimientos, aprendí que primero
-- tienen que estar creadas, por eso el orden de ejecución es importante.
