/// Syntax validation only; does not establish ownership or mailbox existence.
String? emailError(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  final parts = value.split('@');
  if (value.length > 160 || parts.length != 2) return 'Enter a valid email address';
  final local = parts[0], domain = parts[1];
  if (local.isEmpty || local.length > 64 || local.startsWith('.') ||
      local.endsWith('.') || local.contains('..') ||
      !RegExp(r"^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$").hasMatch(local)) {
    return 'Enter a valid email address';
  }
  const typos = {'gmial.com','gamil.com','gmai.com','gmail.co','gmail.con','gmail.cm','gmail.om','gmail.comm','gmal.com','gmailcom'};
  if (typos.contains(domain)) return 'Did you mean gmail.com?';
  final labels = domain.split('.');
  if (labels.length < 2 || !RegExp(r'^[a-z]{2,63}$').hasMatch(labels.last) ||
      labels.any((v) => !RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$').hasMatch(v))) {
    return 'Enter a valid email address';
  }
  if ((domain == 'gmail.com' || domain == 'googlemail.com') &&
      !RegExp(r'^[a-z0-9]+(?:\.[a-z0-9]+)*(?:\+[a-z0-9._-]+)?$').hasMatch(local)) {
    return 'Enter a valid Gmail address';
  }
  return null;
}
