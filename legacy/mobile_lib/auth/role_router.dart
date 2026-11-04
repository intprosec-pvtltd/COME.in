import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../owner/owner_v2.dart';
import '../resident/resident_v2.dart';

class RoleRouter extends StatelessWidget {
  final Map<String, dynamic> profile;
  final ApiRequest api; final AttachmentUpload upload;
  final VoidCallback logout;
  const RoleRouter({super.key, required this.profile, required this.api, required this.upload, required this.logout});
  @override Widget build(BuildContext context) {
    switch (profile['role']) {
      case 'owner': case 'manager':
        return OwnerV2(api: api, upload: upload, profile: profile, logout: logout);
      case 'resident':
        return ResidentV2(api: api, upload: upload, profile: profile, logout: logout);
      default:
        return Scaffold(appBar: AppBar(title: const Text('Account access')),
          body: Center(child: Column(mainAxisSize:MainAxisSize.min,children:[
            const Text('This role does not yet have a mobile dashboard.'),
            const SizedBox(height:12), ElevatedButton(onPressed:logout,child:const Text('Log out'))
          ])));
    }
  }
}
