const path = require('path');

module.exports = {
  apps: [
    {
      name: 'paper-backend',
      script: 'server.js',
      cwd: __dirname,
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '300M',

      // Keep secrets out of git:
      // - Create a `.env` file next to this file on the server.
      // - PM2 will load it when starting this app.
      env_file: path.join(__dirname, '.env'),

      // Safe defaults. `.env` can override any of these.
      env: {
        NODE_ENV: 'production',
        PORT: 18080,
        DB_PATH: path.join(__dirname, 'data', 'paper.db'),
      },
    },
  ],
};
