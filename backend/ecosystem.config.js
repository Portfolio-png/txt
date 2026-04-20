module.exports = {
  apps: [
    {
      name: 'paper-backend',
      script: 'server.js',
      cwd: '/home/ubuntu/txt/backend',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '300M',
      env: {
        NODE_ENV: 'production',
        PORT: 18080,
        DB_PATH: '/home/ubuntu/txt/backend/data/paper.db',
      },
    },
  ],
};
