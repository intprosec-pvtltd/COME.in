import 'package:flutter/material.dart';
import '../app/controller.dart';

/// V28 UI localization catalog. Unknown strings safely fall back to English.
/// Language preference is local to the phone, not identity information.
const supportedLanguages = <String, String>{
 'en':'English', 'hi':'हिन्दी', 'ta':'தமிழ்',
 'te':'తెలుగు', 'kn':'ಕನ್ನಡ', 'ml':'മലയാളം',
};
final localizedLabels = <String, Map<String, String>>{
  'Language': {'en': 'Language', 'hi': 'भाषा', 'ta': 'மொழி', 'te': 'భాష', 'kn': 'ಭಾಷೆ', 'ml': 'ഭാഷ'},
  'Your account': {'en': 'Your account', 'hi': 'आपका खाता', 'ta': 'உங்கள் கணக்கு', 'te': 'మీ ఖాతా', 'kn': 'ನಿಮ್ಮ ಖಾತೆ', 'ml': 'നിങ്ങളുടെ അക്കൗണ്ട്'},
  'Profile, settings and essentials.': {'en': 'Profile, settings and essentials.', 'hi': 'प्रोफ़ाइल और सेटिंग्स', 'ta': 'சுயவிவரமும் அமைப்புகளும்', 'te': 'ప్రొఫైల్ మరియు సెట్టింగ్‌లు', 'kn': 'ಪ್ರೊಫೈಲ್ ಮತ್ತು ಸೆಟ್ಟಿಂಗ್‌ಗಳು', 'ml': 'പ്രൊഫൈലും ക്രമീകരണങ്ങളും'},
  'Preferences & security': {'en': 'Preferences & security', 'hi': 'प्राथमिकताएँ और सुरक्षा', 'ta': 'விருப்பங்களும் பாதுகாப்பும்', 'te': 'ప్రాధాన్యతలు మరియు భద్రత', 'kn': 'ಆದ್ಯತೆಗಳು ಮತ್ತು ಭದ್ರತೆ', 'ml': 'മുൻഗണനകളും സുരക്ഷയും'},
  'Business settings': {'en': 'Business settings', 'hi': 'व्यवसाय सेटिंग्स', 'ta': 'வணிக அமைப்புகள்', 'te': 'వ్యాపార సెట్టింగ్‌లు', 'kn': 'ವ್ಯಾಪಾರ ಸೆಟ್ಟಿಂಗ್‌ಗಳು', 'ml': 'ബിസിനസ് ക്രമീകരണങ്ങൾ'},
  'Change password': {'en': 'Change password', 'hi': 'पासवर्ड बदलें', 'ta': 'கடவுச்சொல்லை மாற்று', 'te': 'పాస్‌వర్డ్ మార్చండి', 'kn': 'ಪಾಸ್‌ವರ್ಡ್ ಬದಲಿಸಿ', 'ml': 'പാസ്‌വേഡ് മാറ്റുക'},
  'Log out': {'en': 'Log out', 'hi': 'लॉग आउट', 'ta': 'வெளியேறு', 'te': 'లాగ్ అవుట్', 'kn': 'ಲಾಗ್ ಔಟ್', 'ml': 'ലോഗ് ഔട്ട്'},
  'Appearance': {'en': 'Appearance', 'hi': 'दिखावट', 'ta': 'தோற்றம்', 'te': 'రూపం', 'kn': 'ಗೋಚರತೆ', 'ml': 'രൂപഭാവം'},
  'Help & support': {'en': 'Help & support', 'hi': 'सहायता', 'ta': 'உதவி', 'te': 'సహాయం', 'kn': 'ಸಹಾಯ', 'ml': 'സഹായം'},
  'Notifications': {'en': 'Notifications', 'hi': 'सूचनाएँ', 'ta': 'அறிவிப்புகள்', 'te': 'నోటిఫికేషన్లు', 'kn': 'ಅಧಿಸೂಚನೆಗಳು', 'ml': 'അറിയിപ്പുകൾ'},
  'Identity verification': {'en': 'Identity verification', 'hi': 'पहचान सत्यापन', 'ta': 'அடையாளச் சரிபார்ப்பு', 'te': 'గుర్తింపు ధృవీకరణ', 'kn': 'ಗುರುತಿನ ಪರಿಶೀಲನೆ', 'ml': 'ഐഡന്റിറ്റി പരിശോധന'},
  'Resident ID proof': {'en': 'Resident ID proof', 'hi': 'निवासी पहचान पत्र', 'ta': 'குடியிருப்பாளர் அடையாளச் சான்று', 'te': 'నివాసి గుర్తింపు పత్రం', 'kn': 'ನಿವಾಸಿಯ ಗುರುತಿನ ದಾಖಲೆ', 'ml': 'താമസക്കാരന്റെ തിരിച്ചറിയൽ രേഖ'},
  'Submit identity proof': {'en': 'Submit identity proof', 'hi': 'पहचान प्रमाण जमा करें', 'ta': 'அடையாளச் சான்றைச் சமர்ப்பிக்கவும்', 'te': 'గుర్తింపు పత్రం సమర్పించండి', 'kn': 'ಗುರುತಿನ ದಾಖಲೆ ಸಲ್ಲಿಸಿ', 'ml': 'തിരിച്ചറിയൽ രേഖ സമർപ്പിക്കുക'},
  'Payment details': {'en': 'Payment details', 'hi': 'भुगतान विवरण', 'ta': 'கட்டண விவரங்கள்', 'te': 'చెల్లింపు వివరాలు', 'kn': 'ಪಾವತಿ ವಿವರಗಳು', 'ml': 'പണമടയ്ക്കൽ വിവരങ്ങൾ'},
  'Submit payment': {'en': 'Submit payment', 'hi': 'भुगतान जमा करें', 'ta': 'கட்டணத்தைச் சமர்ப்பி', 'te': 'చెల్లింపు సమర్పించండి', 'kn': 'ಪಾವತಿ ಸಲ್ಲಿಸಿ', 'ml': 'പേയ്മെന്റ് സമർപ്പിക്കുക'},
  'View payment proof': {'en': 'View payment proof', 'hi': 'भुगतान प्रमाण देखें', 'ta': 'கட்டணச் சான்றைப் பார்', 'te': 'చెల్లింపు రుజువు చూడండి', 'kn': 'ಪಾವತಿ ಪುರಾವೆ ನೋಡಿ', 'ml': 'പണമടച്ചതിന്റെ തെളിവ് കാണുക'},
  'Approve payment': {'en': 'Approve payment', 'hi': 'भुगतान स्वीकृत करें', 'ta': 'கட்டணத்தை ஏற்கவும்', 'te': 'చెల్లింపును ఆమోదించండి', 'kn': 'ಪಾವತಿಯನ್ನು ಅನುಮೋದಿಸಿ', 'ml': 'പേയ്മെന്റ് അംഗീകരിക്കുക'},
  'Reject proof': {'en': 'Reject proof', 'hi': 'प्रमाण अस्वीकार करें', 'ta': 'சான்றை நிராகரி', 'te': 'రుజువును తిరస్కరించండి', 'kn': 'ಪುರಾವೆಯನ್ನು ತಿರಸ್ಕರಿಸಿ', 'ml': 'തെളിവ് നിരസിക്കുക'},
  'Home': {'en': 'Home', 'hi': 'होम', 'ta': 'முகப்பு', 'te': 'హోమ్', 'kn': 'ಮುಖಪುಟ', 'ml': 'ഹോം'},
  'Account': {'en': 'Account', 'hi': 'खाता', 'ta': 'கணக்கு', 'te': 'ఖాతా', 'kn': 'ಖಾತೆ', 'ml': 'അക്കൗണ്ട്'},
  'Rent': {'en': 'Rent', 'hi': 'किराया', 'ta': 'வாடகை', 'te': 'అద్దె', 'kn': 'ಬಾಡಿಗೆ', 'ml': 'വാടക'},
  'Residents': {'en': 'Residents', 'hi': 'निवासी', 'ta': 'குடியிருப்பாளர்கள்', 'te': 'నివాసులు', 'kn': 'ನಿವಾಸಿಗಳು', 'ml': 'താമസക്കാർ'},
  'Rooms': {'en': 'Rooms', 'hi': 'कमरे', 'ta': 'அறைகள்', 'te': 'గదులు', 'kn': 'ಕೊಠಡಿಗಳು', 'ml': 'മുറികൾ'},
  'Complaints': {'en': 'Complaints', 'hi': 'शिकायतें', 'ta': 'புகார்கள்', 'te': 'ఫిర్యాదులు', 'kn': 'ದೂರುಗಳು', 'ml': 'പരാതികൾ'},
  'Payments': {'en': 'Payments', 'hi': 'भुगतान', 'ta': 'கட்டணங்கள்', 'te': 'చెల్లింపులు', 'kn': 'ಪಾವತಿಗಳು', 'ml': 'പേയ്മെന്റുകൾ'},
  'Pending': {'en': 'Pending', 'hi': 'लंबित', 'ta': 'நிலுவையில்', 'te': 'పెండింగ్', 'kn': 'ಬಾಕಿ', 'ml': 'തീർപ്പാകാത്തത്'},
  'Approved': {'en': 'Approved', 'hi': 'स्वीकृत', 'ta': 'ஏற்கப்பட்டது', 'te': 'ఆమోదించబడింది', 'kn': 'ಅನುಮೋದಿಸಲಾಗಿದೆ', 'ml': 'അംഗീകരിച്ചു'},
  'Rejected': {'en': 'Rejected', 'hi': 'अस्वीकृत', 'ta': 'நிராகரிக்கப்பட்டது', 'te': 'తిరస్కరించబడింది', 'kn': 'ತಿರಸ್ಕರಿಸಲಾಗಿದೆ', 'ml': 'നിരസിച്ചു'},
  'Welcome back!': {'en': 'Welcome back!', 'hi': 'वापसी पर स्वागत है!', 'ta': 'மீண்டும் வரவேற்கிறோம்!', 'te': 'తిరిగి స్వాగతం!', 'kn': 'ಮತ್ತೆ ಸ್ವಾಗತ!', 'ml': 'വീണ്ടും സ്വാഗതം!'},
  'Same spaces. Brighter days.': {'en': 'Same spaces. Brighter days.', 'hi': 'वही जगह। बेहतर दिन।', 'ta': 'அதே இடம். இனிய நாட்கள்.', 'te': 'అదే స్థలం. మెరుగైన రోజులు.', 'kn': 'ಅದೇ ಸ್ಥಳ. ಉತ್ತಮ ದಿನಗಳು.', 'ml': 'അതേ ഇടം. നല്ല നാളുകൾ.'},
  'Keep me signed in': {'en': 'Keep me signed in', 'hi': 'मुझे लॉग इन रखें', 'ta': 'உள்நுழைந்தே வைத்திரு', 'te': 'లాగిన్ కొనసాగించు', 'kn': 'ಲಾಗಿನ್ ಆಗಿಯೇ ಇರಿಸಿ', 'ml': 'ലോഗിൻ നിലനിർത്തുക'},
  'Forgot password?': {'en': 'Forgot password?', 'hi': 'पासवर्ड भूल गए?', 'ta': 'கடவுச்சொல் மறந்துவிட்டதா?', 'te': 'పాస్‌వర్డ్ మర్చిపోయారా?', 'kn': 'ಪಾಸ್‌ವರ್ಡ್ ಮರೆತಿರಾ?', 'ml': 'പാസ്‌വേഡ് മറന്നോ?'},
  'Sign in': {'en': 'Sign in', 'hi': 'साइन इन', 'ta': 'உள்நுழைக', 'te': 'సైన్ ఇన్', 'kn': 'ಸೈನ್ ಇನ್', 'ml': 'സൈൻ ഇൻ'},
  'Create account': {'en': 'Create account', 'hi': 'खाता बनाएँ', 'ta': 'கணக்கை உருவாக்கு', 'te': 'ఖాతా సృష్టించండి', 'kn': 'ಖಾತೆ ರಚಿಸಿ', 'ml': 'അക്കൗണ്ട് സൃഷ്ടിക്കുക'},
  'Email or Phone': {'en': 'Email or Phone', 'hi': 'ईमेल या फ़ोन', 'ta': 'மின்னஞ்சல் அல்லது தொலைபேசி', 'te': 'ఇమెయిల్ లేదా ఫోన్', 'kn': 'ಇಮೇಲ್ ಅಥವಾ ಫೋನ್', 'ml': 'ഇമെയിൽ അല്ലെങ്കിൽ ഫോൺ'},
  'Password': {'en': 'Password', 'hi': 'पासवर्ड', 'ta': 'கடவுச்சொல்', 'te': 'పాస్‌వర్డ్', 'kn': 'ಪಾಸ್‌ವರ್ಡ್', 'ml': 'പാസ്‌വേഡ്'},
  'Open document': {'en': 'Open document', 'hi': 'दस्तावेज़ खोलें', 'ta': 'ஆவணத்தைத் திற', 'te': 'పత్రం తెరవండి', 'kn': 'ದಾಖಲೆ ತೆರೆಯಿರಿ', 'ml': 'രേഖ തുറക്കുക'},
  'Approve': {'en': 'Approve', 'hi': 'स्वीकृत करें', 'ta': 'ஏற்கவும்', 'te': 'ఆమోదించండి', 'kn': 'ಅನುಮೋದಿಸಿ', 'ml': 'അംഗീകരിക്കുക'},
  'Reject': {'en': 'Reject', 'hi': 'अस्वीकार करें', 'ta': 'நிராகரி', 'te': 'తిరస్కరించండి', 'kn': 'ತಿರಸ್ಕರಿಸಿ', 'ml': 'നിരസിക്കുക'},
  'Risk review': {'en': 'Risk review', 'hi': 'जोखिम समीक्षा', 'ta': 'ஆபத்து மதிப்பாய்வு', 'te': 'ప్రమాద సమీక్ష', 'kn': 'ಅಪಾಯ ಪರಿಶೀಲನೆ', 'ml': 'അപകടസാധ്യത പരിശോധന'},
  'Authenticity not verified': {'en': 'Authenticity not verified', 'hi': 'प्रामाणिकता सत्यापित नहीं', 'ta': 'உண்மைத்தன்மை சரிபார்க்கப்படவில்லை', 'te': 'ప్రామాణికత నిర్ధారించబడలేదు', 'kn': 'ನೈಜತೆ ದೃಢೀಕರಿಸಲಾಗಿಲ್ಲ', 'ml': 'ആധികാരികത പരിശോധിച്ചിട്ടില്ല'},
  'Check bank credit before approval': {'en': 'Check bank credit before approval', 'hi': 'स्वीकृति से पहले बैंक क्रेडिट जाँचें', 'ta': 'ஏற்குமுன் வங்கி வரவைச் சரிபார்', 'te': 'ఆమోదానికి ముందు బ్యాంక్ క్రెడిట్ చూడండి', 'kn': 'ಅನುಮೋದನೆ ಮೊದಲು ಬ್ಯಾಂಕ್ ಜಮೆ ಪರಿಶೀಲಿಸಿ', 'ml': 'അംഗീകരിക്കുന്നതിന് മുമ്പ് ബാങ്ക് വരവ് പരിശോധിക്കുക'},
  'No flags found': {'en': 'No flags found', 'hi': 'कोई संकेत नहीं मिला', 'ta': 'சந்தேக அறிகுறிகள் இல்லை', 'te': 'అనుమాన సూచనలు లేవు', 'kn': 'ಯಾವುದೇ ಸೂಚನೆಗಳಿಲ್ಲ', 'ml': 'സംശയ സൂചനകളില്ല'},
  'Possible duplicate': {'en': 'Possible duplicate', 'hi': 'संभावित डुप्लीकेट', 'ta': 'நகலாக இருக்கலாம்', 'te': 'నకిలీ ప్రతిగా ఉండవచ్చు', 'kn': 'ನಕಲು ಆಗಿರಬಹುದು', 'ml': 'പകർപ്പായിരിക്കാം'},
  'Not a government verification': {'en': 'Not a government verification', 'hi': 'यह सरकारी सत्यापन नहीं है', 'ta': 'இது அரசு சரிபார்ப்பு அல்ல', 'te': 'ఇది ప్రభుత్వ ధృవీకరణ కాదు', 'kn': 'ಇದು ಸರ್ಕಾರಿ ಪರಿಶೀಲನೆ ಅಲ್ಲ', 'ml': 'ഇത് സർക്കാർ പരിശോധനയല്ല'},
};
String tr(BuildContext context, String english) {
 final language = Localizations.localeOf(context).languageCode;
 return localizedLabels[english]?[language] ?? english;
}
class LanguagePicker extends StatelessWidget {
 const LanguagePicker({super.key});
 @override Widget build(BuildContext context) {
  final app=AppScope.of(context);
  return DropdownButtonFormField<String>(
   key:ValueKey(app.languageCode),
   initialValue:app.languageCode,
   isExpanded:true,
   decoration:InputDecoration(labelText:tr(context,'Language'), prefixIcon:const Icon(Icons.language)),
   items:supportedLanguages.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),
   onChanged:(v) {if(v!=null)app.setLanguage(v);},
  );
 }
}
