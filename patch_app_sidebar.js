const fs = require('fs');
let code = fs.readFileSync('apps/challans_only/lib/shell/app_sidebar.dart', 'utf8');

code = code.replace(
  `Future<void> _handleResetAndReseed() async {
    setState(() {
      _isResetting = true;
    });
    final auth = context.read<AuthProvider>();
    final success = await auth.resetDemoData();`,
  `Future<void> _handleResetAndReseed(String scenarioId) async {
    setState(() {
      _isResetting = true;
    });
    final auth = context.read<AuthProvider>();
    final success = await auth.resetDemoData(scenarioId: scenarioId);`
);

// We need to replace the single button with a Test Scenarios section
const oldButtons = `                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isResetting ? null : _handleClearDB,
                      child: _isResetting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Clear DB'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _isResetting ? null : _handleResetAndReseed,
                      child: _isResetting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Reset Demo Data'),
                    ),
                  ],
                ),`;

const newButtons = `                const SizedBox(height: 20),
                Text(
                  'Test Scenarios',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: SoftErpTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: SoftErpTheme.cardSurfaceAlt,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: SoftErpTheme.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Electrical Variations', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Default 13 items with color & module variations.', style: TextStyle(fontSize: 12)),
                        trailing: ElevatedButton(
                          onPressed: _isResetting ? null : () => _handleResetAndReseed('default'),
                          child: const Text('Seed Scenario'),
                        ),
                      ),
                      const Divider(height: 24),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Manufacturing Processes', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Intermediate items with processing stages (RAW-MLL-ANO).', style: TextStyle(fontSize: 12)),
                        trailing: ElevatedButton(
                          onPressed: _isResetting ? null : () => _handleResetAndReseed('manufacturing'),
                          child: const Text('Seed Scenario'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isResetting ? null : _handleClearDB,
                      child: const Text('Clear DB Only (Empty)'),
                    ),
                  ],
                ),`;

code = code.replace(oldButtons, newButtons);
fs.writeFileSync('apps/challans_only/lib/shell/app_sidebar.dart', code);
console.log('Patched app_sidebar.dart');
