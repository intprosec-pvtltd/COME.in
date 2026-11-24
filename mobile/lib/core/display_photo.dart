import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../app/controller.dart';

/// Authenticated private profile/property photo. No public media URLs.
class DisplayPhotoWidget extends StatefulWidget {
  const DisplayPhotoWidget({super.key, required this.kind, required this.id,
    required this.revision, this.editable = false, this.size = 76});
  final String kind;
  final int id;
  final int revision;
  final bool editable;
  final double size;

  @override
  State<DisplayPhotoWidget> createState() => _DisplayPhotoWidgetState();
}

class _DisplayPhotoWidgetState extends State<DisplayPhotoWidget> {
  Uint8List? bytes;
  bool busy = false;
  bool loaded = false;
  int loadGeneration = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) { loaded = true; _load(); }
  }
  @override
  void didUpdateWidget(covariant DisplayPhotoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision || oldWidget.id != widget.id ||
        oldWidget.kind != widget.kind) { _load(); }
  }
  String get path => '/identity/display-photos/${widget.kind}/${widget.id}';

  Future<void> _load() async {
    final generation = ++loadGeneration;
    if (widget.revision == 0) {
      if (mounted) setState(() => bytes = null);
      return;
    }
    try {
      final result = await AppScope.of(context).api.download(path);
      if (mounted && generation == loadGeneration) setState(() => bytes = result);
    } catch (_) { if (mounted && generation == loadGeneration) setState(() => bytes = null); }
  }

  Future<void> _choose(ImageSource source) async {
    if (busy) return;
    setState(() => busy = true);
    try {
    final picked = await ImagePicker().pickImage(source: source,
        imageQuality: 83, maxWidth: 1200, maxHeight: 1200);
    if (picked == null || !mounted) return;
    final data = await picked.readAsBytes();
    if (!mounted) return;
    final preview = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Use this photo?'),
      content: Image.memory(data, height: 230, fit: BoxFit.contain),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save photo')),
      ],
    ));
    if (preview != true || !mounted) return;
      final app = AppScope.of(context);
      final mime = picked.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      await app.api.upload(path, picked.name, data, mime);
      await app.refresh();
      if (mounted) {
        await _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo saved')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo not saved: $e')));
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _remove() async {
    if (busy) return;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Remove photo?'),
      content: const Text('Your current photo will be removed.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Remove', style: TextStyle(color: Theme.of(ctx).colorScheme.error)))],
    ));
    if (confirmed != true || !mounted || busy) return;
    setState(() => busy = true);
    try {
      final app = AppScope.of(context);
      await app.api.request(path, method: 'DELETE');
      await app.refresh();
      if (mounted) { loadGeneration++; setState(() => bytes = null); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to remove photo: $e')));
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _photoOptions() async {
    if (busy) return;
    final choice = await showModalBottomSheet<String>(context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(12), child: Text(widget.kind == 'user' ? 'Profile photo' : 'Property photo', style: Theme.of(ctx).textTheme.titleLarge)),
          ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, 'camera')),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, 'gallery')),
          if (widget.revision > 0 || bytes != null) ListTile(leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
            title: Text('Remove photo', style: TextStyle(color: Theme.of(ctx).colorScheme.error)), onTap: () => Navigator.pop(ctx, 'remove')),
        ]))));
    if (!mounted || busy) return;
    if (choice == 'camera') await _choose(ImageSource.camera);
    if (choice == 'gallery') await _choose(ImageSource.gallery);
    if (choice == 'remove') await _remove();
  }

  @override
  Widget build(BuildContext context) {
    final preview = ClipRRect(
      borderRadius: BorderRadius.circular(widget.kind == 'user' ? widget.size : 12),
      child: SizedBox(width: widget.size, height: widget.size,
        child: bytes == null
          ? ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(widget.kind == 'user' ? Icons.person : Icons.apartment,
                size: widget.size * .48))
          : Image.memory(bytes!, width: widget.size, height: widget.size, fit: BoxFit.cover)),
    );
    if (!widget.editable) return preview;
    final colors = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        preview,
        if (busy) const CircularProgressIndicator(),
        Positioned(right: -5, bottom: -5, child: Material(
          color: colors.surface, shape: const CircleBorder(),
          child: Padding(padding: const EdgeInsets.all(3), child: IconButton.filled(
            tooltip: 'Edit photo', onPressed: busy ? null : _photoOptions,
            icon: const Icon(Icons.camera_alt_outlined),
          )),
        )),
      ]),
      const SizedBox(height: 10),
      TextButton(onPressed: busy ? null : _photoOptions, child: const Text('Edit photo')),
    ]);
  }
}
