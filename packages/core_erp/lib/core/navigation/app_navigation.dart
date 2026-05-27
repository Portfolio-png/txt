abstract class AppNavigation {
  void select(String key, {bool skipTransition = false});
}

class AppNavigationWrapper implements AppNavigation {
  final AppNavigation _navigation;
  AppNavigationWrapper(this._navigation);

  @override
  void select(String key, {bool skipTransition = false}) {
    _navigation.select(key, skipTransition: skipTransition);
  }
}
