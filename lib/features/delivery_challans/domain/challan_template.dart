import 'delivery_challan.dart';

enum ChallanTemplatePartyType { generic, client, vendor }

ChallanTemplatePartyType challanTemplatePartyTypeFromName(String value) {
  return ChallanTemplatePartyType.values.firstWhere(
    (type) => type.name == value.toLowerCase(),
    orElse: () => ChallanTemplatePartyType.generic,
  );
}

class ChallanTemplateMapping {
  const ChallanTemplateMapping({
    required this.id,
    required this.templateId,
    required this.fieldType,
    required this.fieldKey,
    required this.fieldValue,
    required this.assetObjectKey,
    required this.assetImageUrl,
    required this.assetWidthPx,
    required this.assetHeightPx,
    required this.widthMm,
    required this.heightMm,
    required this.imageWidthMm,
    required this.imageHeightMm,
    required this.lockAspectRatio,
    required this.xPercent,
    required this.yPercent,
    required this.fontSize,
    required this.fontWeight,
    required this.alignment,
    required this.textColor,
    required this.letterSpacing,
    required this.maxChars,
    required this.maxWidthMm,
    required this.minFontSize,
    required this.minRows,
    required this.maxRows,
    required this.tableHeightMm,
    required this.rowHeightMm,
  });

  final int id;
  final int templateId;
  final String fieldType;
  final String fieldKey;
  final String fieldValue;
  final String assetObjectKey;
  final String? assetImageUrl;
  final int assetWidthPx;
  final int assetHeightPx;
  final double widthMm;
  final double heightMm;
  final double imageWidthMm;
  final double imageHeightMm;
  final bool lockAspectRatio;
  final double xPercent;
  final double yPercent;
  final double fontSize;
  final String fontWeight;
  final String alignment;
  final String textColor;
  final double letterSpacing;
  final int maxChars;
  final double maxWidthMm;
  final double minFontSize;
  final int minRows;
  final int maxRows;
  final double tableHeightMm;
  final double rowHeightMm;

  ChallanTemplateMapping copyWith({
    int? id,
    int? templateId,
    String? fieldType,
    String? fieldKey,
    String? fieldValue,
    String? assetObjectKey,
    String? assetImageUrl,
    int? assetWidthPx,
    int? assetHeightPx,
    double? widthMm,
    double? heightMm,
    double? imageWidthMm,
    double? imageHeightMm,
    bool? lockAspectRatio,
    double? xPercent,
    double? yPercent,
    double? fontSize,
    String? fontWeight,
    String? alignment,
    String? textColor,
    double? letterSpacing,
    int? maxChars,
    double? maxWidthMm,
    double? minFontSize,
    int? minRows,
    int? maxRows,
    double? tableHeightMm,
    double? rowHeightMm,
  }) {
    return ChallanTemplateMapping(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      fieldType: fieldType ?? this.fieldType,
      fieldKey: fieldKey ?? this.fieldKey,
      fieldValue: fieldValue ?? this.fieldValue,
      assetObjectKey: assetObjectKey ?? this.assetObjectKey,
      assetImageUrl: assetImageUrl ?? this.assetImageUrl,
      assetWidthPx: assetWidthPx ?? this.assetWidthPx,
      assetHeightPx: assetHeightPx ?? this.assetHeightPx,
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      imageWidthMm: imageWidthMm ?? this.imageWidthMm,
      imageHeightMm: imageHeightMm ?? this.imageHeightMm,
      lockAspectRatio: lockAspectRatio ?? this.lockAspectRatio,
      xPercent: xPercent ?? this.xPercent,
      yPercent: yPercent ?? this.yPercent,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      alignment: alignment ?? this.alignment,
      textColor: textColor ?? this.textColor,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      maxChars: maxChars ?? this.maxChars,
      maxWidthMm: maxWidthMm ?? this.maxWidthMm,
      minFontSize: minFontSize ?? this.minFontSize,
      minRows: minRows ?? this.minRows,
      maxRows: maxRows ?? this.maxRows,
      tableHeightMm: tableHeightMm ?? this.tableHeightMm,
      rowHeightMm: rowHeightMm ?? this.rowHeightMm,
    );
  }

