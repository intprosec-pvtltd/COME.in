import '../../core/email_validation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/controller.dart';
import '../../core/design.dart';
import '../../core/localization.dart';

/// Indian numbers may be entered without a country code. International numbers
/// must include their country code. The backend repeats all validation.
String? normalizeMobile(String? raw) {
  var value = (raw ?? '').trim().replaceAll(RegExp(r'[\s()-]'), '');
  if (RegExp(r'^[6-9]\d{9}$').hasMatch(value)) value = '+91$value';
  if (RegExp(r'^91[6-9]\d{9}$').hasMatch(value)) value = '+$value';
  if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value)) return null;
  if (value.startsWith('+91') && !RegExp(r'^\+91[6-9]\d{9}$').hasMatch(value)) return null;
  return value;
}

String? mobileError(BuildContext context, String? value) =>
    normalizeMobile(value) == null ? tr(context, 'Enter a valid mobile number') : null;

/// A display-only prefix; the complete raw number is always normalized on submit.
InputDecoration mobileDecoration(BuildContext context, String raw, {bool label = false}) {
  final compact = raw.trim().replaceAll(RegExp(r'[\s()-]'), '');
  final explicit = compact.startsWith('+') || (compact.startsWith('91') && compact.length > 10);
  return InputDecoration(
    labelText: label ? tr(context, 'Mobile number') : null,
    hintText: tr(context, 'Mobile number'),
    prefixIcon: explicit ? const Icon(Icons.phone_outlined) : Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('+91', style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(width: 10),
        SizedBox(height: 22, child: VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant)),
      ]),
    ),
  );
}

/// Reusable verification screen. The backend owns expiry, replay protection,
/// and limits; the client countdown is solely a user-interface convenience.
class PhoneCodePage extends StatefulWidget {
  const PhoneCodePage({super.key, required this.phone, required this.resend,
    required this.verify, this.registration = false});
  final String phone;
  final bool registration;
  final Future<void> Function() resend;
  final Future<String> Function(String code) verify;
  @override
  State<PhoneCodePage> createState() => _PhoneCodePageState();
}
class _PhoneCodePageState extends State<PhoneCodePage> {
  final code = TextEditingController();
  final form = GlobalKey<FormState>();
  Timer? timer;
  int seconds = 30;
  bool busy = false;
  String? error;
  @override
  void initState() { super.initState(); startCountdown(); }
  void startCountdown() {
    timer?.cancel();
    seconds = 30;
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => seconds--);
      if (seconds <= 0) t.cancel();
    });
  }
  @override
  void dispose() { timer?.cancel(); code.dispose(); super.dispose(); }
  Future<void> sendAgain() async {
    setState(() { busy = true; error = null; });
    try {
      await widget.resend();
      if (mounted) { code.clear(); setState(startCountdown); }
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> confirm() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() { busy = true; error = null; });
    try {
      final result = await widget.verify(code.text);
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => PageBody(title: 'Verify mobile number',
    subtitle: 'If eligible, a six-digit SMS code will arrive at ${widget.phone}. The code expires after five minutes.',
    children: [Surface(child: Form(key: form, child: Column(children: [
      TextFormField(controller: code, keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode], maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Verification code'),
        validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '') ? null : 'Enter the six-digit code'),
      const SizedBox(height: 12),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      FilledButton(onPressed: busy ? null : confirm, child: Text(busy ? 'Please wait…' : 'Verify code')),
      TextButton(onPressed: busy || seconds > 0 ? null : sendAgain,
        child: Text(seconds > 0 ? 'Resend code in ${seconds}s' : 'Resend code')),
      if (widget.registration) ...[
        const SizedBox(height: 8),
        const Text('No SMS? Check your mobile number and signal. If you already have an account, sign in or use Forgot Password. Otherwise, retry after the countdown or contact support.', textAlign: TextAlign.center),
        TextButton(onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Change mobile number')),
      ],
    ])))]);
}

/// One-time migration for existing accounts and owner-invited residents.
/// Email is used only to prove the existing account, not as the new login.
class ActivateMobilePage extends StatefulWidget {
  const ActivateMobilePage({super.key});
  @override
  State<ActivateMobilePage> createState() => _ActivateMobilePageState();
}
class _ActivateMobilePageState extends State<ActivateMobilePage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(), phone = TextEditingController(), password = TextEditingController();
  bool busy = false, hidden = true;
  String? error;
  @override
  void dispose() { email.dispose(); phone.dispose(); password.dispose(); super.dispose(); }
  Future<void> _activateMobile() async {
    if (busy || !form.currentState!.validate()) return;
    final api = AppScope.of(context).api;
    final number = normalizeMobile(phone.text)!;
    final data = <String, dynamic>{'email': email.text.trim(), 'phone': number, 'password': password.text};
    setState(() { busy = true; error = null; });
    try {
      Future<void> send() async { await api.request('/v3/phone/enroll/request', method: 'POST', body: data); }
      await send();
      if (!mounted) return;
      final result = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => PhoneCodePage(
        phone: number, resend: send, verify: (code) async {
          await api.request('/v3/phone/enroll/confirm', method: 'POST', body: {...data, 'code': code});
          return 'verified';
        })));
      if (mounted && result == 'verified') {
        password.clear();
        Navigator.of(context).pop(number);
      }
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => PageBody(title: 'Activate mobile login',
    subtitle: 'Existing owners and invited residents: verify your phone once using your original account email and password. Your account and records stay unchanged.',
    children: [Surface(child: Form(key: form, child: Column(children: [
      TextFormField(controller: email, keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Existing account email'),
        validator: emailError),
      const SizedBox(height: 12),
      TextFormField(controller: password, obscureText: hidden,
        decoration: InputDecoration(labelText: 'Existing password', suffixIcon: IconButton(
          onPressed: () => setState(() => hidden = !hidden), icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined))),
        validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null),
      const SizedBox(height: 12),
      TextFormField(controller: phone, keyboardType: TextInputType.phone,
        decoration: mobileDecoration(context, phone.text, label: true),
        onChanged: (_) => setState(() {}),
        validator: (v) => mobileError(context, v)),
      const SizedBox(height: 12),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      FilledButton(onPressed: busy ? null : _activateMobile, child: Text(busy ? 'Requesting…' : 'Send SMS code')),
    ])))]);
}
