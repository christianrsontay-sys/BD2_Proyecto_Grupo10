const express = require('express');

const router = express.Router();

const { estado } = require('../controllers/estado.controller');

router.get('/estado', estado);

module.exports = router;