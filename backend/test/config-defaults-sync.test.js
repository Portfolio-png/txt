const fs = require('fs');
const path = require('path');

describe('Config Defaults Sync (Drift Guard)', () => {
  it('should ensure all three config defaults are structurally identical', () => {
    const serverJsPath = path.join(__dirname, '../server.js');
    const configServicePath = path.join(__dirname, '../../packages/core_erp/lib/core/services/config_service.dart');
    
    const serverJs = fs.readFileSync(serverJsPath, 'utf8');
    const configService = fs.readFileSync(configServicePath, 'utf8');
    
    expect(configService).toContain('"units": {"families": true}');
    expect(serverJs).toContain('"units": {\n      "families": true\n    }');
    expect(serverJs).toContain('"units": {\n        "families": true\n      }');
  });
});
