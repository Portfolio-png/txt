enum FeatureKey {
  modulesOrders('modules.orders', 'Orders Module', 'Modules', 'Enable the Orders module'),
  modulesMasters('modules.masters', 'Masters & Catalogs', 'Modules', 'Enable the Masters & Catalogs module'),
  modulesInventory('modules.inventory', 'Inventory Management', 'Modules', 'Enable the Inventory Management module'),
  modulesProduction('modules.production', 'Production & Runs', 'Modules', 'Enable the Production & Runs module'),
  modulesPm('modules.pm', 'Preventative Maintenance', 'Modules', 'Enable the Preventative Maintenance module'),
  modulesJobs('modules.jobs', 'Freelancer Jobs Portal', 'Modules', 'Enable the Freelancer Jobs Portal'),
  modulesChallans('modules.delivery_challans', 'Delivery Challans', 'Modules', 'Enable Delivery Challans'),
  ordersAllowCustomActions('orders.allowCustomActions', 'Allow Dynamic Actions Dropdown', 'Orders Screen', 'Show dynamic actions on orders'),
  ordersAllowOrdersCreation('orders.allowOrdersCreation', 'Allow Order Creation', 'Orders Screen', 'Allow creating new orders'),
  featuresDisableMachineCustomFields('features.disableMachineCustomFields', 'Disable Machine Custom Fields', 'Machine Form', 'Hide custom fields on Machine Creation');

  final String key;
  final String displayName;
  final String category;
  final String description;

  const FeatureKey(this.key, this.displayName, this.category, this.description);
}

class FeatureFlags {
  static Map<String, dynamic> _config = {};

  static void setConfig(Map<String, dynamic> config) {
    _config = config;
  }

  static bool isEnabled(FeatureKey feature) {
    final val = _getNestedProperty(_config, feature.key);
    if (val is bool) {
      return val;
    }
    return _getDefaultValue(feature);
  }

  static dynamic _getNestedProperty(Map<String, dynamic> config, String path) {
    final keys = path.split('.');
    dynamic current = config;
    for (final key in keys) {
      if (current is Map<String, dynamic> && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  static bool _getDefaultValue(FeatureKey feature) {
    switch (feature) {
      case FeatureKey.modulesOrders:
      case FeatureKey.modulesMasters:
        return true;
      case FeatureKey.modulesInventory:
      case FeatureKey.modulesProduction:
      case FeatureKey.modulesPm:
      case FeatureKey.modulesJobs:
      case FeatureKey.modulesChallans:
        return false;
      case FeatureKey.ordersAllowCustomActions:
      case FeatureKey.ordersAllowOrdersCreation:
        return true;
      case FeatureKey.featuresDisableMachineCustomFields:
        return false;
    }
  }
}
