import 'package:flutter_test/flutter_test.dart';
import 'package:floos/domain/party_key.dart';

void main() {
  group('partyKey', () {
    test('trims, case-folds and collapses whitespace', () {
      expect(partyKey('  RED   BOX '), partyKey('red box'));
      expect(partyKey('RED BOX'), 'red box');
      expect(partyKey('AMAZON  SA'), 'amazon sa');
    });

    test('leaves account-number style parties alone', () {
      expect(partyKey('**7772'), '**7772');
      expect(partyKey('KR-133'), 'kr-133');
    });
  });

  group('partyMatches', () {
    test('an exact match', () {
      expect(partyMatches('RED BOX', 'red box'), isTrue);
    });

    test('recognises a name the bank truncated', () {
      // The bank sends "Ali bin Ab*"; the rule may have been saved under the
      // full name (or the other way round).
      expect(partyMatches('Ali bin Ab', 'Ali bin Abi Taleb'), isTrue);
      expect(partyMatches('Ali bin Abi Taleb', 'Ali bin Ab'), isTrue);
      expect(partyMatches('eski kebap', 'eski kebap house'), isTrue);
    });

    test('a short key must not collide with everything', () {
      // "stc" is only three characters — letting it prefix-match would file
      // every STC-something merchant under one rule.
      expect(partyMatches('stc', 'stc pay'), isFalse);
      expect(partyMatches('sa', 'salat asia'), isFalse);
    });

    test('unrelated parties do not match', () {
      expect(partyMatches('amazon sa', 'apple'), isFalse);
      expect(partyMatches('RED BOX', 'BLUE BOX'), isFalse);
      // A shared prefix that is long enough still has to be a real prefix.
      expect(partyMatches('salat asia', 'salad bar'), isFalse);
    });

    test('blank input never matches', () {
      expect(partyMatches('', 'red box'), isFalse);
      expect(partyMatches('red box', '   '), isFalse);
    });
  });
}
