import 'package:flutter/material.dart';

enum HGalleryTagType { general, artist, system }

class HGalleryTagChip extends StatelessWidget {
  const HGalleryTagChip({
    required this.label,
    required this.type,
    this.onPressed,
    this.showAddIcon = false,
    super.key,
  });

  final String label;
  final HGalleryTagType type;
  final VoidCallback? onPressed;
  final bool showAddIcon;

  Color get _borderColor => switch (type) {
        HGalleryTagType.general => const Color(0xFFA9682C),
        HGalleryTagType.artist => const Color(0xFF8C5AB3),
        HGalleryTagType.system => const Color(0xFF43845C),
      };

  Color get _textColor => switch (type) {
        HGalleryTagType.general => const Color(0xFFFFD8AD),
        HGalleryTagType.artist => const Color(0xFFEAD2FF),
        HGalleryTagType.system => const Color(0xFFC9F4D6),
      };

  Color get _backgroundColor => switch (type) {
        HGalleryTagType.general => const Color(0xFF56351D),
        HGalleryTagType.artist => const Color(0xFF43285A),
        HGalleryTagType.system => const Color(0xFF234B34),
      };

  @override
  Widget build(BuildContext context) {
    final labelWidget = Text(
      label,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: _textColor),
    );
    if (onPressed != null) {
      return ActionChip(
        avatar: showAddIcon
            ? Icon(Icons.add_rounded, size: 17, color: _textColor)
            : null,
        label: labelWidget,
        onPressed: onPressed,
        backgroundColor: _backgroundColor,
        side: BorderSide(color: _borderColor),
        visualDensity: VisualDensity.compact,
      );
    }
    return Chip(
      label: labelWidget,
      backgroundColor: _backgroundColor,
      side: BorderSide(color: _borderColor),
      visualDensity: VisualDensity.compact,
    );
  }
}
