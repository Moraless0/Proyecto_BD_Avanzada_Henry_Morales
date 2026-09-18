-- 04_Seguridad.sql
-- Implementación de seguridad basada en roles (RBAC), control de acceso y cuotas

USE ecommerce_db;

-- ----------------------------------------------------
-- 1. Definición de Roles (RBAC)
-- ----------------------------------------------------

CREATE ROLE IF NOT EXISTS 'Administrador_Sistema';
CREATE ROLE IF NOT EXISTS 'Gerente_Marketing';
CREATE ROLE IF NOT EXISTS 'Analista_Datos';
CREATE ROLE IF NOT EXISTS 'Empleado_Inventario';
CREATE ROLE IF NOT EXISTS 'Atencion_Cliente';
CREATE ROLE IF NOT EXISTS 'Auditor_Financiero';
CREATE ROLE IF NOT EXISTS 'Visitante';

-- ----------------------------------------------------
-- 2. Creación de Usuarios con Políticas de Contraseña
-- ----------------------------------------------------

CREATE USER IF NOT EXISTS 'admin_user'@'localhost' 
    IDENTIFIED BY 'AdminPass2024!Secure'
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LOCK_TIME 2;

CREATE USER IF NOT EXISTS 'marketing_user'@'localhost' 
    IDENTIFIED BY 'Market2024!Promo'
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LOCK_TIME 2;

CREATE USER IF NOT EXISTS 'inventory_user'@'localhost' 
    IDENTIFIED BY 'Inven2024!Stock'
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LOCK_TIME 2;

CREATE USER IF NOT EXISTS 'support_user'@'localhost' 
    IDENTIFIED BY 'Supp2024!HelpDesk'
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LOCK_TIME 2;

-- Usuario analista con cuota de recursos para mitigar sobrecargas por consultas pesadas
CREATE USER IF NOT EXISTS 'analyst_user'@'localhost' 
    IDENTIFIED BY 'Data2024!Analytics'
    WITH MAX_QUERIES_PER_HOUR 1000
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LOCK_TIME 2;

-- ----------------------------------------------------
-- 3. Vistas de Seguridad y Aislamiento de Datos
-- ----------------------------------------------------

-- Vista para personal de atención al cliente: oculta hashes de contraseñas y dirección exacta
CREATE OR REPLACE VIEW v_info_clientes_basica AS
SELECT 
    id_cliente,
    nombre,
    apellido,
    email,
    ciudad,
    fecha_registro,
    fecha_ultima_compra,
    total_gastado,
    id_sucursal,
    activo
FROM clientes;

-- Mapeo de sesión para filtrado de ventas por sucursal (Row-Level Security simulado)
CREATE TABLE IF NOT EXISTS usuario_sucursal (
    usuario VARCHAR(100) PRIMARY KEY,
    id_sucursal INT NOT NULL,
    FOREIGN KEY (id_sucursal) REFERENCES sucursales(id_sucursal) ON DELETE CASCADE
) ENGINE=InnoDB;

INSERT INTO usuario_sucursal (usuario, id_sucursal) VALUES
('support_user', 1),
('inventory_user', 2)
ON DUPLICATE KEY UPDATE id_sucursal = VALUES(id_sucursal);

CREATE OR REPLACE VIEW v_ventas_sucursal_usuario AS
SELECT v.*
FROM ventas v
INNER JOIN usuario_sucursal us ON v.id_sucursal = us.id_sucursal
WHERE us.usuario = SUBSTRING_INDEX(USER(), '@', 1);

-- Tabla de auditoría para registro de fallos de autenticación
CREATE TABLE IF NOT EXISTS auditoria_accesos_fallidos (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    usuario_intentado VARCHAR(100) NOT NULL,
    ip_origen VARCHAR(45) NOT NULL,
    fecha_intento TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    motivo VARCHAR(255) DEFAULT 'Credenciales inválidas o cuenta bloqueada'
) ENGINE=InnoDB;

-- ----------------------------------------------------
-- 4. Asignación de Privilegios a Roles
-- ----------------------------------------------------

-- Administrador: control total sobre la base de datos
GRANT ALL PRIVILEGES ON ecommerce_db.* TO 'Administrador_Sistema' WITH GRANT OPTION;

-- Marketing: lectura de ventas, clientes y catálogo de productos
GRANT SELECT ON ecommerce_db.ventas TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.clientes TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.productos TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.categorias TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.promociones TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.resumen_ventas_diario TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.kpis_mensuales TO 'Gerente_Marketing';

