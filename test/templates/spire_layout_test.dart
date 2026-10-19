import 'package:flutter_test/flutter_test.dart';
import 'package:ember_engine/templates/spire_layout.dart';

void main() {
  test('every room is 30 × 17 and the doorways between rooms line up', () {
    for (final entry in SpireLayout.rooms.entries) {
      final (name, rows) = entry.value;
      expect(rows, hasLength(SpireLayout.roomRows), reason: name);
      for (var i = 0; i < rows.length; i++) {
        expect(rows[i].length, SpireLayout.roomColumns, reason: '$name row $i');
      }
    }
    String at((int, int) room, int c, int r) => SpireLayout.rooms[room]!.$2[r][c];
    bool open(String ch) => ch != '#';
    for (final (rc, rr) in SpireLayout.rooms.keys) {
      if (rc < 2) {
        for (var r = 0; r < SpireLayout.roomRows; r++) {
          expect(open(at((rc, rr), 29, r)), open(at((rc + 1, rr), 0, r)), reason: 'room ($rc,$rr) right edge row $r');
        }
      } else {
        for (var r = 0; r < SpireLayout.roomRows; r++) {
          expect(at((rc, rr), 29, r), '#', reason: 'outer wall ($rc,$rr) row $r');
        }
      }
      if (rr < 2) {
        for (var c = 0; c < SpireLayout.roomColumns; c++) {
          expect(open(at((rc, rr), c, 16)), open(at((rc, rr + 1), c, 0)), reason: 'room ($rc,$rr) bottom edge column $c');
        }
      }
    }
  });

  test('the map has one start, the goal, the boss, the three abilities, shrines, hearts and gems', () {
    final things = SpireLayout.things().map((t) => t.$1).toList();
    expect(things.where((t) => t == 'P'), hasLength(1));
    expect(things.where((t) => t == 'E'), hasLength(1));
    expect(things.where((t) => t == 'B'), hasLength(1));
    for (final a in ['D', 'H', 'W']) {
      expect(things.where((t) => t == a), hasLength(1), reason: a);
    }
    expect(things.where((t) => t == 'S').length, greaterThanOrEqualTo(2));
    expect(things.where((t) => t == 'h'), hasLength(2));
    expect(things.where((t) => t == 'g'), hasLength(3));
    expect(SpireLayout.tiles(), hasLength(SpireLayout.columns * SpireLayout.rows));
  });
}
