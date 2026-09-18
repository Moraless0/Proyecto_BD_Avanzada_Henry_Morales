# Proyecto de Base de Datos para E-commerce

Este proyecto es una base de datos completa para un sistema de comercio electrónico que gestiona productos, clientes, ventas, inventario y seguridad. Fue desarrollado como proyecto final de Bases de Datos Avanzadas para practicar desde el diseño del esquema hasta consultas complejas, funciones, triggers, eventos y procedimientos almacenados.

## Descripción del Proyecto

La idea principal fue crear una base de datos que simule el funcionamiento de una tienda en línea real. No es solo almacenar datos, sino implementar lógica de negocio directamente en MySQL: validaciones automáticas, auditoría de cambios, tareas programadas y seguridad por roles.

El proyecto incluye 7 archivos SQL que deben ejecutarse en orden específico, ya que cada uno depende del anterior.


## Estructura del Proyecto

Los archivos están organizados en el siguiente orden de ejecución:

1. **01_Esquema_y_Datos.sql** - Crea la base de datos, todas las tablas y carga datos de prueba
2. **02_Consultas_Avanzadas.sql** - 20 consultas para análisis de negocio
3. **03_Funciones.sql** - 20 funciones reutilizables para lógica de negocio
4. **04_Seguridad.sql** - Roles, usuarios y permisos basados en RBAC
5. **05_Triggers.sql** - 20 triggers para automatización y auditoría
6. **06_Eventos.sql** - 20 eventos programados para tareas automáticas
7. **07_Procedimientos_Almacenados.sql** - 20 procedimientos con transacciones

## Qué Contiene Cada Archivo

### 01_Esquema_y_Datos.sql

Este archivo es la base del proyecto. Contiene:

- **7 tablas principales**: categorías, proveedores, sucursales, productos, clientes, ventas y detalle_ventas
- **16 tablas auxiliares**: para auditoría, alertas, reportes y módulos adicionales
- **Datos de prueba**: 20 productos, 12 clientes, 18 ventas, 8 categorías, 8 proveedores

Lo más importante de este archivo es la tabla puente `detalle_ventas`. Como una venta puede tener muchos productos y un producto puede estar en muchas ventas, necesitamos una tabla intermedia. El campo clave es `precio_unitario_congelado` que guarda el precio al momento de la compra para mantener la integridad contable histórica.

### 02_Consultas_Avanzadas.sql

Son 20 consultas para análisis de negocio. Algunas de las más importantes:

- Top 10 productos más vendidos por facturación
- Productos con bajas ventas (usando PERCENT_RANK)
- Clientes VIP según su gasto histórico (LTV)
- Ventas mensuales con ticket promedio
- Crecimiento de clientes por trimestre
- Tasa de compra repetida
- Productos comprados juntos (análisis de canasta)
- Rotación de inventario por categoría
- Segmentación de clientes RFM (Recencia, Frecuencia, Monetario)
- Predicción simple de demanda

Las consultas usan CTEs (Common Table Expressions) y window functions como NTILE, PERCENT_RANK y ROW_NUMBER para análisis avanzados.

### 03_Funciones.sql

Son 20 funciones que encapsulan lógica reutilizable:

- `fn_CalcularTotalVenta` - Calcula el total de una venta sumando sus detalles
- `fn_VerificarDisponibilidadStock` - Valida si hay suficiente stock
- `fn_ObtenerPrecioProducto` - Retorna el precio vigente de un producto
- `fn_CalcularEdadCliente` - Calcula edad a partir de fecha de nacimiento
- `fn_FormatearNombreCompleto` - Formatea nombre y apellido
- `fn_EsClienteNuevo` - Determina si el cliente compró en los últimos 30 días
- `fn_CalcularCostoEnvio` - Calcula costo de envío basado en peso
- `fn_AplicarDescuento` - Aplica descuento porcentual
- `fn_ValidarFormatoEmail` - Valida formato de email con REGEXP
- `fn_ContarVentasCliente` - Cuenta ventas efectivas de un cliente
- `fn_DeterminarEstadoLealtad` - Segmenta cliente en Oro/Plata/Bronce
- `fn_GenerarSKU` - Genera SKU automáticamente
- `fn_CalcularIVA` - Calcula IVA (12%)
- `fn_ObtenerStockTotalPorCategoria` - Suma stock por categoría
- `fn_EstimarFechaEntrega` - Estima fecha según ciudad
- `fn_ConvertirMoneda` - Conversión con tasa de cambio
- `fn_ValidarComplejidadContraseña` - Valida fortaleza de contraseña

