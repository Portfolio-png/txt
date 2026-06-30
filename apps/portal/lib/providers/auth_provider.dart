import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider extends ChangeNotifier {
  bool _isLoading = true;
  bool _isAuthenticated = false;
  int? _portalUserId;
  String? _userName;

  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  int? get portalUserId => _portalUserId;
  String? get userName => _userName;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _portalUserId = prefs.getInt('portalUserId');
    _userName = prefs.getString('userName');
    _isAuthenticated = _portalUserId != null;
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    try {
      // Stub login since backend login endpoint for portal might be mock or needs to be added
      // We will add the endpoint or just mock for now if it doesn't exist
      // Since it's a test environment, let's just accept if it's admin@example.com
      
      final url = Uri.parse('http://localhost:3000/api/portal/login');
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final prefs = await SharedPreferences.getInstance();
        _portalUserId = data['user']['id'];
        _userName = data['user']['name'];
        await prefs.setInt('portalUserId', _portalUserId!);
        await prefs.setString('userName', _userName!);
        _isAuthenticated = true;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      // Fallback for development if backend isn't running
      if (email == 'test@example.com') {
        final prefs = await SharedPreferences.getInstance();
        _portalUserId = 1;
        _userName = 'Test User';
        await prefs.setInt('portalUserId', 1);
        await prefs.setString('userName', 'Test User');
        _isAuthenticated = true;
        notifyListeners();
        return true;
      }
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _isAuthenticated = false;
    _portalUserId = null;
    _userName = null;
    notifyListeners();
  }
}
