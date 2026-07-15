const { Database } = require('sqlite3').verbose();
const db = new Database('paper.db');
const employees = [
  { name: 'Rajesh Kumar', role: 'CNC Operator', phone: '9876543210', employment_type: 'in-house', status: 'active', department: 'Production' },
  { name: 'Amit Singh', role: 'Quality Inspector', phone: '9876543211', employment_type: 'in-house', status: 'active', department: 'Quality Control' },
  { name: 'Vikram Sharma', role: 'Maintenance Engineer', phone: '9876543212', employment_type: 'in-house', status: 'active', department: 'Maintenance' },
  { name: 'Sanjay Patel', role: 'Production Manager', phone: '9876543213', employment_type: 'in-house', status: 'active', department: 'Management' },
  { name: 'Priya Verma', role: 'HR Executive', phone: '9876543214', employment_type: 'in-house', status: 'active', department: 'HR' },
  { name: 'Manoj Desai', role: 'CNC Programmer', phone: '9876543215', employment_type: 'in-house', status: 'active', department: 'Engineering' }
];

db.serialize(() => {
  employees.forEach(emp => {
    db.run("INSERT INTO departments (name, created_at, updated_at) SELECT ?, datetime('now'), datetime('now') WHERE NOT EXISTS(SELECT 1 FROM departments WHERE name = ?)", [emp.department, emp.department], function(err) {
      if (err) console.error("Error inserting department:", err);
      db.get("SELECT id FROM departments WHERE name = ?", [emp.department], (err, row) => {
        if (err) console.error("Error fetching department:", err);
        const deptId = row ? row.id : null;
        if (!deptId) {
           console.error("Dept ID not found for", emp.department);
           return;
        }
        db.run("INSERT INTO employees (department_id, name, role, phone, employment_type, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))",
          [deptId, emp.name, emp.role, emp.phone, emp.employment_type, emp.status], (err) => {
             if (err) console.error("Error inserting employee:", err);
          });
      });
    });
  });
});
console.log('Employees seeding initiated');
