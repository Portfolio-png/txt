const fs = require('fs');

let content = fs.readFileSync('packages/core_erp/lib/features/auth/presentation/screens/user_management_screen.dart', 'utf8');

// 1. Imports
const importsTarget = "import '../providers/auth_provider.dart';";
const importsReplacement = "import '../providers/auth_provider.dart';\nimport '../../clients/presentation/providers/clients_provider.dart';\nimport '../../clients/domain/client_definition.dart';";
content = content.replace(importsTarget, importsReplacement);

// 2. Add selectedClientId inside _openCreateUserDialog
const methodStartTarget = "final passwordController = TextEditingController();\n    final formKey = GlobalKey<FormState>();";
const methodStartReplacement = "final passwordController = TextEditingController();\n    int? selectedClientId;\n    final clientsProvider = context.read<ClientsProvider>();\n    final clients = clientsProvider.clients;\n    final formKey = GlobalKey<FormState>();";
content = content.replace(methodStartTarget, methodStartReplacement);

// 3. Add Dropdown to UI
// Find the exact place to insert the dropdown
const dialogColumnsTarget = "validator: (value) => _passwordPolicyValidator(\n                    value,\n                    email: emailController.text,\n                    role: admin ? 'admin' : 'user',\n                  ),\n                ),";

const dropdownCode = `DropdownButtonFormField<int?>(
                  decoration: const InputDecoration(labelText: 'Assign to Client/Factory (Optional)'),
                  value: selectedClientId,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None (Global Access)')),
                    ...clients.map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.displayLabel),
                        )),
                  ],
                  onChanged: (val) => selectedClientId = val,
                ),`;

const dialogColumnsReplacement = `${dialogColumnsTarget}\n                const SizedBox(height: 16),\n                ${dropdownCode}`;
content = content.replace(dialogColumnsTarget, dialogColumnsReplacement);

// 4. Update createUser call
const createUserTarget = "email: emailController.text,\n                password: passwordController.text,\n                admin: admin,\n              );";
const createUserReplacement = "email: emailController.text,\n                password: passwordController.text,\n                admin: admin,\n                clientId: selectedClientId,\n              );";
content = content.replace(createUserTarget, createUserReplacement);

// 5. Update UI to show clientName in the user list if present.
// Let's find where role is printed: Text(user.role.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold))
const userRowTarget = "Text(\n                        user.role.toUpperCase(),\n                        style: const TextStyle(fontWeight: FontWeight.bold),\n                      ),";
const userRowReplacement = `${userRowTarget}\n                      if (user.clientName != null) ...[\n                        const SizedBox(width: 8),\n                        Container(\n                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),\n                          decoration: BoxDecoration(\n                            color: Colors.blue.shade50,\n                            borderRadius: BorderRadius.circular(4),\n                          ),\n                          child: Text(\n                            user.clientName!,\n                            style: TextStyle(fontSize: 12, color: Colors.blue.shade900),\n                          ),\n                        ),\n                      ],`;

content = content.replace(userRowTarget, userRowReplacement);

fs.writeFileSync('packages/core_erp/lib/features/auth/presentation/screens/user_management_screen.dart', content);
console.log("Patched user_management_screen.dart");
