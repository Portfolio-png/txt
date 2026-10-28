import 'dart:convert';

import 'package:core_erp/core/services/generic_asset_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

// The upload behind every logo and photo field in the editors (clients,
// vendors, departments, employees, sets, items).

void main() {
  const input = GenericAssetUploadIntentInput(
    fileName: 'logo.png',
    contentType: 'image/png',
    sizeBytes: 3,
    sha256: 'abc',
  );

  test('what it hands back to save is the link that does not expire', () async {
    final service = GenericAssetService(
      baseUrl: 'http://x',
      useMockResponses: false,
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'success': true,
            'intent': {
              'upload': {
                'uploadUrl': 'http://x/put',
                'objectKey': 'generic/1-logo.png',
                'headers': {'Content-Type': 'image/png'},
                'readUrl': 'http://x/presigned?X-Amz-Expires=604800',
                'viewUrl': 'http://x/api/assets/view/generic/1-logo.png?sig=s',
              },
            },
          }),
          201,
        ),
      ),
    );
    final target = await service.createUploadIntent(input);
    expect(target.readUrl, 'http://x/api/assets/view/generic/1-logo.png?sig=s');
  });

  test(
    'an older server without the link still answers with its read URL',
    () async {
      final service = GenericAssetService(
        baseUrl: 'http://x',
        useMockResponses: false,
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'success': true,
              'intent': {
                'upload': {
                  'uploadUrl': 'http://x/put',
                  'objectKey': 'k',
                  'readUrl': 'http://x/presigned',
                },
              },
            }),
            201,
          ),
        ),
      );
      expect(
        (await service.createUploadIntent(input)).readUrl,
        'http://x/presigned',
      );
    },
  );

  testWidgets(
    'editors get the app\'s signed-in service, not a mock of their own',
    (tester) async {
      final real = GenericAssetService(
        baseUrl: 'http://x',
        useMockResponses: false,
      );
      late GenericAssetService resolved;
      await tester.pumpWidget(
        Provider<GenericAssetService>.value(
          value: real,
          child: Builder(
            builder: (context) {
              resolved = GenericAssetService.resolve(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(identical(resolved, real), isTrue);
    },
  );
}
