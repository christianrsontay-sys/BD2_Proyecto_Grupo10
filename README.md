Proyecto Base de Datos de Ventas - Comercializadora del Norte, S.A.
Bases de Datos II - Fase 1

Integrantes:


1. Archivos del proyecto

00_crear_bd.sql          crea la base de datos
01_modelo.sql            crea las tablas
02_funciones.sql         crea las funciones
03_tablas_tmp.sql        crea la tabla temporal tmp_ventas
04_etl.sql               carga el CSV y pasa los datos a las tablas
05_procedimientos.sql    crea los procedimientos almacenados
06_triggers.sql          crea los triggers y la bitacora
07_pruebas.sql           pruebas de los procedimientos y triggers
08_validacion_etl.sql    revisa que los datos cargados esten completos
09_prueba_rollback.sql   prueba del rollback
ventas.csv               datos a cargar


2. Requisitos

1. MySQL 8.0.16 o superior
2. MySQL Workbench
3. El archivo de ventas (Excel o CSV)


3. Conversion de Excel a CSV

El sistema antiguo exporta las ventas a Excel. Hay que convertir ese archivo a CSV.
Si ya se tiene el ventas.csv, pasar al punto 4.

1. Abrir el archivo de Excel. La primera fila debe tener los nombres de las columnas
   (son 30 columnas, de numero_factura a metodo_pago).
2. Archivo > Guardar como.
3. En "Tipo", elegir CSV UTF-8 (delimitado por comas) (*.csv).
4. Ponerle el nombre ventas.csv y guardar. Si Excel avisa que solo se guarda la hoja
   activa, aceptar.
5. En Excel con configuracion regional en espanol el separador queda como ; (punto y coma),
   que es el que usan los scripts. Para comprobarlo, abrir ventas.csv con el Bloc de notas.
6. Revisar en el Bloc de notas que las fechas se vean como dd/mm/aaaa (por ejemplo 01/01/2022).
7. Cerrar el archivo en Excel antes de cargarlo a la base de datos.


4. Ruta del archivo

El archivo debe guardarse en la carpeta que permite MySQL y la ruta debe estar en 04_etl.sql.

1. En Workbench ejecutar: SELECT @@secure_file_priv;
   El resultado es la carpeta donde debe estar el archivo.
2. Copiar ventas.csv en esa carpeta. En este equipo la ruta es:

   C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/ventas.csv

3. Abrir 04_etl.sql y revisar que el LOAD DATA INFILE tenga esa misma ruta:

   LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/ventas.csv'
   INTO TABLE tmp_ventas
   CHARACTER SET utf8mb4
   FIELDS TERMINATED BY ';' OPTIONALLY ENCLOSED BY '"'
   LINES TERMINATED BY '\r\n'
   IGNORE 1 LINES;

4. Si la carpeta es otra, cambiar la ruta (con / en vez de \).
   Si el archivo usa coma como separador, cambiar ';' por ','.
5. Despues de ejecutar el 04, revisar que se cargo: SELECT COUNT(*) FROM tmp_ventas;
   Con el archivo del proyecto deben ser 20000 filas.


5. Orden de ejecucion

Abrir cada archivo con File > Open SQL Script y ejecutarlo con el rayo (Ctrl + Shift + Enter).
Despues de cada uno revisar el panel Output para ver que no haya errores.

1. 00_crear_bd.sql
2. 01_modelo.sql
3. 02_funciones.sql
4. 03_tablas_tmp.sql
5. 04_etl.sql
6. 05_procedimientos.sql
7. 06_triggers.sql
8. 07_pruebas.sql
9. 08_validacion_etl.sql
10. 09_prueba_rollback.sql

Notas:

1. Los archivos se ejecutan en este orden, uno despues de otro.
2. Antes del 07 y del 09 desmarcar la opcion Query > Stop Script Execution on Errors.
3. El 07 se ejecuta una sola vez. Para repetirlo hay que volver a empezar desde el 00.
