# Proyecto de Base de Datos - E-commerce

Este es mi proyecto final de Bases de Datos Avanzadas. Es una base de datos completa para un e-commerce que gestiona productos, clientes, ventas, inventario y seguridad. La verdad es que fue un proyecto bastante challenging pero aprendí un montón.

## Integrantes
- Abdiel Morales

---

## 🚀 Cómo Ejecutar el Proyecto

Para que todo funcione bien, necesitas ejecutar los archivos en este orden exacto (si no, te van a dar errores de dependencias):

1. **01_Esquema_y_Datos.sql**
   - Crea la base de datos `ecommerce_db`
   - Crea todas las tablas (6 principales + 16 auxiliares)
   - Carga datos de prueba realistas
   - ⚠️ *Lo más difícil aquí fue entender bien las relaciones FOREIGN KEY*

2. **02_Consultas_Avanzadas.sql**
   - 20 consultas analíticas para análisis de negocio
   - Incluye análisis RFM, cohortes, productos más vendidos, etc.
   - *NTILE y las CTEs me costaron un poco entenderlas al principio*

3. **03_Funciones.sql**
   - 20 funciones reutilizables (validación de email, cálculo de IVA, etc.)
   - Usa REGEXP para validaciones complejas
   - *Aprender REGEXP fue interesante pero complicado*

4. **04_Seguridad.sql**
   - 7 roles de usuario (RBAC)
   - Usuarios de prueba para cada rol
   - Vistas de seguridad para ocultar datos sensibles
   - *El concepto de RBAC lo entendí bien pero implementarlo fue todo un reto*

5. **05_Triggers.sql**
   - 20 triggers para automatización y auditoría
   - Control de stock, logs de cambios, validaciones
   - *La diferencia entre BEFORE y AFTER me confundió varias veces*

6. **06_Eventos.sql**
   - 20 eventos programados (tareas automáticas)
   - Reportes diarios, limpieza de datos, actualizaciones
   - *El event_scheduler tuvo que estar activado, eso me dio dolores de cabeza*

7. **07_Procedimientos_Almacenados.sql**
   - 20 procedimientos con transacciones ACID
   - Manejo de errores con ROLLBACK automático
   - *Las transacciones y el control de errores fueron lo más técnico del proyecto*

---

## 📋 Requisitos Previos

- **MySQL 8.0+** (necesario para roles nativos, CTEs, y otras funciones nuevas)
- **InnoDB** (usado en todas las tablas para transacciones y claves foráneas)
- **Permisos de administrador** (necesario para CREATE USER, GRANT, EVENT)
- **Event Scheduler activado** (incluido en el script 06, pero verifica que esté ON)

---

## 🎯 Lo Más Importante del Proyecto

### Tabla Puente `detalle_ventas`
Este fue uno de los conceptos más importantes que aprendí. Como una venta puede tener muchos productos y un producto puede estar en muchas ventas, necesité una tabla intermedia. Lo más crucial es el campo `precio_unitario_congelado` - cuando un cliente compra, guardo el precio de ese momento. Si mañana cambio el precio del producto, las ventas históricas no se modifican. Esto es vital para la contabilidad.

### Por qué InnoDB y no MyISAM
Al principio no entendía bien la diferencia, pero aprendí que InnoDB es necesario porque:
- Soporta transacciones ACID (si algo falla, todo se deshace)
- Tiene claves foráneas (garantiza que no tenga ventas con clientes que no existen)
- Bloqueo a nivel de fila (dos personas no pueden comprar el mismo producto al mismo tiempo y causar sobreventa)

### Seguridad con Roles (RBAC)
Implementé 7 roles diferentes:
- `Administrador_Sistema`: acceso total
- `Gerente_Marketing`: análisis de datos y campañas
- `Analista_Datos`: solo lectura, con límite de consultas por hora
- `Empleado_Inventario`: puede modificar stock pero NO precios
- `Atencion_Cliente`: solo ve información básica de clientes (sin contraseñas)
- `Auditor_Financiero`: acceso a datos financieros
- `Visitante`: acceso mínimo de lectura

El principio aquí es "menor privilegio" - cada rol solo tiene acceso a lo que realmente necesita.

### Triggers BEFORE vs AFTER
Esto me costó un poco:
- **BEFORE**: Se ejecuta ANTES de que el cambio se guarde. Útil para validaciones (ej. verificar stock antes de vender).
- **AFTER**: Se ejecuta DESPUÉS de que el cambio se guarde. Útil para auditoría (ej. registrar el cambio de precio en un log).

### Transacciones ACID
En los procedimientos críticos (como procesar una venta), uso transacciones:
```sql
START TRANSACTION;
-- varias operaciones
COMMIT; -- si todo sale bien
-- o ROLLBACK; -- si algo falla, todo se deshace
```

Esto garantiza que si algo falla a la mitad, no quedan datos inconsistentes.

---

## 📚 Qué Aprendí

