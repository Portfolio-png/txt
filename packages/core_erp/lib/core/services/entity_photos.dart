import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

/// What a photo can belong to. The server's `uploaded_assets.entity_type`.
abstract final class PhotoOwner {
  static const item = 'item';
  static const die = 'die';
  static const machine = 'machine';
  static const client = 'client';
  static const person = 'party_contact';

  static String uploadTypeOf(String owner) => switch (owner) {
    item => 'ITEM_IMAGE',
    die => 'DIE_IMAGE',
    machine => 'MACHINE_IMAGE',
    _ => 'PARTY_IMAGE',
  };
}

/// A record's photo: the asset, and a signed URL that is good for a few
/// minutes. The URL is minted on every read rather than stored on the record —
/// a stored presigned URL is what made the old photo fields go blank in days.
@immutable
class EntityPhoto {
  const EntityPhoto({
    required this.assetId,
    required this.url,
    required this.fetchedAt,
  });

  final int assetId;
  final String url;
  final DateTime fetchedAt;
}

/// The server's asset store, for photos of parts, dies, machines, companies
/// and people.
class EntityPhotoRepository {
  EntityPhotoRepository({
    required this.baseUrl,
    http.Client? client,
    http.Client? uploadClient,
    this.useMockResponses = false,
  }) : _client = client ?? http.Client(),
       _uploadClient = uploadClient ?? http.Client();

  final String baseUrl;
  final bool useMockResponses;

  /// Signed in: talks to the API.
  final http.Client _client;

  /// Not signed in: the PUT goes to a presigned URL, and a bearer token on it
  /// would break an S3 signature.
  final http.Client _uploadClient;

  final Map<String, ({int assetId, String url})> _mock = {};
  int _mockIds = 1;

  /// The primary photo of each of [ids], by id. Ids without one are absent.
  Future<Map<String, EntityPhoto>> primaryPhotos(
    String owner,
    List<String> ids,
  ) async {
    final now = DateTime.now();
    if (useMockResponses) {
      return {
        for (final id in ids)
          if (_mock['$owner:$id'] case final found?)
            id: EntityPhoto(
              assetId: found.assetId,
              url: found.url,
              fetchedAt: now,
            ),
      };
    }
    final payload = await _post('/api/assets/primary', {
      'entityType': owner,
      'entityIds': [for (final id in ids) int.tryParse(id) ?? id],
    });
    final photos = payload['photos'] as Map<String, dynamic>? ?? const {};
    return {
      for (final entry in photos.entries)
        if (entry.value is Map<String, dynamic> &&
            (entry.value['readUrl'] as String?)?.isNotEmpty == true)
          entry.key: EntityPhoto(
            assetId: (entry.value['assetId'] as num).toInt(),
            url: entry.value['readUrl'] as String,
            fetchedAt: now,
          ),
    };
  }

  /// Stores [file] as [owner] [id]'s photo, replacing the one it had.
  Future<EntityPhoto> upload(String owner, String id, XFile file) async {
    final bytes = await file.readAsBytes();
    final contentType =
        lookupMimeType(file.name, headerBytes: bytes.take(24).toList()) ??
        'application/octet-stream';
    // Named for what it is, with an extension: a file handed over without a
    // name became a stored object nothing could tell was a picture.
    final named = file.name.trim();
    final extension = extensionFromMime(contentType) ?? 'png';
    final fileName = named.isEmpty
        ? 'photo.$extension'
        : (named.contains('.') ? named : '$named.$extension');
    if (useMockResponses) {
      final assetId = _mockIds++;
      // The picture every demo upload in the app shows.
      const url =
          'https://images.unsplash.com/photo-1550439062-609e1531270e?auto=format&fit=crop&q=80';
      _mock['$owner:$id'] = (assetId: assetId, url: url);
      return EntityPhoto(assetId: assetId, url: url, fetchedAt: DateTime.now());
    }
    final intent = await _post('/api/assets/upload-intent', {
      'uploadType': PhotoOwner.uploadTypeOf(owner),
      'entityType': owner,
      'entityId': int.tryParse(id) ?? id,
      'fileName': fileName,
      'contentType': contentType,
      'sizeBytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      // A new photo replaces the shown one.
      'isPrimary': true,
    });
    final body = intent['intent'] as Map<String, dynamic>? ?? const {};
    final existing = body['asset'] as Map<String, dynamic>?;
    if (body['alreadyUploaded'] == true && existing != null) {
      // The same picture again: make it the shown one.
      final id = (existing['id'] as num).toInt();
      final primary = await _send('PATCH', '/api/assets/$id/primary', null);
      return _photoFrom(primary['asset'] as Map<String, dynamic>? ?? existing);
    }
    final upload = body['upload'] as Map<String, dynamic>? ?? const {};
    final headers = {
      for (final entry
          in (upload['headers'] as Map<String, dynamic>? ?? const {}).entries)
        entry.key: '${entry.value}',
    };
    final put = await _uploadClient.put(
      Uri.parse(upload['uploadUrl'] as String? ?? ''),
      headers: headers,
      body: bytes,
    );
    if (put.statusCode < 200 || put.statusCode >= 300) {
      throw EntityPhotoException(_reason(put.body) ?? 'The upload was refused.');
    }
    final done = await _post('/api/assets/upload-complete', {
      'uploadSessionId': upload['uploadSessionId'],
      'objectKey': upload['objectKey'],
    });
    return _photoFrom(done['asset'] as Map<String, dynamic>? ?? const {});
  }

