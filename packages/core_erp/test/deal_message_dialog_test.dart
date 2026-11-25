import 'package:core_erp/features/items/presentation/widgets/deal_message_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The draft to whoever a deal was done with (owner, 2026-11-25): To and From,
/// the words from the deal, Send — and Email / WhatsApp to switch between.

const _deal = DealMessageContext(
  personName: 'Ravi Shah',
  email: 'ravi@goldmedal.in',
  phone: '98200 12345',
  theirCompany: 'Gold Medal',
  partName: 'Patti No. 1',
  partCode: 'SADP48',
  quotation: '85000',
  fromName: 'Rutu',
  fromEmail: 'rutu@example.test',
  ourCompany: 'Sarvadnya Udyog',
);

Future<List<Uri>> _open(WidgetTester tester, {DealMessageContext deal = _deal, bool opens = true}) async {
  tester.view.physicalSize = const Size(1400, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final launched = <Uri>[];
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => DealMessageDialog.open(
              context,
              message: deal,
              launcher: (uri) async {
                launched.add(uri);
                return opens;
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return launched;
}

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey<String>('deal-message-$key'))).controller!.text;

void main() {
  test('the sample words come from the deal', () {
    expect(DealMessageDraft.subject(_deal), 'Quotation for Patti No. 1');
    final body = DealMessageDraft.email(_deal);
    expect(body, startsWith('Dear Ravi,'));
    expect(body, contains('Patti No. 1 (SADP48)'));
    expect(body, contains('Quotation: ₹85000'));
    expect(body, endsWith('Rutu\nSarvadnya Udyog'));
    expect(DealMessageDraft.whatsapp(_deal), contains('Our quotation for Patti No. 1 (SADP48) is ₹85000.'));
    expect(DealMessageDraft.whatsappNumber('+91 98200-12345'), '919820012345');
    expect(DealMessageDraft.whatsappNumber('98200 12345'), '919820012345', reason: 'ten digits are Indian');
  });

  testWidgets('email: To, From, subject and message filled in; Send opens it', (tester) async {
    final launched = await _open(tester);
    expect(find.text('Email draft'), findsOneWidget);
    expect(_text(tester, 'to'), 'ravi@goldmedal.in');
    expect(_text(tester, 'subject'), 'Quotation for Patti No. 1');
    expect(find.textContaining('rutu@example.test'), findsOneWidget, reason: 'From');

    await tester.enterText(find.byKey(const ValueKey<String>('deal-message-subject')), 'Patti & co');
    await tester.tap(find.byKey(const ValueKey<String>('deal-message-send')));
    await tester.pumpAndSettle();
    final uri = launched.single;
    expect(uri.scheme, 'mailto');
    expect(uri.toString(), startsWith('mailto:ravi@goldmedal.in?subject=Patti%20%26%20co&body=Dear%20Ravi'));
    expect(find.byType(DealMessageDialog), findsNothing, reason: 'closed once it opened');
  });

  testWidgets('WhatsApp: the number and a short message; Send opens wa.me', (tester) async {
    final launched = await _open(tester);
    await tester.tap(find.byKey(const ValueKey<String>('deal-message-whatsapp')));
    await tester.pump();
    expect(find.text('WhatsApp draft'), findsOneWidget);
    expect(_text(tester, 'phone'), '98200 12345');
    expect(find.byKey(const ValueKey<String>('deal-message-subject')), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('deal-message-send')));
    await tester.pumpAndSettle();
    expect(launched.single.toString(), startsWith('https://wa.me/919820012345?text=Hello%20Ravi'));
  });

  testWidgets('no address, no Send; an app that does not open says so', (tester) async {
    const noEmail = DealMessageContext(
      personName: 'Meena',
      email: '',
      phone: '',
      theirCompany: 'Gold Medal',
      partName: 'Patti No. 1',
      partCode: '',
      quotation: '',
      fromName: '',
      fromEmail: '',
      ourCompany: '',
    );
    final launched = await _open(tester, deal: noEmail, opens: false);
    sendButton() => find.byKey(const ValueKey<String>('deal-message-send'));
    expect(find.byTooltip('Type the email address it goes to'), findsOneWidget);
    await tester.tap(sendButton(), warnIfMissed: false);
    await tester.pump();
    expect(launched, isEmpty);

    await tester.enterText(find.byKey(const ValueKey<String>('deal-message-to')), 'meena@goldmedal.in');
    await tester.pump();
    await tester.tap(sendButton());
    await tester.pumpAndSettle();
    expect(launched, hasLength(1));
    expect(find.textContaining('No mail app opened'), findsOneWidget);
    expect(find.byType(DealMessageDialog), findsOneWidget, reason: 'kept open to copy from');
  });
}
