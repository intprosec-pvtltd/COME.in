import 'dart:async';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api_client.dart';

// The values below are Firebase *client app identifiers*, not service-account keys.
// Set them with --dart-define or FlutterFire during build. Missing config disables push.
class StaySyncPush {
  static const _apiKey=String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId=String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId=String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _projectId=String.fromEnvironment('FIREBASE_PROJECT_ID');
  static bool get configured=>[_apiKey,_appId,_senderId,_projectId].every((x)=>x.isNotEmpty);
  static final _channel=MethodChannel('staysync/notifications');
  static ApiClient? _client;
  static String? _registeredIdentity;
  static StreamSubscription<String>? _tokenChanges;
  static StreamSubscription<RemoteMessage>? _messages;

  static Future<void> initialize() async {
    if (!configured) return;
    try {
      await Firebase.initializeApp(options:const FirebaseOptions(
        apiKey:_apiKey,appId:_appId,messagingSenderId:_senderId,projectId:_projectId));
      await FirebaseMessaging.instance.requestPermission(alert:true,badge:true,sound:true);
      _messages??=FirebaseMessaging.onMessage.listen((msg) async {
        final notification=msg.notification;
        if(notification==null)return;
        try { await _channel.invokeMethod('show',{'title':notification.title??'Stay Sync Manage','body':notification.body??'New PG update'}); }
        catch (_) { /* In-app alert remains available. */ }
      });
    } catch (_) { /* Keep existing in-app notifications working without Firebase. */ }
  }

  static Future<void> register(ApiClient client, String identity) async {
    if(!configured || client.token==null || identity.isEmpty)return;
    _client=client;
    if(_registeredIdentity==identity)return;
    try {
      // Legacy FCM token is required by the current FastAPI push-device API.
      // ignore: deprecated_member_use
      final token=await FirebaseMessaging.instance.getToken();
      if(token==null || token.isEmpty)return;
      await client.request('/v3/push-tokens',method:'POST',body:{'token':token,'platform':'android'});
      _registeredIdentity=identity;
      // Legacy refresh stream; migrate together with server-side FID delivery.
      // ignore: deprecated_member_use
      _tokenChanges??=FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        final active=_client;
        if(active==null || active.token==null)return;
        try {await active.request('/v3/push-tokens',method:'POST',body:{'token':newToken,'platform':'android'});}catch(_){ }
      });
    } catch (_) { /* Registration will be retried next signed-in refresh. */ }
  }

  static Future<void> unregister() async {
    final active=_client;
    if(configured && active!=null && active.token!=null) {
      try {
        // Legacy FCM token is required by the current FastAPI push-device API.
      // ignore: deprecated_member_use
      final token=await FirebaseMessaging.instance.getToken();
        if(token!=null)await active.request('/v3/push-tokens',method:'DELETE',body:{'token':token,'platform':'android'});
      } catch (_) { }
    }
    _registeredIdentity=null;
    _client=null;
    await _tokenChanges?.cancel();_tokenChanges=null;
  }
}
