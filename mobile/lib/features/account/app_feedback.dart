import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/controller.dart';

class FeedbackReminder extends StatefulWidget {
  const FeedbackReminder({super.key, required this.account, required this.child});
  final String account;
  final Widget child;

  @override
  State<FeedbackReminder> createState() => _FeedbackReminderState();
}

class _FeedbackReminderState extends State<FeedbackReminder> with WidgetsBindingObserver {
  final _foreground = Stopwatch();
  Timer? _timer;
  SharedPreferences? _preferences;
  int _seconds = 0;
  bool _running = false;
  bool _showing = false;
  String get _key => 'app_feedback.v1.${widget.account}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _preferences = prefs;
    _seconds = prefs.getInt('$_key.seconds') ?? 0;
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _resume();
    }
  }

  void _resume() {
    if (_running || _preferences == null || _preferences!.getBool('$_key.done') == true) return;
    _running = true;
    _foreground.start();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
  }

  void _checkpoint() {
    if (!_running) return;
    final elapsed = _foreground.elapsed.inSeconds;
    if (elapsed == 0) return;
    _seconds += elapsed;
    _foreground.reset();
    unawaited(_preferences!.setInt('$_key.seconds', _seconds));
  }

  void _pause() {
    _checkpoint();
    _running = false;
    _foreground.stop();
    _foreground.reset();
    _timer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resume();
    } else {
      _pause();
    }
  }

  Future<void> _tick() async {
    _checkpoint();
    final prefs = _preferences!;
    if (!mounted || _showing || prefs.getBool('$_key.done') == true ||
        ModalRoute.of(context)?.isCurrent != true) return;
    final next = prefs.getInt('$_key.next');
    if (next == null ? _seconds < 600 : DateTime.now().millisecondsSinceEpoch < next) return;
    _showing = true;
    await prefs.setInt('$_key.next', DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch);
    if (mounted) await showAppFeedback(context);
    _showing = false;
    if (prefs.getBool('$_key.done') == true) _pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pause();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String feedbackAccount(AppController app) => '${app.profile['tenant']?['id'] ?? ''}.${app.profile['id']}';

Future<void> showAppFeedback(BuildContext context) async {
  final app = AppScope.of(context);
  final account = feedbackAccount(app);
  var rating = 0;
  var comment = '';
  var busy = false;
  String? error;
  final submitted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        scrollable: true,
        title: Row(children: [
          const Expanded(child: Text('Rate Stay Sync Manage')),
          IconButton(tooltip: 'Close review', onPressed: busy ? null : () => Navigator.pop(dialogContext), icon: const Icon(Icons.close)),
        ]),
        content: Column(children: [
          const Text('Share private feedback with the Stay Sync Manage team.'),
          Wrap(children: [
            for (var star = 1; star <= 5; star++)
              IconButton(
                tooltip: '$star of 5 stars',
                onPressed: busy ? null : () => update(() => rating = star),
                icon: Icon(star <= rating ? Icons.star : Icons.star_border),
              ),
          ]),
          TextField(
            enabled: !busy,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Feedback (optional)'),
            onChanged: (value) => comment = value,
          ),
          if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext), child: const Text('Later')),
          FilledButton(
            onPressed: busy || rating == 0 ? null : () async {
              update(() { busy = true; error = null; });
              try {
                await app.api.request('/v3/app-feedback', method: 'PUT', body: {'rating': rating, 'comment': comment.trim()});
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              } catch (_) {
                if (dialogContext.mounted) update(() { busy = false; error = 'Unable to send feedback. Try again.'; });
              }
            },
            child: Text(busy ? 'Sending…' : 'Submit'),
          ),
        ],
      ),
    ),
  );
  if (submitted == true) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_feedback.v1.$account.done', true);
  }
}
