import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_button.dart';
import '../../domain/client_definition.dart';
import '../../domain/sub_contractor_definition.dart';
import '../../domain/sub_contractor_inputs.dart';
import '../providers/sub_contractors_provider.dart';

class SubContractorsSheet extends StatefulWidget {
  const SubContractorsSheet({super.key, required this.client, this.onSelect});

  final ClientDefinition client;
  final ValueChanged<SubContractorDefinition>? onSelect;

  static Future<SubContractorDefinition?> show(
    BuildContext context,
    ClientDefinition client,
  ) {
    return showModalBottomSheet<SubContractorDefinition>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SubContractorsSheet(
        client: client,
        onSelect: (sub) => Navigator.pop(context, sub),
      ),
    );
  }

  @override
  State<SubContractorsSheet> createState() => _SubContractorsSheetState();
}

class _SubContractorsSheetState extends State<SubContractorsSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SubContractorsProvider>().loadForClient(widget.client.id);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final input = CreateSubContractorInput(
      name: name,
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
    );

    try {
      await context.read<SubContractorsProvider>().create(
        widget.client.id,
        input,
      );
      setState(() {
        _isAdding = false;
        _nameController.clear();
        _phoneController.clear();
        _emailController.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SubContractorsProvider>();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sub-contractors',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'for ${widget.client.name}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  color: const Color(0xFF64748B),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          if (_isAdding) ...[
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add New Sub-contractor',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'e.g. John Doe',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      hintText: 'e.g. +1 234 567 8900',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'e.g. john@example.com',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _isAdding = false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 16),
                      AppButton(label: 'Add', onPressed: _submit),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],

          Expanded(
            child: provider.isLoading && provider.subContractors.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : provider.subContractors.isEmpty && !_isAdding
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'No sub-contractors found',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 16),
                        AppButton(
                          label: 'Add Sub-contractor',
                          icon: Icons.add,
                          onPressed: () => setState(() => _isAdding = true),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: provider.subContractors.length,
                    itemBuilder: (context, index) {
                      final sub = provider.subContractors[index];
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        child: ListTile(
                          onTap: widget.onSelect != null
                              ? () => widget.onSelect!(sub)
                              : null,
                          title: Text(
                            sub.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            [
                              if (sub.phone.isNotEmpty) sub.phone,
                              if (sub.email.isNotEmpty) sub.email,
                            ].join(' • '),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Delete Sub-contractor?'),
                                  content: const Text(
                                    'This action cannot be undone.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && mounted) {
                                context.read<SubContractorsProvider>().delete(
                                  sub.id,
                                );
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),

          if (!_isAdding && provider.subContractors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: AppButton(
                label: 'Add Sub-contractor',
                icon: Icons.add,
                onPressed: () => setState(() => _isAdding = true),
              ),
            ),
        ],
      ),
    );
  }
}
