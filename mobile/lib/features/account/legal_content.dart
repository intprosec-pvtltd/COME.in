import 'package:flutter/material.dart';

const policyVersion = '2026-11-26-v1';

class LegalDocument extends StatelessWidget {
  const LegalDocument({super.key});

  static const privacy = <String, String>{
    'Who operates the app':
      'IntProSec Private Limited, Bengaluru, India, operates Stay Sync Manage. Contact info@intprosec.com for privacy questions and account or data requests.',
    'Information we use':
      'We use account names, contact and verified mobile details, organization roles, property and room assignments, rent records, payment references and proof, complaints, messages, attachments, notification preferences, and private app feedback to operate the service. If you submit identity proof or a photograph, it is used for manual review by authorized staff for your PG. Use masked Aadhaar or another accepted document.',
    'Who can see your data':
      'Access depends on your account role and PG. Authorized PG users see information needed for accommodation and service administration. Authorized IntProSec personnel can access records to operate and support the platform. Feedback is stored within the service for product improvement.',
    'Service providers':
      'When configured, Twilio handles SMS delivery using the destination number and verification message. Firebase Cloud Messaging handles push delivery using device registration tokens and notification data. Email delivery uses the configured Mailjet, Resend, or SMTP provider and receives the recipient address and message. The configured hosting and storage providers process application records on behalf of IntProSec.',
    'Storage and account requests':
      'We keep records while they are needed to operate your account, resolve disputes or meet applicable obligations. Contact info@intprosec.com to request access, correction or deletion. We may need to verify your identity and coordinate with your PG. Records required for accounting, security or other obligations may be retained for the applicable period.',
  };

  static const terms = <String, String>{
    'Use of Stay Sync Manage':
      'Stay Sync Manage helps PG owners and residents handle accommodation, notices, rent records and service requests. Provide accurate account information, keep your password and verification codes private, and use only the account and PG access you are authorized to use.',
    'Rent and verification':
      'Verify the payment recipient and amount in your bank or UPI app before paying. PG operators are responsible for checking received payments and reviewing resident documents. A manual review status does not establish government verification or certify authenticity.',
    'Content and support':
      'Upload only documents and messages you have permission to share. Avoid sending passwords, OTPs or unnecessary sensitive data in messages and feedback. For account or service questions, contact info@intprosec.com.',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy & terms')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Stay Sync Manage · IntProSec Private Limited'),
          const SizedBox(height: 8),
          const Text('Version $policyVersion'),
          for (final document in [('Privacy policy', privacy), ('Terms of use', terms)]) ...[
            const SizedBox(height: 22),
            Text(document.$1, style: Theme.of(context).textTheme.headlineSmall),
            for (final section in document.$2.entries) ...[
              const SizedBox(height: 16),
              Text(section.key, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              SelectableText(section.value),
            ],
          ],
        ],
      ),
    ),
  );
}
