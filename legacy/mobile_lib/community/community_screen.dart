import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../core/api_client.dart';
import '../core/india_time.dart';
import '../core/app_theme.dart';
import '../core/v2_ui.dart';

/// PG-isolated text + media chat. Updates while this screen is visible.
/// Attachments are downloaded through authenticated API routes (not public URLs).
class CommunityScreen extends StatefulWidget {
  final ApiRequest api;
  final AttachmentUpload upload;
  final Map<String, dynamic> profile;
  const CommunityScreen({super.key, required this.api, required this.upload, required this.profile});
  @override State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  Timer? refreshTimer;
  List<dynamic> messages = [];
  String? error;
  bool sending = false;
  bool loading = true;
  bool polling = false;
  bool get moderator => ['owner', 'manager'].contains(widget.profile['role']);

  @override
  void initState() {
    super.initState();
    load();
    refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => load());
  }
  @override
  void dispose() {
    refreshTimer?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }
  Future<void> load() async {
    if (polling) return;
    polling = true;
    try {
      final data = await widget.api('/community/messages');
      if (!mounted) return;
      setState(() { messages = data is List ? data : []; error = null; loading = false; });
    } catch (e) {
      if (mounted) setState(() { error = e.toString(); loading = false; });
    } finally { polling = false; }
  }
  Future<void> send() async {
    final body = input.text.trim();
    if (sending || body.isEmpty) return;
    setState(() => sending = true);
    try {
      await widget.api('/community/messages', method: 'POST', body: {'body': body});
      if (!mounted) return;
      input.clear();
      await load();
      _scrollEnd();
    } catch (e) { if (mounted) _feedback('Message not sent: $e'); }
    finally { if (mounted) setState(() => sending = false); }
  }
  void _feedback(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: plum,
      content: Text(message),
      duration: const Duration(seconds: 3),
    ));
  }
  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      scroll.animateTo(scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    });
  }
  String _mime(String name) {
    final ext = name.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'webp': return 'image/webp';
      case 'pdf': return 'application/pdf';
      case 'txt': return 'text/plain';
      default: return '';
    }
  }
  Future<void> _sendAttachment(String filename, List<int> bytes) async {
    final mime = _mime(filename);
    if (mime.isEmpty) { _feedback('Choose JPEG, PNG, WebP, PDF or TXT'); return; }
    if (bytes.length > 10 * 1024 * 1024) { _feedback('Attachments must be 10 MB or smaller'); return; }
    setState(() => sending = true);
    try {
      await widget.upload('/community/attachments', filename, bytes, mime);
      if (!mounted) return;
      _feedback('File shared with your community');
      await load();
      _scrollEnd();
    } catch (e) { if (mounted) _feedback('Attachment not shared: $e'); }
    finally { if (mounted) setState(() => sending = false); }
  }
  Future<void> _photo(ImageSource source) async {
    try {
      final result = await ImagePicker().pickImage(source: source, imageQuality: 78, maxWidth: 1600);
      if (result != null) await _sendAttachment(result.name, await result.readAsBytes());
    } catch (e) { if (mounted) _feedback('Camera/photo unavailable: $e'); }
  }
  Future<void> _file() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom,
          allowedExtensions: ['jpg','jpeg','png','webp','pdf','txt'], withData: true);
      if (result == null || result.files.isEmpty) return;
      final selected = result.files.single;
      if (selected.bytes != null) await _sendAttachment(selected.name, selected.bytes!);
      else if (mounted) _feedback('Unable to read this file');
    } catch (e) { if (mounted) _feedback('File picker unavailable: $e'); }
  }
  Future<void> _attach() async {
    await showModalBottomSheet<void>(context: context, showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Padding(padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Share with your PG', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: plum)),
          const SizedBox(height: 20),
          Wrap(spacing: 28, runSpacing: 15, children: [
            _option(sheetContext, Icons.camera_alt_outlined, 'Camera', () => _photo(ImageSource.camera)),
            _option(sheetContext, Icons.photo_outlined, 'Photos', () => _photo(ImageSource.gallery)),
            _option(sheetContext, Icons.attach_file, 'Documents', _file),
          ]),
          const SizedBox(height: 16),
          const Text('JPEG, PNG, WebP, PDF or TXT • 10 MB maximum', style: TextStyle(fontSize: 12, color: muted)),
        ]))));
  }
  Widget _option(BuildContext sheetContext, IconData icon, String label, VoidCallback action) {
    return InkWell(onTap: () { Navigator.pop(sheetContext); action(); },
      borderRadius: BorderRadius.circular(16),
      child: Column(children: [CircleAvatar(radius: 27, backgroundColor: blush,
        child: Icon(icon, color: plum)),const SizedBox(height: 7),Text(label)]));
  }
  Future<void> _emoji() async {
    final emojis = ['😀','😊','😍','❤️','🙏','👍','🎉','😂','🥰','🔥','🙌','✨','😎','😢','👋','💜'];
    await showModalBottomSheet<void>(context: context, builder: (sheetContext) => SafeArea(
      child: Padding(padding: const EdgeInsets.all(16), child: Wrap(spacing: 10,runSpacing: 10,
        children: emojis.map((emoji) => InkWell(onTap: () {
          final old = input.text;
          input.text = '$old$emoji';
          input.selection = TextSelection.collapsed(offset: input.text.length);
          Navigator.pop(sheetContext);
        },child:Padding(padding:const EdgeInsets.all(8),child:Text(emoji,style:const TextStyle(fontSize:28))))).toList()))));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${widget.profile['tenant']?['name'] ?? 'My PG'}',style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
      const Text('Community • Private to your PG',style:TextStyle(fontSize:11,color:muted)),
    ]),actions:[IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),
    body: Column(children: [
      if (loading) const LinearProgressIndicator(),
      if (error != null) MaterialBanner(content: Text(error!), actions: [TextButton(onPressed:load,child:const Text('Retry'))]),
      Expanded(child: RefreshIndicator(onRefresh:load,child: ListView.builder(
        controller: scroll, padding: const EdgeInsets.symmetric(horizontal: 12,vertical: 14),
        itemCount: messages.length,itemBuilder: (ctx,index) {
          final m = messages[index] as Map<String,dynamic>;
          final mine = m['author_id'] == widget.profile['id'];
          final attachments = m['attachments'] is List ? m['attachments'] as List : <dynamic>[];
          return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(ctx).width * .82),
              child: Card(color: mine ? lavender.withValues(alpha: .18) : Colors.white,
                child: Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,
                  children:[Text('${m['author']}',style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold,color:plum)),
                  const SizedBox(height: 5),Text('${m['body']}'),
                  for (final a in attachments) ListTile(dense:true,contentPadding:EdgeInsets.zero,
                    leading:Icon('${a['content_type']}'.startsWith('image/')?Icons.image_outlined:Icons.description_outlined,color:plum),
                    title:Text('${a['filename']}',maxLines:2,overflow:TextOverflow.ellipsis),
                    subtitle:const Text('Private attachment • Open in a future release')),
                  const SizedBox(height: 7),Text(formatIndiaTime(m['created_at']),
                    style:const TextStyle(fontSize:10,color:muted)),
                  if(moderator && m['deleted'] != true) TextButton.icon(
                    onPressed: () async {
                      final ok = await confirm(ctx, 'Remove this message for your PG?');
                      if (!ok || !ctx.mounted) return;
                      await apiAction(ctx,() => widget.api('/community/messages/${m['id']}',method:'DELETE'),load);
                    },icon:const Icon(Icons.delete_outline,size:16),label:const Text('Remove')),
                ])))));
        }))),
      SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(8,8,8,12),child:Row(children:[
        IconButton(onPressed:sending?null:_attach,icon:const Icon(Icons.add_circle_outline,color:plum),tooltip:'Attach'),
        Expanded(child:TextField(controller:input,minLines:1,maxLines:4,maxLength:2000,
          decoration:const InputDecoration(hintText:'Message your community',counterText:'',isDense:true),
          onSubmitted:(_)=>send())),
        IconButton(onPressed:sending?null:_emoji,icon:const Icon(Icons.emoji_emotions_outlined,color:plum),tooltip:'Emoji'),
        IconButton(onPressed:sending?null:send,icon:Icon(sending?Icons.hourglass_empty:Icons.send,color:plum),tooltip:'Send'),
      ]))),
    ]),
  );
}
