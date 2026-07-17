const fs = require('fs');
let code = fs.readFileSync('server.js', 'utf8');

const oldInventorySeeding = `      // Also maybe RAW-NON-NON
      const materialId2 = await createOrGetMaterial(item.id, {
        'Initial State': 'Raw',
        'Primary Process': 'None',
        'Finishing': 'None'
      });
      
      await addInventory(materialId, 500); // 500 kg
      await addInventory(materialId2, 1000); // 1000 kg`;

const newInventorySeeding = `      // The intermediate item (Milled but NOT Anodized): RAW-MLL-NON
      const materialIdIntermediate = await createOrGetMaterial(item.id, {
        'Initial State': 'Raw',
        'Primary Process': 'Milled',
        'Finishing': 'None'
      });

      // Also the raw item: RAW-NON-NON
      const materialId2 = await createOrGetMaterial(item.id, {
        'Initial State': 'Raw',
        'Primary Process': 'None',
        'Finishing': 'None'
      });
      
      await addInventory(materialId, 500); // 500 kg Finished (RAW-MLL-ANO)
      await addInventory(materialIdIntermediate, 300); // 300 kg Intermediate (RAW-MLL-NON)
      await addInventory(materialId2, 1000); // 1000 kg Raw (RAW-NON-NON)`;

code = code.replace(oldInventorySeeding, newInventorySeeding);
fs.writeFileSync('server.js', code);
console.log('Patched server.js with intermediate items');
