const fs = require('fs');
let code = fs.readFileSync('server.js', 'utf8');

const oldCopper = `    if (item.name === 'Copper Coil') {
      const materialId = await createOrGetMaterial(item.id, {
        'State': 'Drawn',
        'Treatment': 'Insulated'
      });
      await addInventory(materialId, 250);
    }`;

const newCopper = `    if (item.name === 'Copper Coil') {
      const materialId = await createOrGetMaterial(item.id, {
        'State': 'Drawn',
        'Treatment': 'Insulated'
      });
      await addInventory(materialId, 250); // Finished
      
      const materialIdRaw = await createOrGetMaterial(item.id, {
        'State': 'Drawn',
        'Treatment': 'Bare'
      });
      await addInventory(materialIdRaw, 150); // Intermediate / Raw
    }`;

code = code.replace(oldCopper, newCopper);
fs.writeFileSync('server.js', code);
console.log('Patched server.js with copper intermediate items');
