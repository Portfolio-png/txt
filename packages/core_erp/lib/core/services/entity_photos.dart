import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import 'photo_shrink.dart';
import 'socket_service.dart';

/// What a photo can belong to. The server's `uploaded_assets.entity_type`.
abstract final class PhotoOwner {
  static const item = 'item';
  static const die = 'die';
  static const machine = 'machine';
  static const client = 'client';
  static const person = 'party_contact';

  /// A client's contractor. It keeps documents, not a photo slot of its own.
  static const subContractor = 'sub_contractor';

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
    this.thumbUrl,
    this.count = 1,
  });

  final int assetId;
  final String url;
  final DateTime fetchedAt;

  /// The small copy, for a slot in a list. Null for a photo stored before
  /// thumbnails: [url] is shown instead.
  final String? thumbUrl;

  /// How many photos the record keeps — a part keeps several views.
  final int count;

  /// What a small slot shows.
  String get smallUrl => thumbUrl ?? url;
}

/// One of a part's photos, as the gallery shows it. The links are permanent
/// (each leads to a fresh signed URL), so a picture fetched once is kept by
/// the image cache however often the gallery opens.
@immutable
class PartPhoto {
  const PartPhoto({
    required this.id,
    required this.thumbUrl,
    required this.viewUrl,
    this.isPrimary = false,
    this.position,
    this.width,
    this.height,
  });

  factory PartPhoto.fromJson(Map<String, dynamic> json) => PartPhoto(
    id: (json['id'] as num).toInt(),
    thumbUrl: json['thumbUrl'] as String? ?? json['viewUrl'] as String? ?? '',
    viewUrl: json['viewUrl'] as String? ?? '',
    isPrimary: json['isPrimary'] == true,
    position: (json['position'] as num?)?.toInt(),
    width: (json['width'] as num?)?.toInt(),
    height: (json['height'] as num?)?.toInt(),
  );

  final int id;
  final String thumbUrl;
  final String viewUrl;
  final bool isPrimary;
  final int? position;
  final int? width;
  final int? height;

  PartPhoto copyWith({bool? isPrimary, int? position}) => PartPhoto(
    id: id,
    thumbUrl: thumbUrl,
    viewUrl: viewUrl,
    isPrimary: isPrimary ?? this.isPrimary,
    position: position ?? this.position,
    width: width,
    height: height,
  );
}

