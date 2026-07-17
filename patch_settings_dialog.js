const fs = require('fs');
let code = fs.readFileSync('packages/core_erp/lib/core/widgets/app_settings_dialog.dart', 'utf8');

const newToggles = `
                        const Divider(height: 24),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: preferences.enableManufacturing,
                          onChanged: preferences.toggleManufacturing,
                          title: const Text(
                            'Manufacturing Mode',
                            style: TextStyle(
                              color: SoftErpTheme.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: const Text(
                            'Enable linkage to production runs, tracking raw material vs. finished goods.',
                            style: TextStyle(color: SoftErpTheme.textSecondary),
                          ),
                        ),
                        const Divider(height: 24),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: preferences.enableServiceMode,
                          onChanged: preferences.toggleServiceMode,
                          title: const Text(
                            'Service (Job Work) Mode',
                            style: TextStyle(
                              color: SoftErpTheme.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: const Text(
                            'Enable customer-owned stock receipt (Inward), printing/processing, and return.',
                            style: TextStyle(color: SoftErpTheme.textSecondary),
                          ),
                        ),
                      ],
`;

code = code.replace(/                      \],\n                    \),\n                  \);\n                },\n              \),/, newToggles + '                    ),\n                  );\n                },\n              ),');

fs.writeFileSync('packages/core_erp/lib/core/widgets/app_settings_dialog.dart', code);
console.log('Patched AppSettingsDialog with missing toggles');
