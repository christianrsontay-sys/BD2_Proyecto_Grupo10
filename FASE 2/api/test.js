const mysql = require('mysql2/promise');

mysql.createConnection({
  host: 'bd2-grupo10.c5ua46c60eqf.us-east-2.rds.amazonaws.com',
  user: 'admin',
  password: 'Grupo10admin',
  database: 'dw_ventas'
})
.then(() => {
  console.log('Conectado');
  process.exit();
})
.catch(err => {
  console.error('Error:', err);
  process.exit();
});