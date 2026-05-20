import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:codehunt/storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Storage.feedback', () {
    test('round-trip set/get/clear', () async {
      expect(await Storage.getFeedback('example.com', 'CODE10'), isNull);

      await Storage.setFeedback('example.com', 'CODE10', Storage.feedbackWorked);
      expect(
        await Storage.getFeedback('example.com', 'CODE10'),
        Storage.feedbackWorked,
      );

      await Storage.setFeedback('example.com', 'CODE10', Storage.feedbackDidntWork);
      expect(
        await Storage.getFeedback('example.com', 'CODE10'),
        Storage.feedbackDidntWork,
      );

      await Storage.setFeedback('example.com', 'CODE10', null);
      expect(await Storage.getFeedback('example.com', 'CODE10'), isNull);
    });

    test('domain isolation', () async {
      await Storage.setFeedback('a.com', 'XYZ', Storage.feedbackWorked);
      await Storage.setFeedback('b.com', 'XYZ', Storage.feedbackDidntWork);
      expect(await Storage.getFeedback('a.com', 'XYZ'), Storage.feedbackWorked);
      expect(await Storage.getFeedback('b.com', 'XYZ'), Storage.feedbackDidntWork);
    });

    test('getFeedbackForDomain returns the per-code map', () async {
      await Storage.setFeedback('shop.com', 'A', Storage.feedbackWorked);
      await Storage.setFeedback('shop.com', 'B', Storage.feedbackDidntWork);
      final map = await Storage.getFeedbackForDomain('shop.com');
      expect(map['A'], Storage.feedbackWorked);
      expect(map['B'], Storage.feedbackDidntWork);
      expect(map.length, 2);
    });
  });

  group('Storage.pinned', () {
    test('toggle on then off', () async {
      expect(await Storage.isPinned('foo.com'), isFalse);
      expect(await Storage.togglePin('foo.com'), isTrue);
      expect(await Storage.isPinned('foo.com'), isTrue);
      expect(await Storage.togglePin('foo.com'), isFalse);
      expect(await Storage.isPinned('foo.com'), isFalse);
    });
  });

  group('Storage.clearAll', () {
    test('wipes history, pins, cache, feedback', () async {
      await Storage.recordHunt('one.com');
      await Storage.togglePin('one.com');
      await Storage.setFeedback('one.com', 'X', Storage.feedbackWorked);

      await Storage.clearAll();

      expect(await Storage.history(), isEmpty);
      expect(await Storage.pinned(), isEmpty);
      expect(await Storage.getFeedback('one.com', 'X'), isNull);
    });
  });
}
