-- 01_Esquema_y_Datos.sql
-- Definición del esquema DDL y carga inicial de datos para ecommerce_db

CREATE DATABASE IF NOT EXISTS ecommerce_db 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

USE ecommerce_db;

-- ----------------------------------------------------
-- Tablas principales del modelo de negocio
-- ----------------------------------------------------

CREATE TABLE categorias (
    id_categoria INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT,
    total_productos INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE proveedores (
    id_proveedor INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(150) NOT NULL,
    email_contacto VARCHAR(100) UNIQUE,
    telefono_contacto VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE sucursales (
    id_sucursal INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    direccion VARCHAR(255),
    ciudad VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE productos (
    id_producto INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(200) NOT NULL UNIQUE,
    descripcion TEXT,
    precio DECIMAL(10,2) NOT NULL CHECK (precio > 0),
    costo DECIMAL(10,2) NOT NULL CHECK (costo >= 0),
    stock INT NOT NULL DEFAULT 0 CHECK (stock >= 0),
    stock_minimo INT NOT NULL DEFAULT 10 CHECK (stock_minimo >= 0),
    sku VARCHAR(50) NOT NULL UNIQUE,
    peso DECIMAL(8,2) DEFAULT 0.00,
    vistas INT DEFAULT 0,
    activo BOOLEAN DEFAULT TRUE,
    id_categoria INT,
    id_proveedor INT,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (id_categoria) REFERENCES categorias(id_categoria) ON DELETE SET NULL,
    FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE clientes (
    id_cliente INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    contraseña VARCHAR(255) NOT NULL,
    direccion_envio TEXT,
    ciudad VARCHAR(100),
    fecha_nacimiento DATE,
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_gastado DECIMAL(12,2) DEFAULT 0.00,
    fecha_ultima_compra TIMESTAMP NULL,
    id_sucursal INT,
    activo BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (id_sucursal) REFERENCES sucursales(id_sucursal) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE ventas (
    id_venta INT AUTO_INCREMENT PRIMARY KEY,
    fecha_venta TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    estado ENUM('Pendiente de Pago', 'Procesando', 'Enviado', 'Entregado', 'Cancelado') NOT NULL DEFAULT 'Pendiente de Pago',
    total DECIMAL(12,2) NOT NULL DEFAULT 0.00 CHECK (total >= 0),
    id_cliente INT NOT NULL,
    id_sucursal INT,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente) ON DELETE RESTRICT,
    FOREIGN KEY (id_sucursal) REFERENCES sucursales(id_sucursal) ON DELETE SET NULL
) ENGINE=InnoDB;

-- Tabla puente que resuelve la relación N:M entre ventas y productos.
-- precio_unitario_congelado almacena el valor pactado al momento de compra para no romper el histórico contable.
CREATE TABLE detalle_ventas (
    id_detalle INT AUTO_INCREMENT PRIMARY KEY,
    cantidad INT NOT NULL CHECK (cantidad > 0),
    precio_unitario_congelado DECIMAL(10,2) NOT NULL CHECK (precio_unitario_congelado > 0),
    id_venta INT NOT NULL,
    id_producto INT NOT NULL,
    FOREIGN KEY (id_venta) REFERENCES ventas(id_venta) ON DELETE CASCADE,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ----------------------------------------------------
-- Tablas auxiliares (auditoría, logs, agregaciones y módulos)
-- ----------------------------------------------------

CREATE TABLE log_cambios_precio (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    precio_anterior DECIMAL(10,2) NOT NULL,
    precio_nuevo DECIMAL(10,2) NOT NULL,
    fecha_cambio TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    usuario VARCHAR(100),
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE log_clientes_nuevos (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    nombre VARCHAR(100),
    email VARCHAR(150),
    fecha_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE log_estados_pedido (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    id_venta INT NOT NULL,
    estado_anterior VARCHAR(50),
    estado_nuevo VARCHAR(50) NOT NULL,
    fecha_cambio TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    usuario VARCHAR(100),
    FOREIGN KEY (id_venta) REFERENCES ventas(id_venta) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE log_permisos (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    usuario VARCHAR(100) NOT NULL,
    accion VARCHAR(50) NOT NULL,
    permiso VARCHAR(100),
    fecha_cambio TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE log_tamanio_bd (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    tamanio_mb DECIMAL(10,2) NOT NULL,
    tablas_principales TEXT
) ENGINE=InnoDB;

CREATE TABLE alertas (
    id_alerta INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NULL,
    tipo_alerta VARCHAR(50) NOT NULL,
    mensaje TEXT,
    stock_actual INT NULL,
    resuelta BOOLEAN DEFAULT FALSE,
    fecha_alerta TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE ventas_archivadas (
    id_archivo INT AUTO_INCREMENT PRIMARY KEY,
    id_venta_original INT NOT NULL,
    fecha_venta TIMESTAMP NOT NULL,
    total DECIMAL(12,2) NOT NULL,
    id_cliente INT NOT NULL,
    fecha_archivo TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    motivo VARCHAR(255),
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE reporte_ventas_semanales (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    semana_inicio DATE NOT NULL,
    semana_fin DATE NOT NULL,
    total_ventas DECIMAL(12,2) NOT NULL,
    cantidad_ventas INT NOT NULL,
    productos_vendidos INT NOT NULL,
    fecha_generacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE resumen_ventas_diario (
    id_resumen INT AUTO_INCREMENT PRIMARY KEY,
    fecha DATE NOT NULL UNIQUE,
    total_ventas DECIMAL(12,2) NOT NULL,
    cantidad_ventas INT NOT NULL,
    clientes_unicos INT NOT NULL
) ENGINE=InnoDB;

CREATE TABLE carritos_abandonados (
    id_carrito INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    id_producto INT NOT NULL,
    cantidad INT NOT NULL,
    fecha_abandono TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente) ON DELETE CASCADE,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE kpis_mensuales (
    id_kpi INT AUTO_INCREMENT PRIMARY KEY,
    mes INT NOT NULL,
    anio INT NOT NULL,
    total_ventas DECIMAL(12,2) NOT NULL,
    nuevos_clientes INT NOT NULL,
    productos_vendidos INT NOT NULL,
    ticket_promedio DECIMAL(10,2) NOT NULL,
    fecha_calculo TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mes_anio (mes, anio)
) ENGINE=InnoDB;

CREATE TABLE productos_ranking (
    id_ranking INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    posicion INT NOT NULL,
    ventas_totales DECIMAL(12,2) NOT NULL,
    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE proveedor_rendimiento (
    id_rendimiento INT AUTO_INCREMENT PRIMARY KEY,
    id_proveedor INT NOT NULL,
    ventas_totales DECIMAL(12,2) NOT NULL,
    productos_activos INT NOT NULL,
    periodo VARCHAR(50) NOT NULL,
    fecha_calculo TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE promociones (
    id_promocion INT AUTO_INCREMENT PRIMARY KEY,
    codigo VARCHAR(50) NOT NULL UNIQUE,
    descuento_porcentaje DECIMAL(5,2) NOT NULL CHECK (descuento_porcentaje > 0 AND descuento_porcentaje <= 100),
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    activa BOOLEAN DEFAULT TRUE
) ENGINE=InnoDB;

CREATE TABLE reseñas (
    id_reseña INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    id_cliente INT NOT NULL,
    calificacion INT NOT NULL CHECK (calificacion >= 1 AND calificacion <= 5),
    comentario TEXT,
    fecha_reseña TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE CASCADE,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente) ON DELETE CASCADE,
    UNIQUE KEY uq_producto_cliente (id_producto, id_cliente)
) ENGINE=InnoDB;

CREATE TABLE programa_referidos (
    id_referido INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente_referente INT NOT NULL,
    id_cliente_referido INT NOT NULL,
    codigo VARCHAR(20) NOT NULL,
    fecha_referido TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_cliente_referente) REFERENCES clientes(id_cliente) ON DELETE CASCADE,
    FOREIGN KEY (id_cliente_referido) REFERENCES clientes(id_cliente) ON DELETE CASCADE,
    CHECK (id_cliente_referente != id_cliente_referido)
) ENGINE=InnoDB;

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

-- ----------------------------------------------------
-- Carga de datos iniciales realistas
-- ----------------------------------------------------

INSERT INTO sucursales (nombre, direccion, ciudad) VALUES
('Sucursal Central Zona 10', '6a Avenida 12-45, Zona 10', 'Ciudad de Guatemala'),
('Sucursal Norte Zona 18', 'Calzada La Paz 25-30, Zona 18', 'Ciudad de Guatemala'),
('Sucursal Sur Villa Nueva', '5a Avenida 4-55, Zona 1', 'Villa Nueva');

INSERT INTO categorias (nombre, descripcion, total_productos) VALUES
('Electrónica', 'Celulares, cómputo, audio y accesorios de consumo', 4),
('Ropa', 'Prendas de vestir, calzado y confección casual', 3),
('Hogar', 'Mobiliario, iluminación y artículos de cocina', 3),
('Deportes', 'Equipamiento, fitness y actividades al aire libre', 3),
('Libros', 'Literatura clásica, técnica y material de estudio', 1),
('Juguetes', 'Juegos de mesa, didácticos y entretenimiento infantil', 2),
('Beauty', 'Cosméticos, cuidado dermatológico y perfumería', 2),
('Alimentos', 'Café gourmet, conservas y repostería artesanal', 2);

INSERT INTO proveedores (nombre, email_contacto, telefono_contacto) VALUES
('TecnoGuate Distribuciones', 'ventas@tecnoguate.com', '+502 2234-5678'),
('Moda Chapina S.A.', 'contacto@modachapina.com', '+502 2298-7654'),
('Hogar GT Import', 'ventas@hogargt.com', '+502 2412-3456'),
('Deportes Guatemala', 'pedidos@deportesgt.com', '+502 2365-7890'),
('Editorial Iberoamericana', 'ventas@editorialibero.com', '+502 2256-1234'),
('Juguetes del Sur', 'distribucion@juguetessur.com', '+502 2478-9012'),
('DermoSalud y Belleza', 'contacto@dermal.com', '+502 2389-4567'),
('Agroindustrias La Cosecha', 'pedidos@lacosecha.com', '+502 2460-1234');

INSERT INTO productos (nombre, descripcion, precio, costo, stock, stock_minimo, sku, peso, vistas, activo, id_categoria, id_proveedor) VALUES
('Samsung Galaxy A55 128GB', 'Smartphone pantalla Super AMOLED 6.6 pulgadas, cámara 50MP, batería 5000mAh', 3199.99, 2450.00, 40, 10, 'SAM-A55-001', 0.21, 420, TRUE, 1, 1),
('Laptop Lenovo IdeaPad 3 15.6"', 'Procesador Intel Core i5 12va gen, 8GB RAM, 512GB SSD NVMe', 5499.99, 4200.00, 25, 5, 'LEN-IP3-002', 1.80, 580, TRUE, 1, 1),
('Audífonos Bluetooth JBL Wave Beam', 'True wireless con cancelación pasiva, micrófono integrado y estuche de carga', 449.99, 280.00, 75, 15, 'JBL-BT-003', 0.18, 310, TRUE, 1, 1),
('Camiseta Casual Algodón Orgánico', 'Prenda básica 100% algodón hilado en anillo, corte unisex', 129.99, 65.00, 120, 20, 'CAM-GT-004', 0.20, 190, TRUE, 2, 2),
('Jeans Slim Fit Denim Stretch', 'Pantalón mezclilla índigo clásico con elastano para ajuste flexible', 299.99, 165.00, 70, 15, 'JEA-SF-005', 0.55, 230, TRUE, 2, 2),
('Lámpara LED Articulada de Escritorio', 'Iluminación regulable 3 tonos cálido/frío, puerto USB de carga', 189.99, 105.00, 50, 10, 'LAM-LED-006', 1.10, 140, TRUE, 3, 3),
('Set de Herramientas Mecánicas 50 Pzas', 'Maletín con llaves combinadas, dados milimétricos y destornilladores cromo-vanadio', 399.99, 245.00, 35, 8, 'HER-50-007', 3.20, 115, TRUE, 3, 3),
('Bicicleta MTB Rodada 29"', 'Cuadro de aluminio, frenos de disco hidráulicos y transmisión Shimano 21 vel', 3499.99, 2450.00, 12, 4, 'BIC-MTB-008', 14.50, 490, TRUE, 4, 4),
('Balón de Fútbol Profesional N5', 'Termosellado de poliuretano texturizado, aprobado para alta competencia', 199.99, 110.00, 95, 20, 'BAL-FUT-009', 0.44, 210, TRUE, 4, 4),
('Antología Cuentos y Leyendas de Centroamérica', 'Edición ilustrada de literatura tradicional y crónica popular', 99.99, 55.00, 80, 15, 'LIB-GT-010', 0.38, 85, TRUE, 5, 5),
('LEGO City Estación de Bomberos', 'Kit de armado modular con camión autobomba, helicóptero y 5 figuras', 399.99, 250.00, 45, 10, 'LEG-CITY-011', 1.05, 340, TRUE, 6, 6),
('Peluche Antialérgico Oso 30cm', 'Relleno de fibra siliconada hipoalergénica lavable', 149.99, 75.00, 68, 12, 'PEL-OSI-012', 0.40, 160, TRUE, 6, 6),
('Crema Hidratante Cerámidas 250ml', 'Tratamiento facial reparador de barrera cutánea con ácido hialurónico', 189.99, 95.00, 58, 10, 'CRE-FAC-013', 0.30, 275, TRUE, 7, 7),
('Sérum Facial Vitamina C 15%', 'Fórmula antioxidante antimanchas con ácido ferúlico activo', 249.99, 135.00, 48, 10, 'SER-HIA-014', 0.12, 395, TRUE, 7, 7),
('Café de Altura Tostado en Grano 1kg', 'Varietal Bourbon lavado cosechado sobre los 1600 msnm', 125.00, 75.00, 96, 20, 'CAF-ANT-015', 1.02, 330, TRUE, 8, 8),
('Chocolate Amargo 75% Cacao 100g', 'Tableta artesanal con nibs tostados sin lecitina de soya añadida', 39.99, 22.00, 178, 30, 'CHO-GT-016', 0.11, 410, TRUE, 8, 8),
('Apple iPad Pro 11" M2 128GB', 'Pantalla Liquid Retina ProMotion 120Hz con chip Apple M2 octa-core', 8999.99, 6900.00, 14, 3, 'IPD-PRO-017', 0.47, 890, TRUE, 1, 1),
('Chaqueta Térmica Impermeable', 'Membrana cortavientos respirable con costuras selladas para montaña', 499.99, 275.00, 45, 10, 'CHA-IMP-018', 0.82, 175, TRUE, 2, 2),
('Sofá Escandinavo 3 Plazas Gris', 'Estructura en madera sólida de pino con tapicería repelente a líquidos', 4299.99, 2900.00, 8, 2, 'SOF-3P-019', 42.00, 520, TRUE, 3, 3),
('Zapatillas Running Amortiguación Dual', 'Suela de espuma reactiva con malla superior transpirable sin costuras', 599.99, 340.00, 65, 15, 'ZAP-RUN-020', 0.68, 380, TRUE, 4, 4);

INSERT INTO clientes (nombre, apellido, email, contraseña, direccion_envio, ciudad, fecha_nacimiento, fecha_registro, total_gastado, fecha_ultima_compra, id_sucursal, activo) VALUES
('Carlos', 'Morales', 'carlos.morales@email.com', '$2y$10$e8Tj4pYQ1mE2fJ.bC6H/duY0eP5bkWsBf3q2yG7mN9e1r8tK5l3qa', '6a Calle Poniente No. 14, Antigua Guatemala', 'Antigua Guatemala', '1990-03-15', '2023-01-10 09:30:00', 3299.98, '2024-02-15 12:30:00', 1, TRUE),
('María', 'López', 'maria.lopez@email.com', '$2y$10$k1J8mQ4yR7sU9vW2xZ3e4uY0eP5bkWsBf3q2yG7mN9e1r8tK5l3qa', 'Colonia Kennedy, 8a Avenida 14-22, Zona 18', 'Ciudad de Guatemala', '1994-07-22', '2023-02-14 11:15:00', 849.98, '2024-02-18 16:00:00', 2, TRUE),
('José', 'Hernández', 'jose.hernandez@email.com', '$2y$10$v2K9nT5zS8tV0wX3yA4f5vZ1fQ6clXtCg4r3zH8nO0f2s9uL6m4rb', '1a Calle 3-40, Barrio San Antonio, Zona 1', 'Villa Nueva', '1988-11-30', '2023-03-01 16:45:00', 5689.98, '2024-02-20 11:45:00', 3, TRUE),
('Ana', 'Martínez', 'ana.martinez@email.com', '$2y$10$w3L0oU6aT9uW1xY4zB5g6wA2gR7dmYuDh5s4aI9oP1g3t0vM7n5sc', 'Boulevard Principal 15-20, San Cristóbal, Zona 8', 'Mixco', '1996-05-18', '2023-04-12 10:00:00', 549.98, '2024-02-25 14:15:00', 1, TRUE),
('Pedro', 'Gómez', 'pedro.gomez@email.com', '$2y$10$x4M1pV7bU0vX2yZ5aC6h7xB3hS8enZvEi6t5bJ0pQ2h4u1wN8o6td', 'Avenida Las Américas 18-90, Zona 13', 'Ciudad de Guatemala', '1985-09-10', '2023-05-20 14:20:00', 314.99, '2024-03-01 10:00:00', 2, TRUE),
('Laura', 'Castillo', 'laura.castillo@email.com', '$2y$10$y5N2qW8cV1wY3zA6bD7i8yC4iT9foAwFj7u6cK1qR3i5v2xO9p7ue', 'Condominio San Marino Lote 14, San Lucas Sacatepéquez', 'San Lucas', '1999-01-25', '2023-06-08 17:05:00', 3879.97, '2024-03-05 15:30:00', 3, TRUE),
('Miguel', 'Ramírez', 'miguel.ramirez@email.com', '$2y$10$z6O3rX9dW2xZ4aB7cE8j9zD5jU0gpBxFk8v7dL2rS4j6w3yP0q8vf', 'Calzada Aguilar Batres 34-10, Zona 12', 'Ciudad de Guatemala', '1992-12-05', '2023-07-15 08:50:00', 779.97, '2024-03-10 11:00:00', 1, TRUE),
('Sofía', 'Díaz', 'sofia.diaz@email.com', '$2y$10$a7P4sY0eX3yA5bC8dF9k0aE6kV1hqCyGl9w8eM3sT5k7x4zQ1r9wg', 'Calle Real 9-45, Jocotenango', 'Jocotenango', '1997-08-14', '2023-08-22 13:30:00', 629.97, '2024-03-15 14:20:00', 2, TRUE),
('Diego', 'Ruiz', 'diego.ruiz@email.com', '$2y$10$b8Q5tZ1fY4zB6cD9eG0l1bF7lW2irDzHm0x9fN4tU6l8y5aR2s0xh', 'Residenciales Los Encinos Manzana C Casa 8', 'Villa Nueva', '1993-04-02', '2023-09-05 15:10:00', 199.99, '2024-02-05 14:40:00', 3, TRUE),
('Isabel', 'Morales', 'isabel.morales@email.com', '$2y$10$c9R6uA2gZ5aC7dE0fH1m2cG8mX3jsEaIn1y0gO5uV7m9z6bS3t1yi', '15 Avenida 4-30, Vista Hermosa I, Zona 15', 'Ciudad de Guatemala', '2001-06-28', '2023-10-18 12:40:00', 0.00, NULL, 1, TRUE),
('Fernando', 'Soto', 'fernando.soto@email.com', '$2y$10$d0S7vB3hA6bD8eF1gI2n3dH9nY4ktFbJo2z1hP6vW8n0a7cT4u2zj', '10a Calle 5-20, Zona 14', 'Ciudad de Guatemala', '1987-02-11', '2023-11-02 09:10:00', 0.00, NULL, 1, TRUE),
('Gabriela', 'Paz', 'gabriela.paz@email.com', '$2y$10$e1T8wC4iB7cE9fG2hJ3o4eI0oZ5luGcKp3a2iQ7wX9o1b8dU5v3ak', 'Sector 3 Lote 45, Pinares de San Cristóbal', 'Mixco', '1995-10-19', '2023-12-01 18:25:00', 0.00, NULL, 3, TRUE);

INSERT INTO ventas (id_venta, fecha_venta, estado, total, id_cliente, id_sucursal) VALUES
(1,  '2024-01-15 10:30:00', 'Entregado', 3199.99, 1, 1),
(2,  '2024-01-16 14:20:00', 'Entregado', 449.99,  2, 2),
(3,  '2024-01-18 09:15:00', 'Entregado', 5499.99, 3, 3),
(4,  '2024-01-20 16:45:00', 'Entregado', 299.99,  4, 1),
(5,  '2024-01-22 11:30:00', 'Entregado', 189.99,  5, 2),
(6,  '2024-01-25 13:10:00', 'Procesando', 3499.99, 6, 3),
(7,  '2024-01-28 15:00:00', 'Pendiente de Pago', 399.99, 7, 1),
(8,  '2024-02-01 10:20:00', 'Entregado', 129.99,  8, 2),
(9,  '2024-02-05 14:40:00', 'Enviado',   199.99,  9, 3),
(10, '2024-02-10 09:50:00', 'Cancelado', 8999.99, 10, 1),
(11, '2024-02-15 12:30:00', 'Entregado', 99.99,   1, 1),
(12, '2024-02-18 16:00:00', 'Entregado', 399.99,  2, 2),
(13, '2024-02-20 11:45:00', 'Procesando', 189.99, 3, 3),
(14, '2024-02-25 14:15:00', 'Entregado', 249.99,  4, 1),
(15, '2024-03-01 10:00:00', 'Pendiente de Pago', 125.00, 5, 2),
(16, '2024-03-05 15:30:00', 'Entregado', 379.98,  6, 3),
(17, '2024-03-10 11:00:00', 'Entregado', 379.98,  7, 1),
(18, '2024-03-15 14:20:00', 'Enviado',   499.98,  8, 2);

INSERT INTO detalle_ventas (cantidad, precio_unitario_congelado, id_venta, id_producto) VALUES
(1, 3199.99, 1, 1),
(1, 449.99,  2, 3),
(1, 5499.99, 3, 2),
(1, 299.99,  4, 5),
(1, 189.99,  5, 6),
(1, 3499.99, 6, 8),
(1, 399.99,  7, 7),
(1, 129.99,  8, 4),
(1, 199.99,  9, 9),
(1, 8999.99, 10, 17),
(1, 99.99,   11, 10),
(1, 399.99,  12, 11),
(1, 189.99,  13, 13),
(1, 249.99,  14, 14),
(1, 125.00,  15, 15),
(2, 189.99,  16, 13),
(2, 189.99,  17, 6),
(2, 249.99,  18, 14);

INSERT INTO promociones (codigo, descuento_porcentaje, fecha_inicio, fecha_fin, activa) VALUES
('INDEPENDENCIA15', 15.00, '2024-09-01', '2024-09-30', TRUE),
('VERANO2024',      20.00, '2024-06-01', '2024-08-31', FALSE),
('BLACKFRIDAY25',   25.00, '2024-11-25', '2024-11-30', FALSE),
('NAVIDAD10',       10.00, '2024-12-01', '2024-12-25', FALSE);

INSERT INTO reseñas (id_producto, id_cliente, calificacion, comentario) VALUES
(1,  1, 5, 'Excelente pantalla y respuesta de la batería. Satisfecho con la relación calidad-precio.'),
(2,  3, 4, 'Buena potencia para trabajo en desarrollo y oficina. El ventilador enciende bajo carga pesada.'),
(3,  2, 4, 'Emparejamiento inmediato y cancelación adecuada para uso urbano en transporte.'),
(4,  8, 5, 'Tejido suave al tacto y no encoge con los lavados. Corte estándar cómodo.'),
(5,  4, 4, 'Mezclilla flexible y costuras bien rematadas. Ajuste fiel a la talla habitual.'),
(8,  6, 5, 'Rendimiento sólido en terracería media. Frenos hidráulicos responden sin retardo.'),
(10, 1, 5, 'Buena compilación de crónicas orales centroamericanas con notas explicativas.'),
(13, 4, 5, 'Textura ligera sin residuo oleoso. Buena tolerancia en piel sensible.');

INSERT INTO carritos_abandonados (id_cliente, id_producto, cantidad, fecha_abandono) VALUES
(10, 17, 1, '2024-02-09 22:15:00'),
(11, 2,  1, '2024-03-12 18:30:00'),
(12, 8,  1, '2024-03-14 11:20:00');

INSERT INTO programa_referidos (id_cliente_referente, id_cliente_referido, codigo) VALUES
(1, 2, 'REF-CMORALES-01'),
(3, 6, 'REF-JHERNAN-03'),
(4, 8, 'REF-AMARTIN-04');