### Conceptos Técnicos
- **Normalización 3NF**: Cómo organizar datos para evitar redundancia
- **CTEs (Common Table Expressions)**: Hacen las consultas más legibles
- **Window Functions** (NTILE, ROW_NUMBER): Para análisis avanzados
- **REGEXP**: Validaciones complejas con expresiones regulares
- **JSON en MySQL**: Para pasar estructuras de datos complejas
- **Vistas materializadas simuladas**: MySQL no las tiene nativas, las simulé con tablas físicas

### Lo Más Difícil
1. **Análisis RFM con NTILE**: Dividir clientes en cuartiles por recencia, frecuencia y monetario fue técnicamente complejo.
2. **Manejo de errores en procedimientos**: Entender DECLARE EXIT HANDLER y cuándo usar ROLLBACK.
3. **Programación de eventos**: Calcular fechas exactas para ejecuciones recurrentes.
4. **Auto-referencia en triggers**: Evitar que un trigger dispare otro trigger infinitamente.

### Lo Más Satisfactorio
1. **Ver que los triggers funcionan**: Cuando cambié un precio y se registró automáticamente en el log.
2. **Las transacciones**: Cuando simulé un error en medio de una venta y todo se deshizo perfectamente.
3. **El análisis de cohort**: Ver cómo los clientes se retienen mes a mes fue muy interesante.

---

## 🗂️ Archivos del Proyecto

**Archivos principales (7 archivos SQL):**
- `01_Esquema_y_Datos.sql` - Esquema y datos
- `02_Consultas_Avanzadas.sql` - 20 consultas analíticas
- `03_Funciones.sql` - 20 funciones
- `04_Seguridad.sql` - 7 roles + usuarios
- `05_Triggers.sql` - 20 triggers
- `06_Eventos.sql` - 20 eventos
- `07_Procedimientos_Almacenados.sql` - 20 procedimientos

**Archivos adicionales:**
- `Diagrama_ER.drawio` - Diagrama entidad-relación (abrir en diagrams.net)
- `GUIA_ESTUDIO_COMPLETA.md` - Guía explicativa de TODO el proyecto
- `README.md` - Este archivo

---

## 💡 Tips para Quien Quiera Estudiar Este Proyecto

1. **Lee los archivos en orden**: Empieza con el esquema, luego las consultas, etc.
2. **Ejecuta cada archivo en MySQL**: No solo leas, practica realmente.
3. **Modifica las consultas**: Cambia parámetros y observa los resultados.
4. **Prueba los triggers manualmente**: Haz un UPDATE y mira el log.
5. **Usa la guía de estudio**: `GUIA_ESTUDIO_COMPLETA.md` explica absolutamente todo.

---

## 🎓 Para la Defensa

Si el profesor te pregunta:

**¿Por qué la tabla puente?**
- Porque es una relación muchos a muchos. Una venta tiene muchos productos, un producto está en muchas ventas. Sin esta tabla, tendría que duplicar información o sería muy difícil de consultar.

**¿Por qué precio congelado?**
- Por integridad contable. Si hoy vendo un iPhone a Q1000 y mañana cambio el precio a Q900, mi reporte de ventas de ayer sigue siendo correcto con Q1000. No quiero que los reportes históricos cambien.

**¿Por qué InnoDB?**
- Por transacciones y claves foráneas. MyISAM no soporta transacciones, si algo falla a la mitad, no puedo deshacer los cambios.

**¿Qué es ACID?**
- Atomicidad, Consistencia, Aislamiento, Durabilidad. Garantiza que las transacciones son confiables.

**¿Para qué sirven los triggers?**
- Para automatizar reglas de negocio y auditoría. En lugar de escribir código en la aplicación, las reglas viven en la base de datos.

---

## ⚠️ Errores Comunes que Encontré

1. **Orden de ejecución incorrecto**: Si ejecutas los archivos fuera de orden, tendrás errores de dependencias.
2. **Event Scheduler desactivado**: Los eventos no se ejecutan si no activas el scheduler.
3. **JSON mal formateado**: En el procedimiento de venta, el JSON debe tener comillas dobles, no simples.
4. **Permisos insuficientes**: Necesitas permisos de administrador para crear roles y usuarios.

---

## 🏆 Calificación Personal

Este proyecto me enseñó mucho más de lo que esperaba. Al principio me pareció abrumador con tantos requisitos (20 de cada cosa), pero al final entendí que cada elemento tiene su propósito. Los triggers, eventos y procedimientos hacen que la base de datos sea mucho más inteligente y segura que si solo tuviera tablas y consultas simples.

Si tuviera que hacerlo de nuevo, probablemente simplificaría algunos triggers que hacen cosas similares, pero en general estoy satisfecho con el resultado. Creo que demuestra comprensión profunda de conceptos avanzados de bases de datos.

---

**¡Espero que este proyecto sea útil para aprender MySQL avanzado!** 🎓