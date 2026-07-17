const jwt = require('jsonwebtoken');
require('dotenv').config();
const token = jwt.sign({ id: 1, email: 'datta@bhau.com', role: 'admin' }, process.env.JWT_SECRET || 'paper_secret_key', { expiresIn: '1h' });
console.log(token);
