import 'package:core_erp/features/auth/domain/auth_user.dart';
import 'package:core_erp/features/auth/domain/track_event.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/auth/presentation/widgets/my_account_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Your own Account & Access, from the profile chip: the same panel People
// shows for a person, about whoever is signed in.

class _Me extends AuthProvider {
  _Me(this._user) : super(baseUrl: 'http://x');

  final AuthUser _user;
  final List<(String, String)> passwordChanges = [];
  final List<String> signedOut = [];
  bool refusePassword = false;
  List<AuthSession> sessions = [];

  @override
  AuthUser? get user => _user;

  @override
  Future<bool> changeOwnPassword({required String currentPassword, required String newPassword}) async {
    if (refusePassword) return false;
    passwordChanges.add((currentPassword, newPassword));
    return true;
  }

  @override
  String? get errorMessage => refusePassword ? 'Current password is incorrect.' : null;

  @override
  Future<({List<AuthSession> sessions, String? currentId})?> loadMySessions() async =>
      (sessions: List.of(sessions), currentId: 'here');

  @override
  Future<bool> revokeOwnSession(String sessionId) async {
    signedOut.add(sessionId);
    sessions = [for (final s in sessions) if (s.id != sessionId) s];
    return true;
  }

  @override
  Future<List<TrackEvent>> getActorTrack(int userId) async => const [];
}

AuthSession _session(String id, String platform) => AuthSession(
      id: id,
      userId: 7,
      createdAt: DateTime(2026, 10, 30, 9, 30),
      lastUsedAt: DateTime(2026, 10, 30, 10),
      expiresAt: DateTime.now().add(const Duration(hours: 4)),
      revokedAt: null,
      revokedReason: '',
      ipAddress: '192.168.1.20',
      userAgent: 'Dart',
      clientPlatform: platform,
    );

void main() {
  const staff = AuthUser(
    id: 7,
    name: 'Anil Manjre',
    email: 'a@b.c',
    role: 'user',
    permissions: ['login.desktop', 'login.mobile', 'items.read', 'items.update', 'dies.read'],
    isActive: true,
    mobilePin: '1703',
  );

  Future<_Me> open(WidgetTester tester, AuthUser user) async {
    final me = _Me(user);
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: me,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => MyAccountDialog.open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return me;
  }

  testWidgets('the account card is yours: email, PIN, access', (tester) async {
    await open(tester, staff);
    expect(find.text('Account & Access'), findsOneWidget);
    expect(find.text('Manage your login, access, and security.'), findsOneWidget);
    expect(find.text('a@b.c'), findsOneWidget);
    expect(find.text('Anil Manjre · Staff'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('PIN 1703'), findsOneWidget);
    expect(find.text('Desktop Access'), findsOneWidget);
    expect(find.text('Mobile Access'), findsOneWidget);
    expect(find.text('Everything you have changed across the app.'), findsOneWidget);
  });

  testWidgets('what only another admin may do is there, disabled, saying why', (tester) async {
    await open(tester, staff);
    for (final (label, why) in [
      ('Deactivate login', 'deactivate your own login'),
      ('Unlink login', 'unlink your own login'),
      ('Delete account', 'delete your own account'),
    ]) {
      expect(find.text(label), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').contains(why)), findsOneWidget);
    }
  });

  testWidgets('change password asks for the current one and checks the new twice', (tester) async {
    final me = await open(tester, staff);
    await tester.tap(find.byKey(const ValueKey<String>('my-account-password')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey<String>('my-password-current')), 'Old12345x');
    await tester.enterText(find.byKey(const ValueKey<String>('my-password-new')), 'New12345x');
    await tester.enterText(find.byKey(const ValueKey<String>('my-password-again')), 'Different1');
    await tester.tap(find.byKey(const ValueKey<String>('my-password-save')));
    await tester.pumpAndSettle();
    expect(find.text('The two new passwords are not the same.'), findsOneWidget);
    expect(me.passwordChanges, isEmpty);

    // The server says no: its reason is shown, the dialog stays.
    me.refusePassword = true;
    await tester.enterText(find.byKey(const ValueKey<String>('my-password-again')), 'New12345x');
    await tester.tap(find.byKey(const ValueKey<String>('my-password-save')));
    await tester.pumpAndSettle();
    expect(find.text('Current password is incorrect.'), findsOneWidget);

    me.refusePassword = false;
    await tester.tap(find.byKey(const ValueKey<String>('my-password-save')));
    await tester.pumpAndSettle();
    expect(me.passwordChanges, [('Old12345x', 'New12345x')]);
    expect(find.byKey(const ValueKey<String>('my-password-current')), findsNothing);
  });

  testWidgets('sessions: which device, this one marked, others signed out', (tester) async {
    final me = await open(tester, staff);
    me.sessions = [_session('here', 'desktop'), _session('phone', 'mobile'), _session('old-pc', 'desktop')];
    await tester.tap(find.byKey(const ValueKey<String>('my-account-sessions')));
    await tester.pumpAndSettle();

    expect(find.text('Desktop · this device'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('my-session-signout-here')), findsNothing,
        reason: 'this device is not offered for sign-out');

    await tester.tap(find.byKey(const ValueKey<String>('my-session-signout-phone')));
    await tester.pumpAndSettle();
    expect(me.signedOut, ['phone']);
    expect(find.text('Phone'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('my-sessions-signout-others')));
    await tester.pumpAndSettle();
    expect(me.signedOut, ['phone', 'old-pc']);
  });

  testWidgets('permissions are shown by module, read-only', (tester) async {
    await open(tester, staff);
    await tester.tap(find.byKey(const ValueKey<String>('my-account-permissions')));
    await tester.pumpAndSettle();
    expect(find.text('Items  View · Update'), findsOneWidget);
    expect(find.text('Dies  View'), findsOneWidget);
    expect(find.text('Login  Desktop · Mobile'), findsOneWidget);
  });

  testWidgets('a super admin reads "everything"', (tester) async {
    await open(
      tester,
      const AuthUser(id: 1, name: 'Super Admin', email: 'super@paper.local', role: 'super_admin', permissions: [], isActive: true),
    );
    expect(find.text('Super Admin · Super Admin'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('my-account-permissions')));
    await tester.pumpAndSettle();
    expect(find.text('Everything — you are the super admin.'), findsOneWidget);
  });
}
