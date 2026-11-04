import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';

class OwnerHome extends StatefulWidget {
  final ApiRequest api;
  final Map<String, dynamic> profile;
  final VoidCallback logout;
  const OwnerHome({super.key, required this.api, required this.profile, required this.logout});
  @override State<OwnerHome> createState() => _OwnerHomeState();
}
class _OwnerHomeState extends State<OwnerHome> {
  int selected = 0;
  bool loading = false;
  String? error;
  Map<String, dynamic> summary = {};
  List<dynamic> residents = [], tickets = [], invoices = [], payments = [], notices = [];
  @override void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final s = await widget.api('/summary');
      final r = await widget.api('/residents');
      final t = await widget.api('/tickets');
      final i = await widget.api('/invoices');
      final p = await widget.api('/payments');
      final n = await widget.api('/notices');
      if (mounted) setState(() { summary = Map<String,dynamic>.from(s); residents=r; tickets=t; invoices=i; payments=p; notices=n; });
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => loading = false); }
  }
  Widget metric(String name, String value, IconData icon) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: plum), const SizedBox(height: 10),
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), Text(name)])));
  Widget dashboard() => ListView(children: [
    Text('Welcome, ${widget.profile['name'] ?? 'Owner'}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8), const Text('PG overview (all billing periods)'), const SizedBox(height: 12),
    Row(children: [Expanded(child: metric('Residents', '${summary['residents'] ?? '—'}', Icons.people)), Expanded(child: metric('Open complaints', '${summary['open_tickets'] ?? '—'}', Icons.build))]),
    Row(children: [Expanded(child: metric('Rent collected', '₹${summary['collected'] ?? '—'}', Icons.check_circle)), Expanded(child: metric('Outstanding', '₹${summary['outstanding'] ?? '—'}', Icons.account_balance_wallet))]),
    const SizedBox(height: 12),
    ListTile(title: const Text('Rent & resident payment status'), trailing: const Icon(Icons.chevron_right), onTap: () => setState(() => selected = 2)),
    ListTile(title: const Text('Complaints & maintenance'), trailing: const Icon(Icons.chevron_right), onTap: () => setState(() => selected = 3)),
    ListTile(title: const Text('Residents'), trailing: const Icon(Icons.chevron_right), onTap: () => setState(() => selected = 1)),
  ]);
  Widget residentList() => ListView(children: [const Text('Residents', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
    if (residents.isEmpty) const ListTile(title: Text('No residents yet')),
    ...residents.map((r) => Card(child: ListTile(leading: const Icon(Icons.person),title: Text('${r['name']}'),subtitle: Text('Room ${r['room'] ?? '—'} • ${r['email'] ?? ''}'))))]);
  Widget rentList() => ListView(children: [const Text('Rent & payments', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
    const Text('Payments are confirmed only after verifying actual bank credit.'),
    const SizedBox(height: 12),
    ...invoices.map((i) => Card(child: ListTile(title: Text('Resident #${i['resident_id']} • ${i['period']}'),subtitle: Text('Billed ₹${i['amount']} • Paid ₹${i['paid']}'),trailing: Text('₹${i['outstanding']}')))),
    const SizedBox(height: 12), const Text('Payment submissions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    ...payments.map((p) => Card(child: ListTile(title: Text('₹${p['amount']} • ${p['status']}'),subtitle: Text('Resident #${p['resident_id']} • Reference: ${p['reference']}'),
      trailing: p['status'] == 'pending' && widget.profile['role'] == 'owner' ? PopupMenuButton<String>(
        onSelected: (decision) => verifyPayment(p, decision), itemBuilder: (_) => const [
          PopupMenuItem(value: 'approved', child: Text('Approve after bank verification')),
          PopupMenuItem(value: 'rejected', child: Text('Reject')),
        ]) : null))),
  ]);
  Future<void> verifyPayment(dynamic payment, String decision) async {
    final confirmation = await showDialog<bool>(context: context,builder: (ctx) => AlertDialog(
      title: Text(decision == 'approved' ? 'Confirm bank credit' : 'Reject payment'),
      content: Text(decision == 'approved' ? 'Approve only after checking that ₹${payment['amount']} reached the correct bank account. Reference: ${payment['reference']}' : 'Reject this submitted payment reference?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false),child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx,true),child: const Text('Confirm'))]));
    if (confirmation != true) return;
    try { await widget.api('/payments/${payment['id']}/verify',method:'POST',body:{'decision':decision}); await refresh(); }
    catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e'))); }
  }
  Widget issuesList() => ListView(children: [const Text('Complaints',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
    ...tickets.map((t) => Card(child: ListTile(title:Text('${t['category']} • ${t['status']}'),subtitle: Text('${t['description']}'),
      trailing: PopupMenuButton<String>(onSelected: (status) async {
        try { await widget.api('/tickets/${t['id']}',method:'PATCH',body:{'status':status}); await refresh(); }
        catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e'))); }
      },itemBuilder: (_) => const ['submitted','assigned','in_progress','resolved','reopened'].map((s) => PopupMenuItem<String>(value:s,child:Text(s))).toList()))))]);
  Widget account() => ListView(children: [
    Text('${widget.profile['tenant']?['name'] ?? 'Your PG'}',style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
    ListTile(title:Text('${widget.profile['name']}'),subtitle:Text('Role: ${widget.profile['role']}')),
    ElevatedButton(onPressed: widget.logout, child:const Text('Log out')),
  ]);
  @override Widget build(BuildContext context) {
    final pages = [dashboard(),residentList(),rentList(),issuesList(),account()];
    return Scaffold(appBar: AppBar(title: Text('${widget.profile['tenant']?['name'] ?? 'PG'}'),actions:[IconButton(onPressed:refresh,icon:const Icon(Icons.refresh))]),
      body: Padding(padding:const EdgeInsets.all(12),child: Column(children:[if (loading) const LinearProgressIndicator(),if(error!=null) Text(error!,style:const TextStyle(color:Colors.red)), Expanded(child:pages[selected])])),
      bottomNavigationBar: NavigationBar(selectedIndex:selected,onDestinationSelected:(n)=>setState(()=>selected=n),indicatorColor:lavender,destinations:const [
        NavigationDestination(icon:Icon(Icons.dashboard_outlined),label:'Home'),NavigationDestination(icon:Icon(Icons.people_outline),label:'Residents'),
        NavigationDestination(icon:Icon(Icons.wallet_outlined),label:'Rent'),NavigationDestination(icon:Icon(Icons.build_outlined),label:'Issues'),
        NavigationDestination(icon:Icon(Icons.person_outline),label:'Profile')
      ]));
  }
}
