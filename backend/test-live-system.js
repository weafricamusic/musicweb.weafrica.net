/* eslint-disable no-console */
// Simple smoke test for the live endpoints (requires the server running locally).

const http = require('http');

console.log('Testing live streaming system setup...\n');

const ports = [3000, 5000, 8000, 8080];

ports.forEach((port) => {
  const req = http.request(
    {
      hostname: 'localhost',
      port,
      path: '/live/active',
      method: 'GET',
      timeout: 2000,
    },
    (res) => {
      console.log(`✅ Server responding on port ${port} - Status: ${res.statusCode}`);
      res.on('data', () => {});
    },
  );

  req.on('error', () => {
    console.log(`❌ No server on port ${port}`);
  });

  req.end();
});

console.log('\nTo start the Nest backend:');
console.log('npm --prefix backend run dev:nest');
console.log('\nThen test:');
console.log('curl http://localhost:3000/live/active');
