import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/erp_form_dialog.dart';

/// How the draft goes out.
enum DealMessageChannel { email, whatsapp }

/// What the draft is about: the person it is to, the deal, who it is from.
class DealMessageContext {
  const DealMessageContext({
    required this.personName,
    required this.email,
    required this.phone,
    required this.theirCompany,
    required this.partName,
    required this.partCode,
    required this.quotation,
    required this.fromName,
    required this.fromEmail,
    required this.ourCompany,
  });

  final String personName;
  final String email;
  final String phone;
  final String theirCompany;

  /// "Patti No. 1".
  final String partName;
  final String partCode;

  /// As typed on the deal ("85000"); blank when there is none yet.
  final String quotation;
  final String fromName;
  final String fromEmail;
  final String ourCompany;
}

/// The draft's words, from the deal. Kept apart from the dialog so the same
/// sample reads the same wherever it is built.
class DealMessageDraft {
  const DealMessageDraft._();

  static String _greetingName(DealMessageContext c) {
    final first = c.personName.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? 'Sir/Madam' : first;
  }

  static String _part(DealMessageContext c) {
    final name = c.partName.trim().isEmpty ? 'the part' : c.partName.trim();
    return c.partCode.trim().isEmpty ? name : '$name (${c.partCode.trim()})';
  }

  static String _signature(DealMessageContext c) => [
    if (c.fromName.trim().isNotEmpty) c.fromName.trim(),
    if (c.ourCompany.trim().isNotEmpty) c.ourCompany.trim(),
  ].join('\n');

  static String subject(DealMessageContext c) {
    final name = c.partName.trim().isEmpty ? 'our part' : c.partName.trim();
    return 'Quotation for $name';
  }

  static String email(DealMessageContext c) {
    final q = c.quotation.trim();
    final lines = <String>[
      'Dear ${_greetingName(c)},',
      '',
      'Thank you for your time. As discussed, here is our quotation for ${_part(c)}.',
      if (q.isNotEmpty) ...['', 'Quotation: ₹$q'],
      '',
      'Please let us know if you have any questions, or if we may go ahead.',
      '',
      'Regards,',
      _signature(c),
    ];
    return lines.join('\n').trimRight();
  }

  static String whatsapp(DealMessageContext c) {
    final q = c.quotation.trim();
    final from = [
      if (c.fromName.trim().isNotEmpty) c.fromName.trim(),
      if (c.ourCompany.trim().isNotEmpty) 'from ${c.ourCompany.trim()}',
    ].join(' ');
    return [
      'Hello ${_greetingName(c)},',
      if (from.isNotEmpty) 'this is $from.',
      q.isEmpty
          ? 'Following up on ${_part(c)}.'
          : 'Our quotation for ${_part(c)} is ₹$q.',
      'Please let us know if you have any questions.',
    ].join(' ');
  }

  /// Digits WhatsApp dials: "+91 98200 12345" → 919820012345; a ten-digit
  /// number is taken as Indian and gets 91.
  static String whatsappNumber(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length == 10 ? '91$digits' : digits;
  }

  static bool looksLikeEmail(String text) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text.trim());

  static Uri emailUri({
    required String to,
    required String subject,
    required String body,
  }) =>
      // Encoded by hand: Uri's queryParameters writes spaces as "+", which
      // mail apps show as plus signs.
      Uri.parse(
        'mailto:${to.trim()}?subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}',
      );

  static Uri whatsappUri({
    required String phone,
    required String text,
  }) => Uri.parse(
    'https://wa.me/${whatsappNumber(phone)}?text=${Uri.encodeComponent(text)}',
  );
}

/// A sample message to a person the deal was done with — by email or on
/// WhatsApp — with To, From and the words filled in from the deal, every one
/// editable, and Send.
///
/// Send hands the message to the computer's own mail app or to WhatsApp,
/// filled in: Paper has no mail server of its own to send from, and a message
/// to a customer should be seen by whoever sends it.
class DealMessageDialog extends StatefulWidget {
  const DealMessageDialog({
    super.key,
    required this.context,
    this.initialChannel = DealMessageChannel.email,
    this.launcher,
  });

  final DealMessageContext context;
  final DealMessageChannel initialChannel;

  /// Opens the message; the real one is url_launcher. Swapped in tests.
  final Future<bool> Function(Uri uri)? launcher;

  static Future<void> open(
    BuildContext context, {
    required DealMessageContext message,
    Future<bool> Function(Uri uri)? launcher,
  }) {
    return showErpFormDialog<void>(
      context,
      maxWidth: 760,
      maxHeight: 820,
      child: DealMessageDialog(context: message, launcher: launcher),
    );
  }

  @override
  State<DealMessageDialog> createState() => _DealMessageDialogState();
}

