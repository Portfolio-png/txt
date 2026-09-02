#!/usr/bin/env bash
# Regenerates the cross-language barcode codec vectors.
#
# The codec exists twice — backend/kernel/barcodes.js and
# packages/core_erp/lib/core/services/barcode_codec.dart — which is a real
# hazard: nothing stops one side drifting, and the symptom would be a printed
# label the server refuses to resolve.
#
# So the JS implementation is treated as the source of truth. This script runs
# it and writes what it actually does into two pinned fixtures:
#
#   backend/test/fixtures/barcode-vectors.json          (checked by the JS test)
#   packages/core_erp/test/fixtures/barcode_codec_vectors.dart  (by the Dart test)
#
# Run this ONLY when you have deliberately changed the codec. If a test fails
# and you have not, do not regenerate — the two sides have drifted and
# regenerating would paper over exactly the bug this is here to catch.
set -euo pipefail
cd "$(dirname "$0")/.."
node tool/gen_barcode_vectors.js
echo "Regenerated. Now run:  (cd backend && npm test)  and  flutter test packages/core_erp/test/barcode_codec_test.dart"