-- Analista de datos: lectura global excepto tablas de auditoría sensible
-- Al no otorgar permisos DELETE ni DROP (que gobierna TRUNCATE), quedan bloqueados por diseño
GRANT SELECT ON ecommerce_db.productos TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.categorias TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.proveedores TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.clientes TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.ventas TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.sucursales TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.promociones TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.reseñas TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.kpis_mensuales TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.productos_ranking TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.proveedor_rendimiento TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.resumen_ventas_diario TO 'Analista_Datos';

-- Inventario: lectura de catálogo y actualización exclusiva de columnas operativas
-- Se excluye explícitamente la columna precio y costo
GRANT SELECT ON ecommerce_db.productos TO 'Empleado_Inventario';
GRANT SELECT ON ecommerce_db.categorias TO 'Empleado_Inventario';
GRANT SELECT ON ecommerce_db.proveedores TO 'Empleado_Inventario';
GRANT UPDATE (stock, stock_minimo, peso, activo) ON ecommerce_db.productos TO 'Empleado_Inventario';

-- Atención al cliente: vista anonimizada de clientes y seguimiento de órdenes
GRANT SELECT ON ecommerce_db.v_info_clientes_basica TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.ventas TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.productos TO 'Atencion_Cliente';
GRANT UPDATE (estado) ON ecommerce_db.ventas TO 'Atencion_Cliente';

-- Auditor financiero: lectura de transacciones, catálogo y bitácoras de precios
GRANT SELECT ON ecommerce_db.ventas TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.productos TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.log_cambios_precio TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.ventas_archivadas TO 'Auditor_Financiero';

-- Visitante: catálogo público
GRANT SELECT ON ecommerce_db.productos TO 'Visitante';

-- ----------------------------------------------------
-- 5. Concesión de Ejecución de Procedimientos
-- ----------------------------------------------------

-- Nota: los GRANT EXECUTE sobre sp_GenerarReporteMensualVentas y sp_ObtenerDashboardAdmin
-- se movieron al final de 07_Procedimientos_Almacenados.sql, porque esos procedimientos
-- no existen todavia en este punto del orden de ejecucion (04 se corre antes que 07).

-- ----------------------------------------------------
-- 6. Asignación de Roles a Cuentas y Activación por Defecto
-- ----------------------------------------------------

GRANT 'Administrador_Sistema' TO 'admin_user'@'localhost';
SET DEFAULT ROLE 'Administrador_Sistema' TO 'admin_user'@'localhost';

GRANT 'Gerente_Marketing' TO 'marketing_user'@'localhost';
SET DEFAULT ROLE 'Gerente_Marketing' TO 'marketing_user'@'localhost';

GRANT 'Empleado_Inventario' TO 'inventory_user'@'localhost';
SET DEFAULT ROLE 'Empleado_Inventario' TO 'inventory_user'@'localhost';

GRANT 'Atencion_Cliente' TO 'support_user'@'localhost';
SET DEFAULT ROLE 'Atencion_Cliente' TO 'support_user'@'localhost';

GRANT 'Analista_Datos' TO 'analyst_user'@'localhost';
SET DEFAULT ROLE 'Analista_Datos' TO 'analyst_user'@'localhost';

-- ----------------------------------------------------
-- 7. Restricciones Perimetrales de Seguridad
-- ----------------------------------------------------

-- Impedir acceso remoto del superusuario root asegurando que solo opere en local
DELETE FROM mysql.user 
WHERE User = 'root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

FLUSH PRIVILEGES;

-- ============================================================================
-- NOTAS DE APRENDIZAJE
-- ============================================================================
-- Lo más difícil de este archivo:
-- - Entender bien el modelo RBAC y cómo se relacionan roles y usuarios
-- - WITH MAX_QUERIES_PER_HOUR: cómo limitar recursos por usuario
-- - Crear vistas de seguridad que ocultan información sensible
--
-- Lo más interesante:
-- - Ver cómo el principio de menor privilegio se aplica en la práctica
-- - Las vistas de seguridad: v_info_clientes_basica oculta contraseñas y direcciones
-- - WITH GRANT OPTION: cómo permitir que un usuario dé permisos a otros
--
-- Errores que cometí:
-- - Al principio intenté dar permisos directamente a usuarios en lugar de roles
-- - Me faltó REVOKE para quitar permisos de tablas de auditoría al Analista_Datos
-- - No entendía bien la diferencia entre @'%' y @'localhost' para hosts
--
-- Nota: Para ejecutar este archivo necesitas permisos de administrador. Si te da
-- error de permisos, ejecuta como root o pide a tu profesor que te dé los permisos.
