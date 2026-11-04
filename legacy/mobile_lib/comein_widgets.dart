import 'package:flutter/material.dart';
import 'app_theme.dart';

class BrandMark extends StatelessWidget {
  final double size;
  final bool wordmark;
  const BrandMark({super.key, this.size = 42, this.wordmark = true});
  @override Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: size, height: size, decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [plum, Color(0xFF9564A5), blush], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(size * .31)),
      child: Icon(Icons.door_front_door_rounded, color: const Color(0xFFFFE8CF), size: size * .60)),
    if (wordmark) ...[SizedBox(width: size * .18), Text('COME.in', style: TextStyle(fontWeight: FontWeight.w900, fontSize: size * .47, color: plum, letterSpacing: -.9))],
  ]);
}

class SectionHeading extends StatelessWidget {
  final String title;
  final String? caption;
  final VoidCallback? action;
  const SectionHeading(this.title, {super.key, this.caption, this.action});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(2, 18, 2, 8), child: Row(children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: plum)),
      if (caption != null) Text(caption!, style: const TextStyle(color: muted, fontSize: 12)),
    ])),
    if (action != null) TextButton(onPressed: action, child: const Text('View all')),
  ]));
}

class SoftMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  const SoftMetric({super.key, required this.label, required this.value, required this.icon, this.accent = lavender, this.onTap});
  @override Widget build(BuildContext context) => Card(child: InkWell(borderRadius: BorderRadius.circular(23), onTap: onTap,
    child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: accent.withValues(alpha: .16), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: accent, size: 20)),
      const SizedBox(height: 14), Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: plum)),
      const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 12, color: muted)),
    ]))));
}

class ActionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  const ActionTile({super.key, required this.title, required this.subtitle, required this.icon, this.onTap});
  @override Widget build(BuildContext context) => Card(child: ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    leading: Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: lavender.withValues(alpha: .16), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: plum)),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: plum)),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
    trailing: const Icon(Icons.chevron_right_rounded, color: muted),
    onTap: onTap,
  ));
}

class PlumHero extends StatelessWidget {
  final String eyebrow;
  final String amount;
  final String detail;
  final Widget? footer;
  const PlumHero({super.key, required this.eyebrow, required this.amount, required this.detail, this.footer});
  @override Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), gradient: const LinearGradient(colors: [plum, Color(0xFF6C3D77)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(eyebrow, style: const TextStyle(color: Color(0xFFE8CDE8), fontWeight: FontWeight.w700)),
      const SizedBox(height: 8), Text(amount, style: const TextStyle(color: Colors.white, fontSize: 33, fontWeight: FontWeight.w900)),
      const SizedBox(height: 5), Text(detail, style: const TextStyle(color: Color(0xFFE8D8EA), fontSize: 12)),
      if (footer != null) ...[const SizedBox(height: 16), footer!],
    ]));
}
