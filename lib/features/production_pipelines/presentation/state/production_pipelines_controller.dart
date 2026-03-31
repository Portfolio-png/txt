import 'package:flutter/material.dart';

import '../../data/mock_production_pipelines_data.dart';
import '../../domain/models/aging_row.dart';
import 'production_pipelines_state.dart';

class ProductionPipelinesController extends ChangeNotifier {
  ProductionPipelinesController()
    : _state = ProductionPipelinesState(
        selectedSidebarKey: 'production_pipelines',
        selectedFilters: const {
          'Party': kAllValue,
          'Group': kAllValue,
          'Outstanding': kAllValue,
          'Status': kAllValue,
        },
        selectedRowIds: <String>{},
        selectedSummaryCardId: null,
        sortBy: 'partyName',
        sortAscending: true,
        summaryCards: MockProductionPipelinesData.summaryCards,
        rows: MockProductionPipelinesData.rows,
      );

  ProductionPipelinesState _state;

  ProductionPipelinesState get state => _state;

  List<SummaryMetric> get summaryCards => _state.summaryCards;

  int get selectedCount => _state.selectedRowIds.length;

  List<AgingRow> get visibleRows {
    var rows = _state.rows;

    final selectedParty = _state.selectedFilters['Party'];
    if (selectedParty != null && selectedParty != kAllValue) {
      rows = rows.where((row) => row.partyName == selectedParty).toList();
    }

    final selectedOutstanding = _state.selectedFilters['Outstanding'];
    if (selectedOutstanding != null && selectedOutstanding != kAllValue) {
      rows = switch (selectedOutstanding) {
        '0-30' => rows.where((row) => row.bucket0To30 > 0).toList(),
        '31-60' => rows.where((row) => row.bucket31To60 > 0).toList(),
        '61-90' => rows.where((row) => row.bucket61To90 > 0).toList(),
        '>90' => rows.where((row) => row.bucketOver90 > 0).toList(),
        _ => rows,
      };
    }

    final sortedRows = [...rows];
    sortedRows.sort((a, b) {
      final int result = switch (_state.sortBy) {
        'totalOutstanding' => a.totalOutstanding.compareTo(b.totalOutstanding),
        _ => a.partyName.compareTo(b.partyName),
      };

      return _state.sortAscending ? result : -result;
    });

    return sortedRows;
  }

  bool isSelected(String id) => _state.selectedRowIds.contains(id);

  void setSidebar(String key) {
    _state = _state.copyWith(selectedSidebarKey: key);
    notifyListeners();
  }

  void setFilter(String name, String value) {
    final updatedFilters = Map<String, String>.from(_state.selectedFilters)
      ..[name] = value;

    _state = _state.copyWith(selectedFilters: updatedFilters);
    notifyListeners();
  }

  void toggleRowSelection(String id) {
    final updatedSelection = Set<String>.from(_state.selectedRowIds);
    if (!updatedSelection.add(id)) {
      updatedSelection.remove(id);
    }

    _state = _state.copyWith(selectedRowIds: updatedSelection);
    notifyListeners();
  }

  void clearSelection() {
    _state = _state.copyWith(selectedRowIds: <String>{});
    notifyListeners();
  }

  void setSort(String key, {required bool ascending}) {
    _state = _state.copyWith(sortBy: key, sortAscending: ascending);
    notifyListeners();
  }

  void toggleSortBy(String key) {
    if (_state.sortBy == key) {
      setSort(key, ascending: !_state.sortAscending);
      return;
    }

    setSort(key, ascending: true);
  }

  void toggleSummaryCard(String cardId) {
    final nextId = _state.selectedSummaryCardId == cardId ? null : cardId;
    _state = _state.copyWith(selectedSummaryCardId: nextId);
    notifyListeners();
  }
}
