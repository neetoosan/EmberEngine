import 'package:flutter/material.dart';

/// PBR-inspired material definition for 3D meshes in Ember Engine.
class Material3D {
  Color color;
  double roughness;
  double metallic;
  bool wireframe;
  double opacity;

  Material3D({
    this.color = const Color(0xFF6366F1), // Default Ember Indigo
    this.roughness = 0.5,
    this.metallic = 0.1,
    this.wireframe = false,
    this.opacity = 1.0,
  });

  Map<String, dynamic> toJson() {
    return {
      'color': color.toARGB32(),
      'roughness': roughness,
      'metallic': metallic,
      'wireframe': wireframe,
      'opacity': opacity,
    };
  }

  factory Material3D.fromJson(Map<String, dynamic> json) {
    return Material3D(
      color: Color(json['color'] as int? ?? 0xFF6366F1),
      roughness: (json['roughness'] as num?)?.toDouble() ?? 0.5,
      metallic: (json['metallic'] as num?)?.toDouble() ?? 0.1,
      wireframe: json['wireframe'] as bool? ?? false,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Material3D clone() {
    return Material3D(
      color: color,
      roughness: roughness,
      metallic: metallic,
      wireframe: wireframe,
      opacity: opacity,
    );
  }
}