  factory ChallanTemplateMapping.fromJson(Map<String, dynamic> json) {
    final fieldType =
        (json['fieldType'] as String? ??
                json['field_type'] as String? ??
                'DYNAMIC')
            .toUpperCase();
    final imageWidthMm =
        (json['imageWidthMm'] as num? ?? json['image_width_mm'] as num? ?? 35)
            .toDouble();
    final imageHeightMm =
        (json['imageHeightMm'] as num? ?? json['image_height_mm'] as num? ?? 20)
            .toDouble();
    final maxWidthMm =
        (json['maxWidthMm'] as num? ?? json['max_width_mm'] as num? ?? 80)
            .toDouble();
    return ChallanTemplateMapping(
      id: json['id'] as int? ?? 0,
      templateId:
          json['templateId'] as int? ?? json['template_id'] as int? ?? 0,
      fieldType:
          json['fieldType'] as String? ??
          json['field_type'] as String? ??
          'DYNAMIC',
      fieldKey:
          json['fieldKey'] as String? ?? json['field_key'] as String? ?? '',
      fieldValue:
          json['fieldValue'] as String? ?? json['field_value'] as String? ?? '',
      assetObjectKey:
          json['assetObjectKey'] as String? ??
          json['asset_object_key'] as String? ??
          '',
      assetImageUrl:
          json['assetImageUrl'] as String? ??
          json['asset_image_url'] as String?,
      assetWidthPx:
          json['assetWidthPx'] as int? ?? json['asset_width_px'] as int? ?? 0,
      assetHeightPx:
          json['assetHeightPx'] as int? ?? json['asset_height_px'] as int? ?? 0,
      widthMm:
          (json['widthMm'] as num? ??
                  json['width_mm'] as num? ??
                  (fieldType == 'IMAGE' ? imageWidthMm : maxWidthMm))
              .toDouble(),
      heightMm:
          (json['heightMm'] as num? ??
                  json['height_mm'] as num? ??
                  (fieldType == 'IMAGE' ? imageHeightMm : 12))
              .toDouble(),
      imageWidthMm: imageWidthMm,
      imageHeightMm: imageHeightMm,
      lockAspectRatio:
          json['lockAspectRatio'] as bool? ??
          ((json['lock_aspect_ratio'] as num? ?? 1).toInt() == 1),
      xPercent: (json['xPercent'] as num? ?? json['x_percent'] as num? ?? 0)
          .toDouble(),
      yPercent: (json['yPercent'] as num? ?? json['y_percent'] as num? ?? 0)
          .toDouble(),
      fontSize: (json['fontSize'] as num? ?? json['font_size'] as num? ?? 10)
          .toDouble(),
      fontWeight:
          json['fontWeight'] as String? ??
          json['font_weight'] as String? ??
          'normal',
      alignment: json['alignment'] as String? ?? 'left',
      textColor:
          json['textColor'] as String? ??
          json['text_color'] as String? ??
          'black',
      letterSpacing:
          (json['letterSpacing'] as num? ?? json['letter_spacing'] as num? ?? 0)
              .toDouble(),
      maxChars: json['maxChars'] as int? ?? json['max_chars'] as int? ?? 0,
      maxWidthMm: maxWidthMm,
      minFontSize:
          (json['minFontSize'] as num? ?? json['min_font_size'] as num? ?? 6)
              .toDouble(),
      minRows: json['minRows'] as int? ?? json['min_rows'] as int? ?? 0,
      maxRows: json['maxRows'] as int? ?? json['max_rows'] as int? ?? 0,
      tableHeightMm:
          (json['tableHeightMm'] as num? ??
                  json['table_height_mm'] as num? ??
                  60)
              .toDouble(),
      rowHeightMm:
          (json['rowHeightMm'] as num? ?? json['row_height_mm'] as num? ?? 6)
              .toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'templateId': templateId,
      'fieldType': fieldType,
      'fieldKey': fieldKey,
      'fieldValue': fieldValue,
      'assetObjectKey': assetObjectKey,
      'assetImageUrl': assetImageUrl,
      'assetWidthPx': assetWidthPx,
      'assetHeightPx': assetHeightPx,
      'widthMm': widthMm,
      'heightMm': heightMm,
      'imageWidthMm': imageWidthMm,
      'imageHeightMm': imageHeightMm,
      'lockAspectRatio': lockAspectRatio,
      'xPercent': xPercent,
      'yPercent': yPercent,
      'fontSize': fontSize,
      'fontWeight': fontWeight,
      'alignment': alignment,
      'textColor': textColor,
      'letterSpacing': letterSpacing,
      'maxChars': maxChars,
      'maxWidthMm': maxWidthMm,
      'minFontSize': minFontSize,
      'minRows': minRows,
      'maxRows': maxRows,
      'tableHeightMm': tableHeightMm,
      'rowHeightMm': rowHeightMm,
    };
  }
}

class ChallanTemplate {
  const ChallanTemplate({
    required this.id,
    required this.name,
    required this.partyType,
    required this.partyId,
    required this.challanType,
    required this.backgroundObjectKey,
    required this.backgroundImageUrl,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.rotationDegrees,
    required this.globalOffsetXmm,
    required this.globalOffsetYmm,
    required this.stockSize,
    required this.paperSize,
    required this.nUpLayout,
    required this.isActive,
    required this.mappings,
  });

  final int id;
  final String name;
  final ChallanTemplatePartyType partyType;
  final int partyId;
  final ChallanType challanType;
  final String backgroundObjectKey;
  final String? backgroundImageUrl;
  final int canvasWidth;
  final int canvasHeight;
  final double rotationDegrees;
  final double globalOffsetXmm;
  final double globalOffsetYmm;
  final String stockSize;
  final String paperSize;
  final int nUpLayout;
  final bool isActive;
  final List<ChallanTemplateMapping> mappings;

