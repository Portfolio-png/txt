const fs = require('fs');
let code = fs.readFileSync('backend/server.js', 'utf8');

const guardCode = `
function guardContract(contract) {
  return (req, res, next) => {
    const alerts = [];
    if (contract && contract.fields) {
      for (const [key, rules] of Object.entries(contract.fields)) {
        if (req.body && req.body[key] !== undefined) {
          const val = req.body[key];
          if (rules.type === 'number' && typeof val !== 'number') {
            alerts.push({ path: 'item.' + key, message: 'Must be a number' });
          }
        }
      }
    }
    if (alerts.length > 0) {
      guardAlerts.push({
        route: req.method + ' ' + req.route.path,
        details: { problems: alerts }
      });
    }
    next();
  };
}
`;

if (!code.includes('function guardContract')) {
  code = code.replace('const guardAlerts = [];', 'const guardAlerts = [];\n' + guardCode);
  fs.writeFileSync('backend/server.js', code);
  console.log('Added guardContract');
} else {
  console.log('guardContract already exists');
}
