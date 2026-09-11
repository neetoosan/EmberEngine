
/// Supported types for inspectable properties in the Ember Engine Inspector.
enum InspectableType {
  number,
  integer,
  boolean,
  string,
  color,
  vector2,
  vector3,
  vector4,
  quaternion,
  options,
  anchor,
  assetReference,
}

/// Metadata definition for a property exposed to the Ember Engine Inspector.
class InspectableProperty<T> {
  final String name;
  final String label;
  final InspectableType type;
  final T Function() getter;
  final void Function(T value) setter;
  final double? min;
  final double? max;
  final double step;
  final List<String>? options;
  final String? group;
  final String? tooltip;

  const InspectableProperty({
    required this.name,
    required this.label,
    required this.type,
    required this.getter,
    required this.setter,
    this.min,
    this.max,
    this.step = 0.1,
    this.options,
    this.group,
    this.tooltip,
  });

  T get value => getter();
  set value(T val) => setter(val);

  dynamic getValue() => getter();
  void setValue(dynamic val) => setter(val as T);
}
/// Annotation for marking fields as inspectable in Ember Engine components.
class Inspectable {
  final String? label;
  final double? min;
  final double? max;
  final double step;
  final String? group;
  final String? tooltip;
  final List<String>? options;

  const Inspectable({
    this.label,
    this.min,
    this.max,
    this.step = 0.1,
    this.group,
    this.tooltip,
    this.options,
  });
}
