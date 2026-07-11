import '../annotations/feature_annotation.dart';
import 'dev_config.dart';

/// RULE: every user-facing feature/module ships behind a flag — nothing reaches
/// a client build ungated. To add one: declare an `@FeatureFlag` key here, gate
/// the feature with `FeatureFlags.isEnabled(...)`, then publish it to the
/// dashboard with `dart run bin/generate_registry.dart`. See CLAUDE.md.
///
/// Replacing a working flow? Use a SELECTOR flag (default off) and branch at the
/// flow's single entry point — add a new file, never edit the old one, so the
/// current flow keeps working. See CLAUDE.md → "Replacing a working flow".
class FeatureKeys {
  @FeatureFlag(category: 'Modules', displayName: 'Orders Module', desc: 'Enable the Orders module')
  static const String modulesOrders = 'modules.orders';

  @FeatureFlag(category: 'Modules', displayName: 'Masters & Catalogs', desc: 'Enable the Masters & Catalogs module')
  static const String modulesMasters = 'modules.masters';

  @FeatureFlag(category: 'Modules', displayName: 'Inventory Management', desc: 'Enable the Inventory Management module')
  static const String modulesInventory = 'modules.inventory';

  @FeatureFlag(category: 'Modules', displayName: 'Production & Runs', desc: 'Enable the Production & Runs module')
  static const String modulesProduction = 'modules.production';

  @FeatureFlag(category: 'Modules', displayName: 'Preventative Maintenance', desc: 'Enable the Preventative Maintenance module')
  static const String modulesPm = 'modules.pm';

  @FeatureFlag(category: 'Modules', displayName: 'Freelancer Jobs Portal', desc: 'Enable the Freelancer Jobs Portal')
  static const String modulesJobs = 'modules.jobs';

  @FeatureFlag(category: 'Modules', displayName: 'Delivery Challans', desc: 'Enable Delivery Challans')
  static const String modulesChallans = 'modules.delivery_challans';

  @FeatureFlag(category: 'Modules', displayName: 'Action Center', desc: 'Trash bin & broken-reference resolution center')
  static const String modulesActionCenter = 'modules.actionCenter';

  @FeatureFlag(category: 'Orders Screen', displayName: 'Allow Dynamic Actions Dropdown', desc: 'Show dynamic actions on orders')
  static const String ordersAllowCustomActions = 'orders.allowCustomActions';

  @FeatureFlag(category: 'Orders Screen', displayName: 'Allow Order Creation', desc: 'Allow creating new orders')
  static const String ordersAllowOrdersCreation = 'orders.allowOrdersCreation';

  @FeatureFlag(category: 'Orders Screen', displayName: 'Show Report', desc: 'Production report (quantities only, rates left blank) with print, on the order row menu')
  static const String ordersShowReport = 'orders.showReport';

  @FeatureFlag(category: 'Machine Form', displayName: 'Disable Machine Custom Fields', desc: 'Hide custom fields on Machine Creation')
  static const String featuresDisableMachineCustomFields = 'features.disableMachineCustomFields';

  @FeatureFlag(category: 'Pipeline Builder', displayName: 'Multiple Scrap Items per Stage', desc: 'Let a stage ship scrap to several items from the Scrap group instead of one')
  static const String pipelineMultiScrapItems = 'production.multiScrapItems';

  @FeatureFlag(category: 'Pipeline Builder', displayName: 'Material Variation Paths', desc: 'Pick the exact item variation path for stage input/output materials')
  static const String pipelineMaterialVariationPaths = 'production.materialVariationPaths';

  /// Master switch for the 2026 catalog & inventory enhancement bundle:
  /// group-scoped item selection in the order editor, combination groups for
  /// variant sets, measurable property values with unit assignment, the primary
  /// unit placeholder cleanup, and the inventory movement audit trail popup.
  /// OFF by default so every client keeps the current behaviour until enabled.
  @FeatureFlag(category: 'Catalog & Inventory', displayName: 'Catalog & Inventory Enhancements', desc: 'Group-scoped item picker, combination groups, measurable units, inventory audit trail')
  static const String catalogInventoryEnhancements = 'enhancements.catalogInventory';

  /// When ON, the Challans screen shows a type selector (All / Reception /
  /// Delivery) and picking a single type collapses the split Reception|Delivery
  /// view to that one type, full-width. OFF keeps the side-by-side layout.
  @FeatureFlag(category: 'Challans Screen', displayName: 'Single-type Challan View', desc: 'Show one challan type full-width instead of the split Reception/Delivery view')
  static const String challansSingleTypeView = 'challans.singleTypeView';

  /// Gates the purchase-catalog capability: shows the "Available for purchase"
  /// toggle in the desktop item editor, and (on mobile) the Purchase-challan
  /// browse flow that only lists purchase-available items. OFF by default.
  @FeatureFlag(category: 'Catalog & Inventory', displayName: 'Purchase Items', desc: 'Enable the "Available for purchase" item toggle and the mobile Purchase (reception) challan flow')
  static const String catalogPurchaseItems = 'catalog.purchaseItems';
}

class FeatureFlags {
  static Map<String, dynamic> _config = {};

  static void setConfig(Map<String, dynamic> config) {
    _config = config;
  }

  static bool isEnabled(String featureKey) {
    // Offline dev mode: dev_config.dart wins so hot reload toggles flags live.
    if (useDevConfig) {
      final dev = _getNestedProperty(devConfig, featureKey);
      if (dev is bool) return dev;
    }
    final val = _getNestedProperty(_config, featureKey);
    if (val is bool) {
      return val;
    }
    return false; // Default fallback if key not found in merged config
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
}