  Future<void> remove(String owner, String id, int assetId) async {
    if (useMockResponses) {
      _mock.remove('$owner:$id');
      return;
    }
    await _send('DELETE', '/api/assets/$assetId', null);
  }

  EntityPhoto _photoFrom(Map<String, dynamic> asset) {
    final url = asset['readUrl'] as String?;
    if (url == null || url.isEmpty) {
      throw const EntityPhotoException('The photo was stored but cannot be shown.');
    }
    return EntityPhoto(
      assetId: (asset['id'] as num).toInt(),
      url: url,
      fetchedAt: DateTime.now(),
    );
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) =>
      _send('POST', path, body);

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Content-Type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await _client.send(request));
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      payload = const {};
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] == false) {
      throw EntityPhotoException(
        payload['error'] as String? ??
            'The server answered ${response.statusCode}.',
      );
    }
    return payload;
  }

  static String? _reason(String body) {
    try {
      return (jsonDecode(body) as Map<String, dynamic>)['error'] as String?;
    } catch (_) {
      return null;
    }
  }
}

class EntityPhotoException implements Exception {
  const EntityPhotoException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Every photo on screen, fetched in batches and kept fresh.
///
/// A thumbnail asks for its own photo with [request]; the asks of one frame
/// go to the server as ONE request per kind of record — a table of fifty
/// parts is one round trip, not fifty. A signed URL lives five minutes, so a
/// photo older than [maxAge] is asked for again.
class EntityPhotosProvider extends ChangeNotifier {
  EntityPhotosProvider({
    required EntityPhotoRepository repository,
    this.maxAge = const Duration(minutes: 4),
  }) : _repository = repository;

  final EntityPhotoRepository _repository;
  final Duration maxAge;

  final Map<String, EntityPhoto> _photos = {};

  /// When each record was last asked about, photo or not — so a record with
  /// no photo is not asked about again on every rebuild.
  final Map<String, DateTime> _checkedAt = {};
  final Map<String, Set<String>> _pending = {};
  final Set<String> _busy = {};
  bool _flushScheduled = false;
  bool _disposed = false;

  static String _key(String owner, String id) => '$owner:$id';

  EntityPhoto? photoOf(String owner, String id) => _photos[_key(owner, id)];

  bool isBusy(String owner, String id) => _busy.contains(_key(owner, id));

  /// Asks for [owner] [id]'s photo unless it is known and fresh. Cheap: call
  /// it from build.
  void request(String owner, String id) {
    final checked = _checkedAt[_key(owner, id)];
    if (checked != null && DateTime.now().difference(checked) < maxAge) return;
    (_pending[owner] ??= <String>{}).add(id);
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(_flush);
  }

  Future<void> _flush() async {
    _flushScheduled = false;
    final batches = Map.of(_pending);
    _pending.clear();
    var changed = false;
    for (final entry in batches.entries) {
      final ids = entry.value.toList();
      final now = DateTime.now();
      for (final id in ids) {
        _checkedAt[_key(entry.key, id)] = now;
      }
      try {
        final found = await _repository.primaryPhotos(entry.key, ids);
        for (final id in ids) {
          final key = _key(entry.key, id);
          final photo = found[id];
          if (photo == null) {
            changed |= _photos.remove(key) != null;
          } else {
            _photos[key] = photo;
            changed = true;
          }
        }
      } catch (_) {
        // Not shown is the honest answer to "could not ask"; asked again
        // once [maxAge] passes.
      }
    }
    if (changed && !_disposed) notifyListeners();
  }

  /// Stores [file] as the photo. Answers why not, or null when it landed.
  Future<String?> upload(String owner, String id, XFile file) async {
    final key = _key(owner, id);
    _busy.add(key);
    notifyListeners();
    try {
      final photo = await _repository.upload(owner, id, file);
      _photos[key] = photo;
      _checkedAt[key] = photo.fetchedAt;
      return null;
    } catch (error) {
      return '$error';
    } finally {
      _busy.remove(key);
      if (!_disposed) notifyListeners();
    }
  }

  Future<String?> remove(String owner, String id) async {
    final key = _key(owner, id);
    final photo = _photos[key];
    if (photo == null) return null;
    _busy.add(key);
    notifyListeners();
    try {
      await _repository.remove(owner, id, photo.assetId);
      _photos.remove(key);
      // The server may promote an older photo; ask again.
      _checkedAt.remove(key);
      request(owner, id);
      return null;
    } catch (error) {
      return '$error';
    } finally {
      _busy.remove(key);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
