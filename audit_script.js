const fs = require('fs');
const content = fs.readFileSync('backend/server.js', 'utf8');
const regex = /app\.(get|post|put|patch|delete)\s*\(\s*['"](\/api\/[^'"]+)['"]/g;
let match;
const routes = [];
while ((match = regex.exec(content)) !== null) {
  routes.push({ method: match[1].toUpperCase(), path: match[2] });
}

const entityMap = {};
for (const route of routes) {
  const parts = route.path.split('/');
  if (parts.length > 2) {
    const entity = parts[2];
    if (!entityMap[entity]) {
      entityMap[entity] = [];
    }
    entityMap[entity].push(`${route.method} ${route.path}`);
  }
}

fs.writeFileSync('audit_results_raw.json', JSON.stringify(entityMap, null, 2));
