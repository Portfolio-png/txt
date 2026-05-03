import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CachedPoFile {
  const CachedPoFile({
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.sha256,
    required this.cachePath,
    required this.cachedAt,
  });

  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String sha256;
  final String cachePath;
  final DateTime cachedAt;

  Map<String, dynamic> toJson() {
    return {
      'fileName': fileName,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'sha256': sha256,
      'cachePath': cachePath,
      'cachedAt': cachedAt.toIso8601String(),
    };
  }

  factory CachedPoFile.fromJson(Map<String, dynamic> json) {
    return CachedPoFile(
      fileName: json['fileName'] as String? ?? '',
      contentType: json['contentType'] as String? ?? '',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      sha256: json['sha256'] as String? ?? '',
      cachePath: json['cachePath'] as String? ?? '',
      cachedAt:
          DateTime.tryParse(json['cachedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class PoDocumentCache {
  static const int maxBytes = 100 * 1024 * 1024;
  static const Duration maxAge = Duration(days: 30);
  static const Set<String> allowedContentTypes = {
    'application/pdf',
    'image/png',
    'image/jpeg',
  };

  Future<CachedPoFile> cachePickedFile(XFile file) async {
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes).toString();
    final contentType =
        file.mimeType ??
        lookupMimeType(file.name, headerBytes: bytes.take(24).toList()) ??
        _contentTypeFromExtension(file.name);
    if (!allowedContentTypes.contains(contentType)) {
      throw const PoCacheException('Select a PDF, PNG, JPG, or JPEG file.');
    }
    final directory = await _cacheDirectory();
    await directory.create(recursive: true);
    final extension = _extensionForContentType(contentType, file.name);
    final cacheFile = File(p.join(directory.path, '$digest$extension'));
    if (!await cacheFile.exists()) {
      await cacheFile.writeAsBytes(bytes, flush: true);
    }
    final cached = CachedPoFile(
      fileName: p.basename(file.name),
      contentType: contentType,
      sizeBytes: bytes.length,
      sha256: digest,
      cachePath: cacheFile.path,
      cachedAt: DateTime.now(),
    );
    await _upsertIndex(cached);
    await prune();
    return cached;
  }

  Future<List<CachedPoFile>> recentFiles() async {
    final entries = await _readIndex();
    final existing = <CachedPoFile>[];
    for (final entry in entries) {
      if (await File(entry.cachePath).exists()) {
        existing.add(entry);
      }
    }
    existing.sort((a, b) => b.cachedAt.compareTo(a.cachedAt));
    return existing.take(8).toList(growable: false);
  }

  Future<List<int>> readBytes(CachedPoFile file) {
    return File(file.cachePath).readAsBytes();
  }

  Future<void> prune() async {
    final cutoff = DateTime.now().subtract(maxAge);
    final entries = await _readIndex();
    final retained = <CachedPoFile>[];
    for (final entry in entries) {
      final cacheFile = File(entry.cachePath);
      if (entry.cachedAt.isBefore(cutoff)) {
        if (await cacheFile.exists()) {
          await cacheFile.delete();
        }
        continue;
      }
      if (await cacheFile.exists()) {
        retained.add(entry);
      }
    }
    retained.sort((a, b) => b.cachedAt.compareTo(a.cachedAt));
    var total = retained.fold<int>(0, (sum, entry) => sum + entry.sizeBytes);
    final finalEntries = <CachedPoFile>[];
    for (final entry in retained) {
      if (total > maxBytes) {
        final cacheFile = File(entry.cachePath);
        if (await cacheFile.exists()) {
          await cacheFile.delete();
        }
        total -= entry.sizeBytes;
        continue;
      }
      finalEntries.add(entry);
    }
    await _writeIndex(finalEntries);
  }

  Future<Directory> _cacheDirectory() async {
    final root = await getTemporaryDirectory();
    return Directory(p.join(root.path, 'paper_po_cache'));
  }

  Future<File> _indexFile() async {
    final directory = await _cacheDirectory();
    await directory.create(recursive: true);
    return File(p.join(directory.path, 'po_cache_index.json'));
  }

  Future<List<CachedPoFile>> _readIndex() async {
    final file = await _indexFile();
    if (!await file.exists()) {
      return const <CachedPoFile>[];
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List<dynamic>) {
      return const <CachedPoFile>[];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(CachedPoFile.fromJson)
        .toList(growable: false);
  }

  Future<void> _writeIndex(List<CachedPoFile> entries) async {
    final file = await _indexFile();
    await file.writeAsString(
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> _upsertIndex(CachedPoFile file) async {
    final entries = await _readIndex();
    final merged = <CachedPoFile>[
      file,
      ...entries.where((entry) => entry.sha256 != file.sha256),
    ];
    await _writeIndex(merged);
  }

  static String _contentTypeFromExtension(String fileName) {
    switch (p.extension(fileName).toLowerCase()) {
      case '.pdf':
        return 'application/pdf';
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      default:
        return 'application/octet-stream';
    }
  }

  static String _extensionForContentType(String contentType, String fileName) {
    final existing = p.extension(fileName).toLowerCase();
    if (existing == '.pdf' ||
        existing == '.png' ||
        existing == '.jpg' ||
        existing == '.jpeg') {
      return existing;
    }
    switch (contentType) {
      case 'application/pdf':
        return '.pdf';
      case 'image/png':
        return '.png';
      case 'image/jpeg':
        return '.jpg';
      default:
        return '.bin';
    }
  }
}

class PoCacheException implements Exception {
  const PoCacheException(this.message);

  final String message;

  @override
  String toString() => message;
}
