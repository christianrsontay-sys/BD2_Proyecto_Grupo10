Proyecto Base de Datos de Ventas - Comercializadora del Norte, S.A. Bases de Datos II - Fase 2

Integrantes:
Astrid Gabriela Rivera Vásquez 2450042 
Christian Eduardo Rivas Sontay 2450503 
Josue Daniel Perez Suruy - 2427098   

Tecnología	Versión 
Sistema gestor de base de datos	MySQL 8.4	
Lenguaje de programación de la API	JavaScript	
Entorno de ejecución	Node.js 22.23.5	
Conexión a MySQL	mysql2	
Administrador de procesos	PM2
Servicio de base de datos	Amazon RDS	
Servicio de publicación	Amazon EC2
Puerto de publicación	3000


Preparación de la instancia de base de datos
1. Se creó una instancia de Amazon RDS con el motor MySQL.
2. Se configuró el acceso a la instancia mediante sus reglas de seguridad.
3. Se verificó la conectividad desde MySQL Workbench.
4. Se utilizó la base de datos de la Fase 1 como origen de información.
5. Se creó una base de datos independiente denominada dw_ventas, destinada al almacenamiento dimensional.

Servidor RDS utilizado:  bd2-grupo10.c5ua46c60eqf.us-east-2.rds.amazonaws.com

Se creó la base de datos dw_ventas.
Se crearon las seis dimensiones:
- dim_tiempo
- dim_producto
- dim_cliente
- dim_ubicacion
- dim_vendedor
- dim_metodo_pago

Se creó la tabla de hechos fact_ventas.
Se creó la tabla de control dw_control.
Se implementó el procedimiento almacenado sp_dw_cargar().
Se ejecutó el procedimiento para realizar la carga de información desde la base de datos de la Fase 1.
Se verificó que la carga finalizara correctamente.


Se desarrolló una API REST utilizando JavaScript, Node.js y Express.js.
Se creó una instancia de Amazon EC2.
Se instaló Node.js en el servidor.
Se instaló PM2 para administrar el proceso de la API.
Se descargó el repositorio del proyecto desde GitHub.
Se ingresó a la carpeta FASE 2.
Se instalaron las dependencias del proyecto.
Se configuraron las variables de entorno.
Se inició la API mediante PM2.

Comandos utilizados:
npm install
pm2 start server.js --name bd2-api
pm2 status