import 'package:flutter/foundation.dart';
import '../../core/services/config_service.dart';

class PreferencesProvider extends ChangeNotifier {
  bool get maintainStocks => ConfigService.instance.isModuleEnabled('inventory');
  bool get enableTrading => ConfigService.instance.isModuleEnabled('trading');
  bool get enableManufacturing => ConfigService.instance.isModuleEnabled('production');
  bool get enableServiceMode => ConfigService.instance.isModuleEnabled('jobs');

  void toggleMaintainStocks(bool value) {
    // Cannot toggle locally anymore, controlled by remote config
    notifyListeners();
  }

  void toggleTrading(bool value) {
    notifyListeners();
  }

  void toggleManufacturing(bool value) {
    notifyListeners();
  }

  void toggleServiceMode(bool value) {
    notifyListeners();
  }
}
