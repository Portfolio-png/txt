import 'package:flutter/foundation.dart';

import '../../../../core/services/socket_service.dart';

import '../../data/die_maker_repository.dart';
import '../../domain/die_maker.dart';

/// Holds the die maker master.
///
/// Small and rarely edited, so it is loaded once and kept. [ensureLoaded] is
/// the entry point rather than a bare `load`, because the one screen that
/// needs it — the die sheet's "made by" picker — is reached long before
/// anybody opens a die makers screen, and a picker that is empty because
/// nothing fetched is indistinguishable from one that is empty because the
/// shop has no die makers. That exact failure already happened once with
/// materials on the item sheet.
class DieMakersProvider extends ChangeNotifier {
  DieMakersProvider({required DieMakerRepository repository})
      : _repository = repository {
    SocketService.instance.on('die_makers_changed', _onRemoteChange);
  }

  /// A maker added, renamed or archived in another window — the die sheet's
  /// picker kept the list it first loaded until the app restarted.
  void _onRemoteChange(dynamic _) {
    if (_initialized && !_isLoading) refresh();
  }

  @override
  void dispose() {
    SocketService.instance.off('die_makers_changed', _onRemoteChange);
    super.dispose();
  }

  final DieMakerRepository _repository;

  List<DieMaker> _dieMakers = const [];
  bool _isLoading = false;
  bool _initialized = false;
  String? _errorMessage;

  List<DieMaker> get dieMakers => _dieMakers;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// The ones a picker should offer — archived makers are not choices.
  List<DieMaker> get selectable =>
      [for (final maker in _dieMakers) if (!maker.isArchived) maker];

  DieMaker? byId(int? id) {
    if (id == null) return null;
    for (final maker in _dieMakers) {
      if (maker.id == id) return maker;
    }
    return null;
  }

  /// The maker that answers to [name], or null.
  ///
  /// Case-insensitive because the unique index is, so "Sharma Tools" and
  /// "sharma tools" must resolve to the same record here too — otherwise the
  /// picker offers to create one the server will then refuse.
  DieMaker? byName(String? name) {
    final needle = (name ?? '').trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final maker in _dieMakers) {
      if (maker.name.trim().toLowerCase() == needle) return maker;
    }
    return null;
  }

  Future<void> ensureLoaded() async {
    if (_initialized || _isLoading) return;
    await refresh();
  }

  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _dieMakers = await _repository.list();
      _initialized = true;
    } on DieMakerException catch (error) {
      _errorMessage = error.message;
    } catch (error) {
      _errorMessage = '$error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Creates one and returns it, or null with [errorMessage] set.
  ///
  /// A duplicate name answers with the maker that already holds it rather than
  /// null: the caller asked for "a die maker called X" and there is one, so
  /// handing it back is the answer to the question that was asked.
  Future<DieMaker?> create(DieMakerInput input) async {
    _errorMessage = null;
    try {
      final made = await _repository.create(input);
      _dieMakers = [..._dieMakers, made]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      notifyListeners();
      return made;
    } on DieMakerException catch (error) {
      if (error.isDuplicate && error.existingId != null) {
        final existing = byId(error.existingId);
        if (existing != null) return existing;
        // Not in the active list, so it is archived: the name was asked for
        // again, so it comes back rather than leaving the name blocked with
        // nothing anyone can pick.
        final restored = await _restore(error.existingId!);
        if (restored != null) return restored;
      }
      _errorMessage = error.message;
      notifyListeners();
      return null;
    } catch (error) {
      _errorMessage = '$error';
      notifyListeners();
      return null;
    }
  }

  Future<DieMaker?> _restore(int id) async {
    try {
      final saved = await _repository.update(
        DieMakerInput(id: id, isArchived: false),
      );
      _dieMakers = [..._dieMakers.where((m) => m.id != saved.id), saved]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      notifyListeners();
      return saved;
    } catch (_) {
      return null;
    }
  }

  Future<DieMaker?> update(DieMakerInput input) async {
    _errorMessage = null;
    try {
      final saved = await _repository.update(input);
      _dieMakers = [
        for (final maker in _dieMakers)
          if (maker.id == saved.id) saved else maker,
      ];
      notifyListeners();
      return saved;
    } on DieMakerException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return null;
    } catch (error) {
      _errorMessage = '$error';
      notifyListeners();
      return null;
    }
  }

  /// Answers whether it was archived rather than deleted, so the caller can
  /// say which happened.
  Future<bool?> remove(int id) async {
    _errorMessage = null;
    try {
      final archived = await _repository.remove(id);
      await refresh();
      return archived;
    } on DieMakerException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return null;
    } catch (error) {
      // A dropped connection or an HTML error page escaped to the caller
      // here, where create and update already caught it.
      _errorMessage = '$error';
      notifyListeners();
      return null;
    }
  }
}
