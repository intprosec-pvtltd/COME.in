import 'package:flutter_test/flutter_test.dart';
import 'package:pg_resident/core/localization.dart';

void main() {
 test('six supported COME.in languages are registered', () {
  expect(supportedLanguages.keys.toSet(), {'en','hi','ta','te','kn','ml'});
  expect(localizedLabels['Your account']!.length,6);
  for(final language in supportedLanguages.keys) {
   expect(localizedLabels['Your account']![language]!.isNotEmpty,isTrue);
  }
 });
}
