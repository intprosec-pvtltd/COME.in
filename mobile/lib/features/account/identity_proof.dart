import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/controller.dart';
import '../../core/design.dart';

/// A resident's uploaded document is reviewed by their own PG owner.
/// This is document submission, not a DigiLocker or government ID verification.
class IdentityProofPage extends StatefulWidget {
  const IdentityProofPage({super.key, this.residentId});
  final int? residentId;
  @override
  State<IdentityProofPage> createState() => _IdentityProofPageState();
}

class _IdentityProofPageState extends State<IdentityProofPage> {
  List<Map<String, dynamic>> proofs = [];
  bool loading = true;
  bool uploading = false;
  bool consent = false;
  String? error;

  bool get ownerView => widget.residentId != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading && proofs.isEmpty && error == null) {
      // Request once after this widget has access to AppScope.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) refresh();
      });
      loading = false;
    }
  }

  Future<void> refresh() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    final app = AppScope.of(context);
    try {
      final path = ownerView
          ? '/identity/residents/${widget.residentId}/proofs'
          : '/identity/proofs/me';
      final response = await app.api.request(path);
      if (!mounted) return;
      setState(() => proofs = (response as List)
          .map((x) => Map<String, dynamic>.from(x as Map)).toList());
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> submit() async {
    if (!consent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please consent to sharing your ID proof with your PG owner.')));
      return;
    }
    final file = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (file == null || file.files.isEmpty || !mounted) return;
    final chosen = file.files.single;
    if (chosen.size > 5 * 1024 * 1024 || chosen.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Choose a JPG, PNG or PDF under 5 MB.')));
      return;
    }
    final extension = chosen.extension?.toLowerCase();
    final mime = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'pdf' => 'application/pdf',
      _ => '',
    };
    if (mime.isEmpty) return;
    setState(() => uploading = true);
    try {
      await AppScope.of(context).api.upload(
        '/identity/proofs', chosen.name, chosen.bytes!, mime);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Identity document sent to your PG owner for review.')));
      await refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> view(Map<String, dynamic> proof) async {
    final api = AppScope.of(context).api;
    try {
      final bytes = await api.download('/identity/proofs/${proof['id']}/file');
      if (!mounted) return;
      if ('${proof['mime']}'.startsWith('image/')) {
        await showDialog<void>(context: context, builder: (ctx) => Dialog(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: InteractiveViewer(child: Image.memory(
              Uint8List.fromList(bytes), fit: BoxFit.contain))),
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
          ]),
        ));
      } else {
        // An explicit action lets the reviewer open a PDF with an installed app.
        // Sharing identity documents should only be done with trusted apps.
        final allow = await showDialog<bool>(context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Open identity PDF?'),
            content: const Text('Only open or share this private ID document with trusted apps.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open PDF')),
            ],
          ));
        if (allow == true) {
          await Share.shareXFiles([
            XFile.fromData(Uint8List.fromList(bytes), mimeType: 'application/pdf',
              name: 'resident-identity-proof.pdf'),
          ]);
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot open document: $e')));
    }
  }

  Future<void> review(Map<String, dynamic> proof, String decision) async {
    try {
      await AppScope.of(context).api.request(
        '/identity/proofs/${proof['id']}/review', method: 'POST',
        body: {'decision': decision, 'note': ''});
      await refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Review failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => PageBody(
    title: ownerView ? 'Resident ID proof' : 'Submit identity proof',
    subtitle: ownerView
        ? 'Documents submitted by this resident. Only your PG team can review.'
        : 'Submit a JPG, PNG or PDF identity proof (max 5 MB). Mask unneeded ID numbers. This is manual PG-owner review, not DigiLocker verification.',
    refresh: refresh,
    children: [
      if (!ownerView) CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: consent,
        onChanged: (v) => setState(() => consent = v ?? false),
        title: const Text('I agree to share my selected ID proof with my PG owner for resident verification.'),
        controlAffinity: ListTileControlAffinity.leading,
      ),
      if (!ownerView) FilledButton.icon(
        onPressed: uploading ? null : submit,
        icon: const Icon(Icons.upload_file_outlined),
        label: Text(uploading ? 'Uploading…' : 'Upload ID proof'),
      ),
      const SizedBox(height: 12),
      if (loading) const Center(child: CircularProgressIndicator()),
      if (error != null) Surface(child: Text(error!)),
      if (!loading && proofs.isEmpty) const Surface(
        child: Text('No identity proof has been submitted yet.')),
      for (final p in proofs) Surface(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${p['filename']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Review status: ${p['status']}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
          if ('${p['review_note']}'.isNotEmpty)
            Text('Owner note: ${p['review_note']}'),
          TextButton.icon(onPressed: () => view(p),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Open document')),
          if (ownerView && p['status'] == 'pending') Row(children: [
            TextButton(onPressed: () => review(p, 'approved'),
              child: const Text('Approve')),
            TextButton(onPressed: () => review(p, 'rejected'),
              child: const Text('Reject')),
          ]),
        ],
      )),
    ],
  );
}
