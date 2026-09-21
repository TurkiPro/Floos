/// Normalization for matching a bank-supplied merchant or transfer
/// destination against a remembered decision about it.
///
/// Pure and dependency-free, like the rest of `lib/domain/`. The parser
/// ([bank_sms.dart]) has already stripped the `SA /` country prefix and the
/// trailing `*` the bank uses to mark a truncated name, so what arrives here
/// is the merchant string itself.
library;

/// Turns a bank-supplied party string into a stable lookup key: trimmed,
/// case-folded, and with runs of whitespace collapsed to one space.
///
/// The same merchant reaches different senders with different spacing
/// ("SA /KR-133" vs "SA/KR-133"), so the key has to be insensitive to it.
String partyKey(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Whether [a] and [b] name the same party despite the bank having truncated
/// one of them.
///
/// Messages arrive with names cut off at a fixed width and marked with a
/// trailing `*` — "SALAT ASIA*", "Ali bin Ab*", "eski kebap*". Because the cut
/// is at a fixed width it is *stable*: the same merchant truncates to the same
/// string every time, so the short form works as a key on its own. This exists
/// for the other direction — recognising a truncated name when the rule was
/// saved under the full one (or vice versa).
///
/// Prefix matching is a heuristic, so it is deliberately conservative:
/// [minPrefix] stops short keys from colliding with everything ("stc" must not
/// match "stc pay"). Callers should try an exact match first — see
/// `PartyRuleDao.lookup`, where exact always wins.
bool partyMatches(String a, String b, {int minPrefix = 6}) {
  final keyA = partyKey(a);
  final keyB = partyKey(b);
  if (keyA.isEmpty || keyB.isEmpty) return false;
  if (keyA == keyB) return true;
  final shorter = keyA.length <= keyB.length ? keyA : keyB;
  final longer = keyA.length <= keyB.length ? keyB : keyA;
  if (shorter.length < minPrefix) return false;
  return longer.startsWith(shorter);
}