Las funciones usan expresiones regulares (REGEXP) para validaciones complejas.

### 04_Seguridad.sql

Implementa seguridad basada en roles (RBAC) con 7 roles:

- **Administrador_Sistema** - Acceso total a la base de datos
- **Gerente_Marketing** - Lectura de ventas, clientes y campañas
- **Analista_Datos** - Solo lectura con límite de consultas por hora
- **Empleado_Inventario** - Puede modificar stock pero NO precios
- **Atencion_Cliente** - Ve información básica de clientes (sin contraseñas)
- **Auditor_Financiero** - Acceso a datos financieros y logs
- **Visitante** - Acceso mínimo de lectura

También crea 5 usuarios de prueba y asigna roles. Incluye vistas de seguridad para ocultar información sensible como contraseñas y direcciones exactas.

### 05_Triggers.sql

Son 20 triggers que automatizan reglas de negocio y auditoría:

- **Auditoría de precios** - Registra cambios de precio en log_cambios_precio
- **Validación de stock** - Impide vender si no hay suficiente inventario
- **Actualización automática de stock** - Descuenta inventario al vender
- **Protección de categorías** - Impide borrar categorías con productos
- **Log de nuevos clientes** - Registra altas de clientes
- **Actualización de LTV** - Actualiza gasto total del cliente al vender
- **Prevención de stock negativo** - Doble barrera de seguridad
- **Capitalización de nombres** - Formatea nombres automáticamente
- **Recálculo de totales** - Recalcula total de venta al modificar detalles
- **Log de cambios de estado** - Registra cambios de estado de pedidos
- **Validación de precios** - Impide precios <= 0
- **Alertas de stock bajo** - Genera alertas automáticas
- **Archivado de ventas** - Guarda respaldo antes de borrar ventas
- **Validación de email** - Valida formato al insertar cliente
- **Prevención de auto-referidos** - Impide que un cliente se refiera a sí mismo
- **Asignación de categoría por defecto** - Crea categoría "General" si es NULL
- **Contador de productos por categoría** - Mantiene contador sincronizado

Los triggers usan BEFORE para validaciones y AFTER para auditoría.

### 06_Eventos.sql

Son 20 eventos programados que ejecutan tareas automáticamente:

- **Reporte semanal de ventas** - Genera reporte cada domingo
- **Limpieza de alertas** - Borra alertas resueltas antiguas
- **Archivado de logs** - Purga logs de más de 6 meses
- **Desactivación de promociones** - Desactiva promociones expiradas
- **Recálculo de lealtad** - Actualiza métricas de clientes cada noche
- **Lista de reabastecimiento** - Genera alertas de stock bajo diario
- **Reconstrucción de índices** - Optimiza tablas semanalmente
- **Suspensión de cuentas inactivas** - Desactiva clientes sin actividad
- **Agregación diaria de ventas** - Guarda resumen diario
- **Verificación de consistencia** - Detecta datos inconsistentes
- **Cumpleaños** - Identifica clientes cumpleañeros
- **Ranking de productos** - Actualiza ranking horario
- **Log de tamaño de BD** - Registra tamaño semanalmente
- **Limpieza de carritos** - Purga carritos abandonados
- **Cálculo de KPIs mensuales** - Calcula indicadores mensuales
- **Detección de fraude** - Detecta patrones sospechosos
- **Reporte de proveedores** - Evalúa rendimiento mensual
- **Purga de ventas archivadas** - Borra archivos antiguos

Los eventos usan diferentes frecuencias: horario, diario, semanal, mensual y trimestral.

### 07_Procedimientos_Almacenados.sql

