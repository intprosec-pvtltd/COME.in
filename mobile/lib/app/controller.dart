import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../core/session_manager.dart';
class AppController extends ChangeNotifier {
  AppController({
    ApiClient? client
  }) : api = client ?? ApiClient();
  final ApiClient api;
  final SessionManager sessions = SessionManager();
  Map<String,
  dynamic> data = {
  };
  String languageCode = 'en';
  /// Persist the chosen language and refresh the entire app.
  Future<void> setLanguage(String code) async {
    if (!const ['en', 'hi', 'ta', 'te', 'kn', 'ml'].contains(code)) return;
    if (languageCode == code) return;
    await (await SharedPreferences.getInstance()).setString('language_code', code);
    languageCode = code;
    notifyListeners();
  }
  bool restoring = true,
  onboardingSeen = false,
  busy = false;
  String? error;
  int? propertyId;
  String period = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
  Map<String,
  dynamic> get profile => Map<String,
  dynamic>.from(data[
    'profile'
  ] as Map? ?? {
  });
  bool get signedIn => profile.isNotEmpty;
  bool get owner => [
    'owner',
    'manager'
  ].contains(profile[
    'role'
  ]);
  bool get staff => profile[
    'role'
  ]=='staff';
  List<Map<String,
  dynamic>> rows(String key) => (data[
    key
  ] as List? ?? [
  ]).map((v)=>Map<String,
  dynamic>.from(v as Map)).toList();
  List<Map<String,
  dynamic>> scoped(String key) => rows(key).where((r)=>propertyId==null||(r[
    'property_id'
  ]??0)==propertyId).toList();
  Map<String,
  dynamic>? find(String key,
  int? id) {
    for(final r in rows(key)){
      if(r[
        'id'
      ]==id)return r;
    }return null;
  } ThemeMode get themeMode => switch ((profile[
    'preferences'
  ] as Map?)?[
    'appearance'
  ]) {
    'Dark'=>ThemeMode.dark,
    'System'=>ThemeMode.system,
    _=>ThemeMode.light
  };
  Future<void> initialize() async {
    final prefs=await SharedPreferences.getInstance();
    onboardingSeen=prefs.getBool('onboarding_seen')??false;
    final code=prefs.getString('language_code')??'en';
    languageCode=['en','hi','ta','te','kn','ml'].contains(code)?code:'en';
    try {
      api.token=await sessions.restoreToken();
      if(api.token!=null)await refresh();
    } catch(e){
      error='$e';
      if(e is ApiException && [
        401,
        403
      ].contains(e.statusCode)){
        api.token=null;
        await sessions.clear();
      }
    } restoring=false;
    notifyListeners();
  } Future<void> finishOnboarding() async {
    onboardingSeen=true;
    await (await SharedPreferences.getInstance()).setBool('onboarding_seen',
    true);
    notifyListeners();
  } Future<void> login(String email,
  String password,
  bool remember) async {
    final result=await api.request('/login',
    method:'POST',
    body:{
      'email':email,
      'password':password
    });
    api.token=result[
      'token'
    ] as String?;
    if(api.token==null)throw const ApiException(0,
    'No session returned');
    try{
      await refresh();
      if(remember)await sessions.saveToken(api.token!);
      else await sessions.clear();
    } catch(e){
      api.token=null;
      data={
      };
      rethrow;
    }
  } Future<void> refresh() async {
    final result=await api.request('/v3/state');
    data=Map<String,
    dynamic>.from(result as Map);
    error=null;
    notifyListeners();
  } Future<dynamic> mutate(String path,
  {
    String method='POST',
    Map<String,
    dynamic>? body
  }) async {
    final result=await api.request(path,
    method:method,
    body:body);
    await refresh();
    return result;
  } Future<void> save(String kind,
  Map<String,
  dynamic> value,
  {
    int? id
  }) async {
    await mutate('/v3/entities/$kind${id==null?'':'/$id'}',
    method:id==null?'POST':'PUT',
    body:value);
  } Future<void> updateProfile(Map<String,
  dynamic> value) async {
    await mutate('/v3/profile',
    method:'PATCH',
    body:value);
  } Future<void> logout() async {
    try{
      if(api.token!=null)await api.request('/v3/logout',
      method:'POST');
    }finally{
      api.token=null;
      data={
      };
      propertyId=null;
      await sessions.clear();
      notifyListeners();
    }
  } void selectProperty(int? id){
    propertyId=id;
    notifyListeners();
  } void selectPeriod(String value){
    period=value;
    notifyListeners();
  }
} class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child
  }):super(notifier:controller);
  static AppController of(BuildContext context)=>context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
} double amount(dynamic value)=>double.tryParse('$value')??0;
