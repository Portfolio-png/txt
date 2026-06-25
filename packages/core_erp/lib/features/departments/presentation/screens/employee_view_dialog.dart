import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../domain/employee_definition.dart';
import 'employee_editor_dialog.dart';

class EmployeeViewDialog extends StatelessWidget {
  const EmployeeViewDialog({
    super.key,
    required this.departmentId,
    required this.employee,
  });

  final int departmentId;
  final EmployeeDefinition employee;

  static Future<void> open(
    BuildContext context, {
    required int departmentId,
    required EmployeeDefinition employee,
  }) {
    return showDialog(
      context: context,
      builder: (context) => EmployeeViewDialog(
        departmentId: departmentId,
        employee: employee,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 800,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: SoftErpTheme.raisedShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _buildDetailsColumn(),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      flex: 4,
                      child: _buildDocumentsColumn(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: SoftErpTheme.accentGradient,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              employee.name.isNotEmpty ? employee.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
                if (employee.role.isNotEmpty)
                  Text(
                    employee.role,
                    style: const TextStyle(
                      fontSize: 14,
                      color: SoftErpTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SoftStatusPill(
            label: employee.status.toUpperCase(),
            background: employee.status == 'active'
                ? SoftErpTheme.successBg
                : SoftErpTheme.cardSurfaceAlt,
            textColor: employee.status == 'active'
                ? SoftErpTheme.successText
                : SoftErpTheme.textSecondary,
            borderColor: employee.status == 'active'
                ? SoftErpTheme.successBg
                : SoftErpTheme.border,
          ),
          const SizedBox(width: 16),
          AppButton(
            label: 'Edit',
            icon: Icons.edit_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: () {
              Navigator.of(context).pop(); // Close view
              EmployeeEditorDialog.open(
                context,
                departmentId: departmentId,
                employee: employee,
              );
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            color: SoftErpTheme.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Personal Details',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: SoftErpTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        _buildInfoRow(Icons.phone_outlined, 'Phone', employee.phone.isEmpty ? '—' : employee.phone),
        const SizedBox(height: 12),
        _buildInfoRow(Icons.home_outlined, 'Address', employee.address.isEmpty ? '—' : employee.address),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 24),
        const Text(
          'Engagement Details',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: SoftErpTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        _buildInfoRow(Icons.work_outline_rounded, 'Employment Type', employee.employmentType),
        if (employee.employmentType == 'freelancer' && employee.barcodeId.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Barcode ID',
            style: TextStyle(
              fontSize: 12,
              color: SoftErpTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SoftErpTheme.border),
            ),
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: employee.barcodeId,
              width: double.infinity,
              height: 76,
              drawText: true,
              style: const TextStyle(
                color: SoftErpTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 24),
        const Text(
          'Identity Numbers',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: SoftErpTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        _buildInfoRow(Icons.pin_outlined, 'Aadhar Number', employee.aadharNumber.isEmpty ? '—' : employee.aadharNumber),
        const SizedBox(height: 12),
        _buildInfoRow(Icons.credit_card_outlined, 'PAN Number', employee.panNumber.isEmpty ? '—' : employee.panNumber),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: SoftErpTheme.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: SoftErpTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: SoftErpTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentsColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Documents & Photos',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: SoftErpTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        _buildDocumentCard('Employee Photo', employee.employeePhotoUrl, Icons.person),
        const SizedBox(height: 16),
        _buildDocumentCard('Aadhar Card', employee.aadharPhotoUrl, Icons.credit_card),
        const SizedBox(height: 16),
        _buildDocumentCard('PAN Card', employee.panPhotoUrl, Icons.credit_card_outlined),
      ],
    );
  }

  Widget _buildDocumentCard(String label, String url, IconData fallbackIcon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: SoftErpTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 140,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          clipBehavior: Clip.antiAlias,
          child: url.isNotEmpty
              ? Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    fallbackIcon,
                    color: const Color(0xFF94A3B8),
                    size: 40,
                  ),
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        fallbackIcon,
                        color: const Color(0xFFCBD5E1),
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Not uploaded',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
