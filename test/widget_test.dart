import 'package:flutter_test/flutter_test.dart';

import 'package:layered_launcher/screens/home/home_screen.dart'
    show floorLabel;

void main() {
  group('floorLabel', () {
    test('0F is HOME', () {
      expect(floorLabel(0), 'HOME');
    });

    test('positive floors', () {
      expect(floorLabel(1), '1F');
      expect(floorLabel(10), '10F');
    });

    test('basement floors', () {
      expect(floorLabel(-1), 'B1F');
      expect(floorLabel(-10), 'B10F');
    });
  });
}
