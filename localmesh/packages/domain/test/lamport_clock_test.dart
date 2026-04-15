import 'package:test/test.dart';
import 'package:domain/domain.dart';

void main() {
  group('LamportClock', () {
    test('initial value is 0', () {
      final clock = LamportClock();
      expect(clock.value, 0);
    });

    test('tick increments by 1 each call', () {
      final clock = LamportClock();
      expect(clock.tick(), 1);
      expect(clock.tick(), 2);
      expect(clock.tick(), 3);
      expect(clock.value, 3);
    });

    test('merge(5) when clock is 2 sets it to 6 — max(2,5)+1', () {
      final clock = LamportClock(initialValue: 2);
      expect(clock.merge(5), 6);
      expect(clock.value, 6);
    });

    test('merge(1) when clock is 10 sets it to 11 — max(10,1)+1', () {
      final clock = LamportClock(initialValue: 10);
      expect(clock.merge(1), 11);
      expect(clock.value, 11);
    });

    test('reset returns clock to 0', () {
      final clock = LamportClock(initialValue: 5);
      clock.tick();
      clock.reset();
      expect(clock.value, 0);
    });
  });
}
