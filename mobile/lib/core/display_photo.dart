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
    if (widget.revision == 0) {
      if (mounted) setState(() => bytes = null);
      return;
    }
    try {
      final result = await AppScope.of(context).api.download(path);
      if (mounted) setState(() => bytes = result);
    } catch (_) { if (mounted) setState(() => bytes = null); }
  }

  Future<void> _choose(ImageSource source) async {
    if (busy) return;
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
    setState(() => busy = true);
    try {
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
    setState(() => busy = true);
    try {
      final app = AppScope.of(context);
      await app.api.request(path, method: 'DELETE');
      await app.refresh();
      if (mounted) setState(() => bytes = null);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to remove photo: $e')));
    } finally { if (mounted) setState(() => busy = false); }
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
    return Column(mainAxisSize: MainAxisSize.min, children: [
      preview,
      if (busy) const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
      Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
        TextButton.icon(onPressed: busy ? null : () => _choose(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined), label: const Text('Gallery')),
        TextButton.icon(onPressed: busy ? null : () => _choose(ImageSource.camera),
          icon: const Icon(Icons.camera_alt_outlined), label: const Text('Camera')),
        if (widget.revision > 0) TextButton.icon(onPressed: busy ? null : _remove,
          icon: const Icon(Icons.delete_outline), label: const Text('Remove')),
      ]),
    ]);
  }
}
