/// The map of "Ember Bastion", shared by the scene builder and the art tool
/// (tool/painted), so the painted road is exactly where enemies walk.
class BastionLayout {
  /// The road, from the cave on the left to the keep on the right.
  static const List<(double, double)> path = [
    (-40, 112), (196, 112), (196, 352), (428, 352), (428, 168), (668, 168), (668, 396), (852, 396), (852, 256), (1010, 256),
  ];

  /// Road width in pixels.
  static const double roadWidth = 46;

  /// Towers sit on a grid of this size.
  static const double cell = 40;

  /// Where towers may go (the HUD bars are outside it).
  static const double buildTop = 56, buildBottom = 456;

  /// Trees and rocks: (x, y, kind) with kind 0 round tree, 1 pine, 2 rock, 3 bush.
  static const List<(double, double, int)> decor = [
    (60, 220, 0), (100, 300, 1), (60, 420, 0), (300, 80, 1), (340, 250, 2), (300, 440, 3), (540, 270, 0),
    (560, 420, 1), (520, 80, 3), (780, 90, 0), (760, 300, 2), (900, 140, 1), (920, 400, 0), (620, 300, 3),
  ];
}
