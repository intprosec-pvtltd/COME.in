import '../../core/localization.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/controller.dart';
import '../../core/design.dart';

/// Manual review by the correct PG owner. Not DigiLocker verification.
class IdentityProofPage extends StatefulWidget {
  const IdentityProofPage({super.key, this.residentId});
  final int? residentId;

  @override
  State<IdentityProofPage> createState() => _IdentityProofPageState();
}

class _IdentityProofPageState extends State<IdentityProofPage> {
  static const plum = Color(0xFF3B1E3F);
  static const green = Color(0xFF167547);
  static const red = Color(0xFFC03540);
  static const blue = Color(0xFF2458A6);

  List<Map<String, dynamic>> proofs = [];
  bool loading = true;
  bool uploading = false;
  bool consent = false;
  bool requested = false;
  String? error;

  bool get ownerView => widget.residentId != null;

  Map<String, dynamic>? get latest => proofs.isEmpty ? null : proofs.first;
  bool get canSubmit => !ownerView && !loading && error == null &&
      (latest == null || latest!['status'] == 'rejected');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!requested) {
      requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) refresh();
      });
    }
  }

  Future<void> refresh() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    try {
      final app = AppScope.of(context);
      final path = ownerView
          ? '/identity/residents/${widget.residentId}/proofs'
          : '/identity/proofs/me';
      final response = await app.api.request(path);
      if (!mounted) return;
      setState(() {
        proofs = (response as List)
            .map((v) => Map<String, dynamic>.from(v as Map)).toList();
        consent = false;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> submit() async {
    if (!canSubmit || uploading) return;
    if (!consent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please agree to share the document with your PG owner.')));
      return;
    }
    final file = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (file == null || file.files.isEmpty || !mounted) return;
    final selected = file.files.single;
    if (selected.size > 5 * 1024 * 1024 || selected.bytes == null ||
        selected.bytes!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Choose a JPG, PNG or PDF file smaller than 5 MB.')));
      return;
    }
    final mime = switch (selected.extension?.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'pdf' => 'application/pdf',
      _ => '',
    };
    if (mime.isEmpty) return;
    setState(() => uploading = true);
    try {
      await AppScope.of(context).api.upload(
        '/identity/proofs', selected.name, selected.bytes!, mime);
      if (!mounted) return;
      await refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Document submitted. Your PG owner will review it.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Upload failed: $e')));
        // Server may have accepted a concurrent upload; get the latest status.
        await refresh();
      }
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> view(Map<String, dynamic> proof) async {
    try {
      final bytes = await AppScope.of(context).api
          .download('/identity/proofs/${proof['id']}/file');
      if (!mounted) return;
      if ('${proof['mime']}'.startsWith('image/')) {
        await showDialog<void>(context: context, builder: (ctx) => Dialog(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: InteractiveViewer(
              child: Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain))),
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
          ]),
        ));
      } else {
        final allow = await showDialog<bool>(context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Open identity PDF?'),
            content: const Text('This document is private. Open it only in a trusted app.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Open PDF')),
            ],
          ));
        if (allow == true) {
          await Share.shareXFiles([
            XFile.fromData(Uint8List.fromList(bytes),
              mimeType: 'application/pdf', name: 'resident-identity-proof.pdf'),
          ]);
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot open document: $e')));
    }
  }

  Future<void> review(Map<String, dynamic> proof, String decision) async {
    if (loading || latest?['id'] != proof['id'] || proof['status'] != 'pending') return;
    final noteController = TextEditingController();
    try {
      final accepted = await showDialog<bool>(context: context,
        builder: (ctx) => AlertDialog(
          title: Text(decision == 'approved' ? 'Approve document?' : 'Reject document?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(decision == 'approved'
              ? 'Confirm that you manually reviewed this resident document.'
              : 'The resident can upload a replacement only after rejection.'),
            if (decision == 'rejected') ...[
              const SizedBox(height: 12),
              TextField(controller: noteController, maxLength: 500, maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason for rejection (optional)',
                  border: OutlineInputBorder())),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: decision == 'approved' ? green : red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(decision == 'approved' ? 'Approve' : 'Reject')),
          ],
        ));
      if (accepted != true || !mounted) return;
      await AppScope.of(context).api.request(
        '/identity/proofs/${proof['id']}/review', method: 'POST',
        body: {'decision': decision, 'note': noteController.text.trim()});
      await refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(decision == 'approved' ? 'Document approved.' : 'Document rejected. Resident may resubmit.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Review failed: $e')));
    } finally {
      noteController.dispose();
    }
  }

  Widget _status(Map<String, dynamic> proof) {
    final status = '${proof['status']}';
    final approved = status == 'approved';
    final rejected = status == 'rejected';
    final color = approved ? green : rejected ? red : blue;
    final title = approved ? 'Approved' : rejected ? 'Rejected' : 'Pending review';
    final icon = approved
        ? Icons.verified_outlined
        : rejected ? Icons.error_outline : Icons.hourglass_top_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 7),
        Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _riskCard(Map<String, dynamic> proof) {
    final flags=(proof['risk_flags'] as List? ?? []).map((e)=>'$e').toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color:const Color(0xFFFFF4E5),
        borderRadius:BorderRadius.circular(12)),
      child: Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(tr(context,'Authenticity not verified'),
          style:const TextStyle(fontWeight:FontWeight.bold,color:Color(0xFF815418))),
        const SizedBox(height:5),
        Text(flags.isEmpty ? tr(context,'No flags found') : flags.join(' • '),
          style:const TextStyle(fontSize:12)),
        const SizedBox(height:5),
        Text(tr(context,'Not a government verification'),
          style:const TextStyle(fontSize:11)),
      ]),
    );
  }

  Widget _proofCard(Map<String, dynamic> proof, {required bool current}) {
    final note = '${proof['review_note'] ?? ''}'.trim();
    final status = '${proof['status']}';
    return Surface(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (current) const Padding(
          padding: EdgeInsets.only(bottom: 9),
          child: Text('CURRENT SUBMISSION',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
              letterSpacing: 1, color: plum))),
        Text('${proof['filename']}',
          overflow: TextOverflow.ellipsis, maxLines: 2,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        _status(proof),
        if (ownerView) ...[
          const SizedBox(height: 9),
          _riskCard(proof),
        ],
        if (note.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('Owner note: $note')),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: blue, backgroundColor: const Color(0xFFEAF2FF),
            side: const BorderSide(color: Color(0xFF9BBCEB)),
            padding: const EdgeInsets.symmetric(vertical: 12)),
          onPressed: () => view(proof),
          icon: const Icon(Icons.visibility_outlined),
          label: Text(tr(context,'Open document')))),
        if (ownerView && current && status == 'pending') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: green, foregroundColor: Colors.white),
              onPressed: () => review(proof, 'approved'),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(tr(context,'Approve')))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: red, foregroundColor: Colors.white),
              onPressed: () => review(proof, 'rejected'),
              icon: const Icon(Icons.cancel_outlined),
              label: Text(tr(context,'Reject')))),
          ]),
        ],
      ],
    ));
  }

  Widget _uploadForm() => Surface(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Submit an identity document',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: plum)),
      const SizedBox(height: 8),
      const Text('Select a clear photo or PDF of an accepted identity document. '
          'Your PG owner will review it privately.'),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFFF5EFF8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5D6E9))),
        child: const Column(children: [
          Icon(Icons.upload_file_outlined, size: 37, color: plum),
          SizedBox(height: 6),
          Text('JPG, PNG or PDF', style: TextStyle(fontWeight: FontWeight.w800)),
          Text('Maximum 5 MB • One active submission at a time',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF76657C))),
        ]),
      ),
      const SizedBox(height: 10),
      const Text('Mask any identification numbers not required for PG review.',
        style: TextStyle(fontSize: 12, color: Color(0xFF76657C))),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: plum,
        value: consent,
        onChanged: uploading ? null : (v) => setState(() => consent = v ?? false),
        title: const Text('I consent to securely sharing this document with my PG owner for manual review.',
          style: TextStyle(fontSize: 13)),
      ),
      const SizedBox(height: 6),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: plum,
          padding: const EdgeInsets.symmetric(vertical: 13)),
        onPressed: uploading ? null : submit,
        icon: uploading
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.file_upload_outlined),
        label: Text(uploading ? 'Submitting…' : 'Choose document & submit'))),
    ],
  ));

  Widget _residentSummary(Map<String, dynamic> proof) {
    final status = '${proof['status']}';
    final message = switch (status) {
      'approved' => 'Your PG owner has approved this submission. No further upload is needed.',
      'rejected' => 'Your PG owner rejected this submission. You can submit a replacement below.',
      _ => 'Your proof has been sent to your PG owner. You cannot submit another while review is pending.',
    };
    return Surface(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
      _status(proof),
      const SizedBox(height: 12),
      Text(message),
      const SizedBox(height: 12),
      Text('${proof['filename']}', maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700)),
      if ('${proof['review_note'] ?? ''}'.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Owner note: ${proof['review_note']}'),
      ],
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => view(proof),
        icon: const Icon(Icons.visibility_outlined),
        label: const Text('View submitted proof')),
    ]));
  }

  @override
  Widget build(BuildContext context) => PageBody(
    title: ownerView ? 'Resident ID proof' : 'Identity verification',
    subtitle: ownerView
        ? 'Documents submitted by this resident. Only your PG team can review.'
        : 'Identity documents are reviewed manually by your PG owner.',
    refresh: refresh,
    children: [
      if (loading) const Center(child: CircularProgressIndicator()),
      if (error != null) Surface(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Unable to check document status: $error'),
          TextButton(onPressed: refresh, child: const Text('Try again')),
        ])),
      if (!loading && error == null) ...[
        if (!ownerView) ...[
          if (latest != null) _residentSummary(latest!),
          if (canSubmit) ...[
            if (latest != null) const SizedBox(height: 12),
            _uploadForm(),
          ],
        ] else ...[
          if (proofs.isEmpty) const Surface(
            child: Text('This resident has not submitted an ID proof yet.')),
          for (var i = 0; i < proofs.length; i++) ...[
            _proofCard(proofs[i], current: i == 0),
            const SizedBox(height: 10),
          ],
        ],
      ],
    ],
  );
}