class _DealMessageDialogState extends State<DealMessageDialog> {
  late DealMessageChannel _channel = widget.initialChannel;
  late final TextEditingController _emailTo = TextEditingController(
    text: widget.context.email.trim(),
  );
  late final TextEditingController _subject = TextEditingController(
    text: DealMessageDraft.subject(widget.context),
  );
  late final TextEditingController _emailBody = TextEditingController(
    text: DealMessageDraft.email(widget.context),
  );
  late final TextEditingController _phoneTo = TextEditingController(
    text: widget.context.phone.trim(),
  );
  late final TextEditingController _waBody = TextEditingController(
    text: DealMessageDraft.whatsapp(widget.context),
  );
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_emailTo, _phoneTo]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_emailTo, _subject, _emailBody, _phoneTo, _waBody]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEmail => _channel == DealMessageChannel.email;

  /// Why Send is off, or null.
  String? get _blocked {
    if (_isEmail) {
      return DealMessageDraft.looksLikeEmail(_emailTo.text)
          ? null
          : 'Type the email address it goes to';
    }
    return DealMessageDraft.whatsappNumber(_phoneTo.text).length >= 10
        ? null
        : 'Type the WhatsApp number it goes to';
  }

  String get _from {
    final c = widget.context;
    final who = [
      if (c.fromName.trim().isNotEmpty) c.fromName.trim(),
      if (_isEmail && c.fromEmail.trim().isNotEmpty) '<${c.fromEmail.trim()}>',
    ].join(' ');
    final company = c.ourCompany.trim();
    if (who.isEmpty) return company.isEmpty ? 'You' : company;
    return company.isEmpty ? who : '$who · $company';
  }

  Future<void> _send() async {
    final uri = _isEmail
        ? DealMessageDraft.emailUri(
            to: _emailTo.text,
            subject: _subject.text,
            body: _emailBody.text,
          )
        : DealMessageDraft.whatsappUri(
            phone: _phoneTo.text,
            text: _waBody.text,
          );
    setState(() {
      _sending = true;
      _error = null;
    });
    final launch =
        widget.launcher ??
        (u) => launchUrl(u, mode: LaunchMode.externalApplication);
    var opened = false;
    try {
      opened = await launch(uri);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    if (opened) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _sending = false;
      _error = _isEmail
          ? 'No mail app opened. Set one up on this computer, or copy the message.'
          : 'WhatsApp did not open. Is it installed on this computer?';
    });
  }

  Widget _field(
    String key,
    TextEditingController controller,
    String label, {
    int lines = 1,
    bool readOnly = false,
    TextInputType? keyboard,
  }) {
    return TextField(
      key: ValueKey<String>('deal-message-$key'),
      controller: controller,
      readOnly: readOnly,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 6,
      keyboardType: keyboard,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: lines > 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final who = widget.context.personName.trim();
    final blocked = _blocked;
    return ErpFormScaffold(
      title: _isEmail ? 'Email draft' : 'WhatsApp draft',
      subtitle: who.isEmpty
          ? widget.context.theirCompany
          : '$who · ${widget.context.theirCompany}',
      onClose: () => Navigator.of(context).maybePop(),
      errorBanner: _error == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: SoftErpTheme.dangerBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  fontSize: 14,
                  color: SoftErpTheme.dangerText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The two ways it can go; the one chosen is filled.
          Row(
            children: <Widget>[
              AppButton(
                key: const ValueKey<String>('deal-message-email'),
                label: 'Email',
                icon: Icons.mail_outline_rounded,
                variant: _isEmail
                    ? AppButtonVariant.primary
                    : AppButtonVariant.secondary,
                dense: true,
                onPressed: () =>
                    setState(() => _channel = DealMessageChannel.email),
              ),
              const SizedBox(width: 10),
              AppButton(
                key: const ValueKey<String>('deal-message-whatsapp'),
                label: 'WhatsApp',
                icon: Icons.chat_outlined,
                variant: _isEmail
                    ? AppButtonVariant.secondary
                    : AppButtonVariant.primary,
                dense: true,
                onPressed: () =>
                    setState(() => _channel = DealMessageChannel.whatsapp),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_isEmail) ...<Widget>[
            _field('to', _emailTo, 'To', keyboard: TextInputType.emailAddress),
            const SizedBox(height: 14),
            _FromLine(text: _from),
            const SizedBox(height: 14),
            _field('subject', _subject, 'Subject'),
            const SizedBox(height: 14),
            _field('body', _emailBody, 'Message', lines: 10),
          ] else ...<Widget>[
            _field(
              'phone',
              _phoneTo,
              'To (WhatsApp number)',
              keyboard: TextInputType.phone,
            ),
            const SizedBox(height: 14),
            _FromLine(text: _from),
            const SizedBox(height: 14),
            _field('wa-body', _waBody, 'Message', lines: 6),
          ],
          const SizedBox(height: 10),
          Text(
            _isEmail
                ? 'Send opens your mail app with this filled in — check it there and send.'
                : 'Send opens WhatsApp with this message to the number — check it there and send.',
            style: const TextStyle(
              fontSize: 14,
              color: SoftErpTheme.textSecondary,
            ),
          ),
        ],
      ),
      footer: Row(
        children: <Widget>[
          const Spacer(),
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message:
                blocked ??
                (_isEmail ? 'Open it in your mail app' : 'Open it in WhatsApp'),
            child: AppButton(
              key: const ValueKey<String>('deal-message-send'),
              label: 'Send',
              icon: Icons.send_rounded,
              isLoading: _sending,
              onPressed: blocked != null || _sending ? null : _send,
            ),
          ),
        ],
      ),
    );
  }
}

class _FromLine extends StatelessWidget {
  const _FromLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      key: const ValueKey<String>('deal-message-from'),
      decoration: const InputDecoration(labelText: 'From', enabled: false),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, color: SoftErpTheme.textPrimary),
      ),
    );
  }
}
