const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 5500;
const HOST = '0.0.0.0';

const server = http.createServer((req, res) => {
    // Disable caching - force fresh load every time
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '-1');
    res.setHeader('Access-Control-Allow-Origin', '*');
    // Add cache-busting timestamp to prevent browser caching
    res.setHeader('ETag', Date.now().toString());

    const filePath = path.join(__dirname, req.url === '/' ? 'index.html' : req.url);

    fs.readFile(filePath, (err, data) => {
        if (err) {
            res.writeHead(404);
            res.end('Not found');
            return;
        }

        const ext = path.extname(filePath);
        const contentType = {
            '.html': 'text/html',
            '.js': 'application/javascript',
            '.css': 'text/css',
        }[ext] || 'application/octet-stream';

        res.writeHead(200, { 'Content-Type': contentType });
        res.end(data);
    });
});

server.listen(PORT, HOST, () => {
    console.log(`Server running at http://${HOST}:${PORT}/`);
    console.log('No-cache headers enabled - refresh to see latest changes');
});