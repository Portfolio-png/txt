const fs = require('fs');

const file = 'backend/server.js';
let content = fs.readFileSync(file, 'utf8');

const target = "await run('DELETE FROM delete_requests WHERE requested_by_user_id = ?', [targetId]);";
if (content.indexOf(target) === -1) {
  console.log("Could not find target line.");
  process.exit(1);
}

const replacement = target + `
      await run('UPDATE users SET created_by_user_id = NULL WHERE created_by_user_id = ?', [targetId]);
      await run('UPDATE procurement_requests SET created_by_user_id = NULL WHERE created_by_user_id = ?', [targetId]);
      await run('UPDATE procurement_requests SET raised_by_user_id = NULL WHERE raised_by_user_id = ?', [targetId]);
      await run('UPDATE procurement_requests SET cancelled_by_user_id = NULL WHERE cancelled_by_user_id = ?', [targetId]);
      await run('UPDATE procurement_requests SET closed_by_user_id = NULL WHERE closed_by_user_id = ?', [targetId]);
      await run('UPDATE procurement_activity_log SET actor_user_id = NULL WHERE actor_user_id = ?', [targetId]);
      await run('UPDATE delivery_challans SET created_by = NULL WHERE created_by = ?', [targetId]);
      await run('UPDATE delivery_challans SET updated_by = NULL WHERE updated_by = ?', [targetId]);
      await run('DELETE FROM search_history WHERE user_id = ?', [targetId]);
      await run('DELETE FROM search_clicks WHERE user_id = ?', [targetId]);`;

content = content.replace(target, replacement);

fs.writeFileSync(file, content);
console.log("Patched user delete transaction!");