/// How many photos a part keeps. The server holds the same line.
const int maxPartPhotos = 5;

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

  /// Demo mode's photos of each part, in order.
  final Map<String, List<PartPhoto>> _mockGallery = {};

  /// Demo mode's picture, for every upload in the app.
  static const _mockUrl =
      'https://images.unsplash.com/photo-1550439062-609e1531270e?auto=format&fit=crop&q=80';

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
            thumbUrl: entry.value['thumbReadUrl'] as String?,
            count: (entry.value['count'] as num?)?.toInt() ?? 1,
            fetchedAt: now,
          ),
    };
  }

  /// [itemId]'s photos, first to last — one request for the whole gallery.
  Future<List<PartPhoto>> partPhotos(String itemId) async {
    if (useMockResponses) return List.of(_mockGallery[itemId] ?? const []);
    final payload = await _send('GET', '/api/items/$itemId/photos', null);
    return [
      for (final row in payload['photos'] as List<dynamic>? ?? const [])
        if (row is Map<String, dynamic>) PartPhoto.fromJson(row),
    ];
  }

  /// The gallery's Save: the photos in [order], [primaryId] the main one.
  /// Answers the photos as the server now keeps them.
  Future<List<PartPhoto>> arrangePartPhotos(
    String itemId, {
    required List<int> order,
    int? primaryId,
  }) async {
    if (useMockResponses) {
      final photos = _mockGallery[itemId] ?? const <PartPhoto>[];
      final byId = {for (final photo in photos) photo.id: photo};
      final ids = [...order, ...photos.map((p) => p.id).where((id) => !order.contains(id))];
      final primary = primaryId ?? photos.where((p) => p.isPrimary).firstOrNull?.id;
      final arranged = [
        for (final (index, id) in ids.indexed)
          if (byId[id] case final photo?)
            photo.copyWith(position: index + 1, isPrimary: id == primary),
      ];
      _mockGallery[itemId] = arranged;
      if (arranged.where((p) => p.isPrimary).firstOrNull case final main?) {
        _mock['${PhotoOwner.item}:$itemId'] = (assetId: main.id, url: _mockUrl);
      }
      return List.of(arranged);
    }
    final payload = await _send('PUT', '/api/items/$itemId/photos', {
      'order': order,
      'primaryId': ?primaryId,
    });
    return [
      for (final row in payload['photos'] as List<dynamic>? ?? const [])
        if (row is Map<String, dynamic>) PartPhoto.fromJson(row),
    ];
  }

  /// The documents stored in demo mode, oldest first.
  @visibleForTesting
  final List<({String owner, String id, String title, int assetId})> mockDocuments = [];

  /// Stores [file] as [owner] [id]'s photo — the shown one, unless
  /// [isPrimary] is false (one more of a part's views).
  Future<EntityPhoto> upload(
    String owner,
    String id,
    XFile file, {
    bool isPrimary = true,
  }) async => _photoFrom(await store(owner, id, file, isPrimary: isPrimary));

  /// Stores [file] on [owner] [id] and answers the server's asset. Without
  /// [documentTitle] it is one of the record's photos — shrunk first, and
  /// sent with a thumbnail — and the shown one when [isPrimary]; with one it
  /// is a document of the company under that name — any kind of file, sent
  /// as it is, and never its picture.
  Future<Map<String, dynamic>> store(
    String owner,
    String id,
    XFile file, {
    String? documentTitle,
    bool isPrimary = true,
  }) async {
    final isDocument = documentTitle != null;
    if (useMockResponses) {
      final assetId = _mockIds++;
      if (isDocument) {
        mockDocuments.add((owner: owner, id: id, title: documentTitle, assetId: assetId));
        return {'id': assetId, 'documentTitle': documentTitle, 'fileName': file.name};
      }
      if (owner == PhotoOwner.item) {
        final gallery = _mockGallery[id] ??= [];
        if (gallery.length >= maxPartPhotos) {
          throw const EntityPhotoException(
            'A part keeps up to $maxPartPhotos photos — remove one first.',
            code: 'photo_limit',
          );
        }
        final main = isPrimary || gallery.isEmpty;
        if (main) {
          for (final (index, photo) in gallery.indexed) {
            gallery[index] = photo.copyWith(isPrimary: false);
          }
        }
        gallery.add(PartPhoto(
          id: assetId,
          thumbUrl: _mockUrl,
          viewUrl: _mockUrl,
          isPrimary: main,
          position: gallery.length + 1,
        ));
        if (!main) return {'id': assetId, 'readUrl': _mockUrl};
      }
      _mock['$owner:$id'] = (assetId: assetId, url: _mockUrl);
      return {'id': assetId, 'readUrl': _mockUrl};
    }
    var bytes = await file.readAsBytes();
    var contentType =
        lookupMimeType(file.name, headerBytes: bytes.take(24).toList()) ??
        'application/octet-stream';
    // A photo is shrunk to what a screen needs, with a small copy for lists:
    // a few hundred KB stored and sent instead of a phone's 3–8 MB.
    final shrunk = isDocument ? null : await shrinkPhoto(bytes, contentType: contentType);
    if (shrunk != null) {
      bytes = shrunk.photo;
      contentType = shrunk.contentType;
    }
    // Named for what it is, with an extension: a file handed over without a
    // name became a stored object nothing could tell was a picture.
    final named = file.name.trim();
    final extension =
        extensionFromMime(contentType) ?? (isDocument ? 'bin' : 'png');
    final stem = named.contains('.') ? named.substring(0, named.lastIndexOf('.')) : named;
    final fileName = named.isEmpty
        ? '${isDocument ? 'document' : 'photo'}.$extension'
        // A shrunk photo is a JPEG whatever it came as.
        : shrunk != null
        ? '${stem.isEmpty ? 'photo' : stem}.jpg'
        : (named.contains('.') ? named : '$named.$extension');
    final intent = await _post('/api/assets/upload-intent', {
      'uploadType': isDocument ? 'PARTY_DOCUMENT' : PhotoOwner.uploadTypeOf(owner),
      'entityType': owner,
      'entityId': int.tryParse(id) ?? id,
      'fileName': fileName,
      'contentType': contentType,
      'sizeBytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      if (isDocument)
        'documentTitle': documentTitle
      else
        'isPrimary': isPrimary,
      if (shrunk != null) ...{
        'thumbnail': {
          'sizeBytes': shrunk.thumb.length,
          'sha256': sha256.convert(shrunk.thumb).toString(),
        },
        'width': shrunk.width,
        'height': shrunk.height,
      },
    });
    final body = intent['intent'] as Map<String, dynamic>? ?? const {};
    final existing = body['asset'] as Map<String, dynamic>?;
    if (body['alreadyUploaded'] == true && existing != null) {
      // The same document under the same name is the one already there; the
      // same picture as one more view is the view already there.
      if (isDocument || !isPrimary) return existing;
      // The same picture again: make it the shown one.
      final id = (existing['id'] as num).toInt();
      final primary = await _send('PATCH', '/api/assets/$id/primary', null);
      return primary['asset'] as Map<String, dynamic>? ?? existing;
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
    final thumbSlot = upload['thumbnail'] as Map<String, dynamic>?;
    if (shrunk != null && thumbSlot != null) {
      final thumbPut = await _uploadClient.put(
        Uri.parse(thumbSlot['uploadUrl'] as String? ?? ''),
        headers: {
          for (final entry
              in (thumbSlot['headers'] as Map<String, dynamic>? ?? const {}).entries)
            entry.key: '${entry.value}',
        },
        body: shrunk.thumb,
      );
      if (thumbPut.statusCode < 200 || thumbPut.statusCode >= 300) {
        throw EntityPhotoException(_reason(thumbPut.body) ?? 'The thumbnail was refused.');
      }
    }
    final done = await _post('/api/assets/upload-complete', {
      'uploadSessionId': upload['uploadSessionId'],
      'objectKey': upload['objectKey'],
    });
    return done['asset'] as Map<String, dynamic>? ?? const {};
  }

  Future<void> remove(String owner, String id, int assetId) async {
    if (useMockResponses) {
      final gallery = _mockGallery[id];
      if (owner == PhotoOwner.item && gallery != null) {
        final wasMain = gallery.any((p) => p.id == assetId && p.isPrimary);
        gallery.removeWhere((p) => p.id == assetId);
        for (final (index, photo) in gallery.indexed) {
          gallery[index] = photo.copyWith(
            position: index + 1,
            isPrimary: photo.isPrimary || (wasMain && index == 0),
          );
        }
        if (gallery.isNotEmpty) {
          _mock['$owner:$id'] = (assetId: gallery.firstWhere((p) => p.isPrimary).id, url: _mockUrl);
          return;
        }
      }
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
        code: payload['code'] as String?,
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

/// A photo in an open gallery: one the part keeps, or one picked on this PC
/// and held here until Save.
sealed class GalleryPhoto {
  const GalleryPhoto();
}

final class StoredGalleryPhoto extends GalleryPhoto {
  const StoredGalleryPhoto(this.photo, {this.fromPhone = false});
  final PartPhoto photo;

  /// It arrived from the phone while the gallery was open.
  final bool fromPhone;
}

final class StagedGalleryPhoto extends GalleryPhoto {
  StagedGalleryPhoto(this.file, this.bytes);
  final XFile file;

  /// Shown from memory: nothing is uploaded until Save.
  final Uint8List bytes;
}

class EntityPhotoException implements Exception {
  const EntityPhotoException(this.message, {this.code});
  final String message;

  /// The server's reason, when it gave one: `photo_limit`.
  final String? code;

  @override
  String toString() => message;
}

/// Every photo on screen, fetched in batches and kept fresh.
///
/// A thumbnail asks for its own photo with [request]; the asks of one frame
/// go to the server as ONE request per kind of record — a table of fifty
/// parts is one round trip, not fifty. A signed URL lives five minutes, so a
/// photo older than [maxAge] is asked for again.
///
/// A photo stored anywhere else — the phone, another desktop — arrives as the
/// server's `asset_changed`, which drops that record here so its slot asks
/// again. Before it, a photo taken on the phone stayed invisible for up to
/// [maxAge].
class EntityPhotosProvider extends ChangeNotifier {
  EntityPhotosProvider({
    required EntityPhotoRepository repository,
    this.maxAge = const Duration(minutes: 4),
    bool listen = true,
  }) : _repository = repository,
       _listening = listen {
    if (listen) SocketService.instance.on('asset_changed', _onAssetChanged);
  }

  final EntityPhotoRepository _repository;
  final Duration maxAge;
  final bool _listening;

  void _onAssetChanged(dynamic data) {
    if (data is! Map) return;
    final owner = '${data['entityType'] ?? ''}';
    final id = '${data['entityId'] ?? ''}';
    if (owner.isEmpty || id.isEmpty) return;
    _bump(owner, id);
    forget(owner, id);
  }

  final Map<String, int> _revisions = {};

  /// Goes up each time [owner] [id]'s photos change anywhere — a shot from
  /// the phone, another desktop, a save here. An open gallery reads it to
  /// know when to look again.
  int revisionOf(String owner, String id) => _revisions[_key(owner, id)] ?? 0;

  void _bump(String owner, String id) {
    final key = _key(owner, id);
    _revisions[key] = (_revisions[key] ?? 0) + 1;
    if (!_disposed) notifyListeners();
  }

  /// [itemId]'s photos, first to last.
  Future<List<PartPhoto>> partPhotos(String itemId) => _repository.partPhotos(itemId);

  /// The gallery's Save, in the order that keeps a part under its limit:
  /// [removed] first, then each new photo of [order] uploaded (shrunk, as one
  /// more view), then one request for the order and [main]. Answers why not,
  /// or null when all of it landed.
  Future<String?> saveGallery(
    String itemId, {
    required List<int> removed,
    required List<GalleryPhoto> order,
    required GalleryPhoto? main,
  }) async {
    const owner = PhotoOwner.item;
    final key = _key(owner, itemId);
    _busy.add(key);
    notifyListeners();
    try {
      for (final assetId in removed) {
        await _repository.remove(owner, itemId, assetId);
      }
      final ids = <int>[];
      int? mainId;
      for (final photo in order) {
        final int id;
        switch (photo) {
          case StoredGalleryPhoto(:final photo):
            id = photo.id;
          case StagedGalleryPhoto(:final file):
            final asset = await _repository.store(owner, itemId, file, isPrimary: false);
            id = (asset['id'] as num).toInt();
        }
        // The same picture picked twice is stored once.
        if (!ids.contains(id)) ids.add(id);
        if (identical(photo, main)) mainId = id;
      }
      if (ids.isNotEmpty) {
        await _repository.arrangePartPhotos(itemId, order: ids, primaryId: mainId);
      }
      return null;
    } catch (error) {
      return '$error';
    } finally {
      _busy.remove(key);
      _bump(owner, itemId);
      _checkedAt.remove(key);
      request(owner, itemId);
    }
  }

  /// Drops what is known about [owner] [id] and asks again, if anything on
  /// screen had asked about it.
  void forget(String owner, String id) {
    final key = _key(owner, id);
    if (_checkedAt.remove(key) == null) return;
    request(owner, id);
  }

  final Map<String, EntityPhoto> _photos = {};

  /// A signed read URL lives an hour; one is reused for most of it.
  static const _keepUrlFor = Duration(minutes: 50);

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
          final old = _photos[key];
          if (photo == null) {
            changed |= _photos.remove(key) != null;
          } else if (old != null &&
              old.assetId == photo.assetId &&
              now.difference(old.fetchedAt) < _keepUrlFor) {
            // The same photo: its URL is kept while it still works, so the
            // image cache answers and nothing is downloaded again.
            if (old.count != photo.count) {
              _photos[key] = EntityPhoto(
                assetId: old.assetId,
                url: old.url,
                thumbUrl: old.thumbUrl,
                count: photo.count,
                fetchedAt: old.fetchedAt,
              );
              changed = true;
            }
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
    if (_listening) SocketService.instance.off('asset_changed', _onAssetChanged);
    super.dispose();
  }
}