  factory ChallanTemplate.fromJson(Map<String, dynamic> json) {
    return ChallanTemplate(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      partyType: challanTemplatePartyTypeFromName(
        json['partyType'] as String? ?? json['party_type'] as String? ?? '',
      ),
      partyId: json['partyId'] as int? ?? json['party_id'] as int? ?? 0,
      challanType: challanTypeFromName(
        json['challanType'] as String? ??
            json['challan_type'] as String? ??
            'delivery',
      ),
      backgroundObjectKey:
          json['backgroundObjectKey'] as String? ??
          json['background_object_key'] as String? ??
          '',
      backgroundImageUrl: json['backgroundImageUrl'] as String?,
      canvasWidth:
          json['canvasWidth'] as int? ?? json['canvas_width'] as int? ?? 0,
      canvasHeight:
          json['canvasHeight'] as int? ?? json['canvas_height'] as int? ?? 0,
      rotationDegrees:
          (json['rotationDegrees'] as num? ??
                  json['rotation_degrees'] as num? ??
                  0)
              .toDouble(),
      globalOffsetXmm:
          (json['globalOffsetXmm'] as num? ??
                  json['global_offset_x_mm'] as num? ??
                  0)
              .toDouble(),
      globalOffsetYmm:
          (json['globalOffsetYmm'] as num? ??
                  json['global_offset_y_mm'] as num? ??
                  0)
              .toDouble(),
      stockSize:
          json['stockSize'] as String? ??
          json['stock_size'] as String? ??
          json['paperSize'] as String? ??
          json['paper_size'] as String? ??
          'A4',
      paperSize:
          json['paperSize'] as String? ?? json['paper_size'] as String? ?? 'A4',
      nUpLayout: json['nUpLayout'] as int? ?? json['n_up_layout'] as int? ?? 1,
      isActive:
          json['isActive'] as bool? ??
          ((json['is_active'] as num? ?? 1).toInt() == 1),
      mappings: (json['mappings'] as List<dynamic>? ?? const [])
          .map(
            (mapping) => ChallanTemplateMapping.fromJson(
              mapping as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
    );
  }
}

class ChallanTemplateInput {
  const ChallanTemplateInput({
    required this.name,
    required this.partyType,
    required this.partyId,
    required this.challanType,
    required this.backgroundObjectKey,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.rotationDegrees,
    required this.globalOffsetXmm,
    required this.globalOffsetYmm,
    required this.stockSize,
    required this.paperSize,
    required this.nUpLayout,
    required this.isActive,
    required this.mappings,
  });

  final String name;
  final ChallanTemplatePartyType partyType;
  final int partyId;
  final ChallanType challanType;
  final String backgroundObjectKey;
  final int canvasWidth;
  final int canvasHeight;
  final double rotationDegrees;
  final double globalOffsetXmm;
  final double globalOffsetYmm;
  final String stockSize;
  final String paperSize;
  final int nUpLayout;
  final bool isActive;
  final List<ChallanTemplateMapping> mappings;

  Map<String, dynamic> toJson() {
    return {
      'name': name.trim(),
      'partyType': partyType.name,
      'partyId': partyId,
      'challanType': challanType.name,
      'backgroundObjectKey': backgroundObjectKey,
      'canvasWidth': canvasWidth,
      'canvasHeight': canvasHeight,
      'rotationDegrees': rotationDegrees,
      'globalOffsetXmm': globalOffsetXmm,
      'globalOffsetYmm': globalOffsetYmm,
      'stockSize': stockSize,
      'paperSize': paperSize,
      'nUpLayout': nUpLayout,
      'isActive': isActive,
      'mappings': mappings.map((mapping) => mapping.toJson()).toList(),
    };
  }
}

class ChallanTemplateUploadIntentInput {
  const ChallanTemplateUploadIntentInput({
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.sha256,
  });

  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String sha256;
}

class ChallanTemplateUploadTarget {
  const ChallanTemplateUploadTarget({
    required this.uploadSessionId,
    required this.objectKey,
    required this.uploadUrl,
    required this.headers,
  });

  final String uploadSessionId;
  final String objectKey;
  final Uri uploadUrl;
  final Map<String, String> headers;

  factory ChallanTemplateUploadTarget.fromJson(Map<String, dynamic> json) {
    return ChallanTemplateUploadTarget(
      uploadSessionId: json['uploadSessionId'] as String? ?? '',
      objectKey: json['objectKey'] as String? ?? '',
      uploadUrl: Uri.parse(json['uploadUrl'] as String? ?? ''),
      headers: (json['headers'] as Map<String, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(key, '$value'),
      ),
    );
  }
}

class ChallanTemplateBackground {
  const ChallanTemplateBackground({
    required this.objectKey,
    required this.canvasWidth,
    required this.canvasHeight,
  });

  final String objectKey;
  final int canvasWidth;
  final int canvasHeight;

  factory ChallanTemplateBackground.fromJson(Map<String, dynamic> json) {
    return ChallanTemplateBackground(
      objectKey: json['objectKey'] as String? ?? '',
      canvasWidth: json['canvasWidth'] as int? ?? 0,
      canvasHeight: json['canvasHeight'] as int? ?? 0,
    );
  }
}
