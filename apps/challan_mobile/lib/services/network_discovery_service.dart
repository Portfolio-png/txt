import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart';

class NetworkDiscoveryService extends ChangeNotifier {
  static const String _serviceType = '_papererp._tcp';
  
  Discovery? _discovery;
  String? _discoveredUrl;
  bool _isSearching = false;
  bool _hasTimedOut = false;
  
  String? get discoveredUrl => _discoveredUrl;
  bool get isSearching => _isSearching;
  bool get hasTimedOut => _hasTimedOut;

  void manualConnect(String ipAddress) {
    if (ipAddress.startsWith('http://') || ipAddress.startsWith('https://')) {
      _discoveredUrl = ipAddress;
    } else {
      _discoveredUrl = 'http://$ipAddress:18080';
    }
    _isSearching = false;
    notifyListeners();
  }

  Future<void> discoverServer() async {
    if (_isSearching) return;
    
    _isSearching = true;
    _hasTimedOut = false;
    _discoveredUrl = null;
    notifyListeners();

    // 5 second timeout for mDNS
    Future.delayed(const Duration(seconds: 5), () {
      if (_isSearching && _discoveredUrl == null) {
        _hasTimedOut = true;
        _isSearching = false;
        notifyListeners();
        stopServerDiscovery();
      }
    });

    try {
      _discovery = await startDiscovery(_serviceType);
      _discovery!.addListener(() {
        for (final service in _discovery!.services) {
          if (service.host != null && service.port != null) {
            _discoveredUrl = 'http://${service.host}:${service.port}';
            _isSearching = false;
            notifyListeners();
            stopServerDiscovery();
            break;
          }
        }
      });
    } catch (e) {
      debugPrint('Error starting mDNS discovery: $e');
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> stopServerDiscovery() async {
    if (_discovery != null) {
      await stopDiscovery(_discovery!);
      _discovery = null;
    }
    _isSearching = false;
    notifyListeners();
  }
}
