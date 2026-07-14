const fs = require('fs');

let content = fs.readFileSync('packages/core_erp/lib/features/auth/domain/auth_user.dart', 'utf8');

// 1. Add fields to constructor
const constructorTarget = "this.createdAt,\n    this.mobilePin,";
const constructorReplacement = "this.createdAt,\n    this.mobilePin,\n    this.clientId,\n    this.clientName,";
content = content.replace(constructorTarget, constructorReplacement);

// 2. Add final fields
const finalTarget = "final DateTime createdAt;\n  final String? mobilePin;";
const finalReplacement = "final DateTime createdAt;\n  final String? mobilePin;\n  final int? clientId;\n  final String? clientName;";
content = content.replace(finalTarget, finalReplacement);

// 3. Add to fromJson
const fromJsonTarget = "createdAt: DateTime.parse(json['createdAt'] as String),\n      mobilePin: json['mobilePin'] as String?,";
const fromJsonReplacement = "createdAt: DateTime.parse(json['createdAt'] as String),\n      mobilePin: json['mobilePin'] as String?,\n      clientId: json['clientId'] as int?,\n      clientName: json['clientName'] as String?,";
content = content.replace(fromJsonTarget, fromJsonReplacement);

// 4. Add to toJson
const toJsonTarget = "'createdAt': createdAt.toIso8601String(),\n      'mobilePin': mobilePin,";
const toJsonReplacement = "'createdAt': createdAt.toIso8601String(),\n      'mobilePin': mobilePin,\n      'clientId': clientId,\n      'clientName': clientName,";
content = content.replace(toJsonTarget, toJsonReplacement);

fs.writeFileSync('packages/core_erp/lib/features/auth/domain/auth_user.dart', content);
console.log("Patched auth_user.dart");

