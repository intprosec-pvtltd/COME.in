import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pg_resident/features/auth/phone_verification.dart';
import 'package:pg_resident/features/community/chat.dart';

void main() {
  test('normalizes Indian and international numbers without accepting email', () {
    expect(normalizeMobile('98765 43210'), '+919876543210');
    expect(normalizeMobile('919876543210'), '+919876543210');
    expect(normalizeMobile('+91 (98765) 43210'), '+919876543210');
    expect(normalizeMobile('+447911123456'), '+447911123456');
    expect(normalizeMobile('name@example.com'), isNull);
    expect(normalizeMobile('1234567890'), isNull);
  });
  test('sender colors are stable and nearby IDs have distinct colors', () {
    for (final mode in Brightness.values) {
      final colors = List.generate(16, (id) => communitySenderColor(id + 1, mode));
      expect(colors.toSet().length, 16);
      expect(communitySenderColor('2', mode), communitySenderColor(2, mode));
      expect(communitySenderColor(2, mode), communitySenderColor(2, mode));
    }
  });
  test('role badges are derived from explicit server roles', () {
    expect(communityRoleLabel('owner'), 'Owner');
    expect(communityRoleLabel('manager'), 'Manager');
    expect(communityRoleLabel('resident'), isNull);
    expect(communityRoleLabel(null), isNull);
  });
  test('sender palette meets AA contrast on both message surfaces', () {
    double ratio(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
    }
    for (var id = 0; id < 16; id++) {
      final light = communitySenderColor(id, Brightness.light);
      final dark = communitySenderColor(id, Brightness.dark);
      expect(ratio(light, Colors.white), greaterThanOrEqualTo(4.5));
      expect(ratio(light, const Color(0xFFF0E5FF)), greaterThanOrEqualTo(4.5));
      expect(ratio(dark, const Color(0xFF282033)), greaterThanOrEqualTo(4.5));
      expect(ratio(dark, const Color(0xFF403355)), greaterThanOrEqualTo(4.5));
    }
  });
}