Son 20 procedimientos con transacciones ACID para operaciones complejas:

- **sp_RealizarNuevaVenta** - Procesa venta completa con múltiples productos (usa JSON)
- **sp_AgregarNuevoProducto** - Alta de producto con SKU automático
- **sp_ActualizarDireccionCliente** - Actualiza dirección de cliente
- **sp_ProcesarDevolucion** - Procesa devolución con reintegro de stock
- **sp_ObtenerHistorialComprasCliente** - Historial de órdenes de cliente
- **sp_AjustarNivelStock** - Ajuste manual de inventario con auditoría
- **sp_EliminarClienteDeFormaSegura** - Anonimiza datos (derecho al olvido)
- **sp_AplicarDescuentoPorCategoria** - Aplica descuento a categoría
- **sp_GenerarReporteMensualVentas** - Reporte contable mensual
- **sp_CambiarEstadoPedido** - Cambia estado de pedido
- **sp_RegistrarNuevoCliente** - Registro con validación de email
- **sp_ObtenerDetallesProductoCompleto** - Ficha técnica de producto
- **sp_FusionarCuentasCliente** - Fusiona cuentas duplicadas
- **sp_AsignarProductoAProveedor** - Cambia proveedor de producto
- **sp_BuscarProductos** - Búsqueda avanzada con filtros
- **sp_ObtenerDashboardAdmin** - Métricas en tiempo real
- **sp_ProcesarPago** - Simulación de pasarela de pago
- **sp_AñadirReseñaProducto** - Registro de reseña validando compra
- **sp_ObtenerProductosRelacionados** - Recomendaciones basadas en compras
- **sp_MoverProductosEntreCategorias** - Reclasificación de productos

Los procedimientos críticos usan transacciones con COMMIT/ROLLBACK para garantizar integridad.

## Relaciones Principales

El modelo de datos tiene estas relaciones clave:

- **Categoría → Productos** (1:N) - Una categoría tiene muchos productos
- **Proveedor → Productos** (1:N) - Un proveedor suministra muchos productos
- **Cliente → Ventas** (1:N) - Un cliente hace muchas ventas
- **Sucursal → Ventas** (1:N) - Una sucursal procesa muchas ventas
- **Venta → Detalle de Ventas → Productos** (N:M) - Una venta tiene muchos productos, un producto está en muchas ventas

La relación N:M entre ventas y productos se resuelve con la tabla puente `detalle_ventas`, que incluye el `precio_unitario_congelado` para mantener el histórico contable.

## Cómo Ejecutar el Proyecto

Es muy importante ejecutar los archivos en este orden exacto:

1. `01_Esquema_y_Datos.sql` - Crea todo desde cero
2. `02_Consultas_Avanzadas.sql` - Las consultas necesitan el esquema
3. `03_Funciones.sql` - Las funciones necesitan el esquema
4. `05_Triggers.sql` - Los triggers necesitan el esquema y tablas auxiliares
5. `06_Eventos.sql` - Los eventos necesitan el esquema
6. `07_Procedimientos_Almacenados.sql` - Los procedimientos necesitan funciones y esquema
7. `04_Seguridad.sql` - La seguridad necesita que existan los procedimientos

**Nota importante**: El archivo 04 hace GRANT EXECUTE sobre procedimientos que se crean en 07, por eso debe ejecutarse al final.

## Requisitos Previos

- MySQL 8.0 o superior (necesario para roles nativos, CTEs y funciones de ventana)
- Permisos de administrador (necesario para CREATE USER, GRANT, EVENT)
- Event Scheduler activado (se activa en el archivo 06, pero se puede verificar con `SHOW VARIABLES LIKE 'event_scheduler'`)


## Conclusión

Este proyecto fue un reto considerable pero aprendí mucho más de lo que esperaba. Al principio parecía abrumador con tantos requisitos (20 de cada cosa), pero al final entendí que cada elemento tiene su propósito. Los triggers, eventos y procedimientos hacen que la base de datos sea mucho más inteligente y segura que si solo tuviera tablas y consultas simples.

Mas misericordia a la proxima :'(


## Autor
Henry Morales