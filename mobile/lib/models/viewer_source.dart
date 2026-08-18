class ViewerSource {
  const ViewerSource({
    required this.kind,
    required this.value,
  });

  final String kind;
  final String value;

  bool get isImageFile => kind == 'imageFile';
  bool get isVideoContentUri => kind == 'videoContentUri';

  factory ViewerSource.fromPlatform(Map<Object?, Object?> value) {
    return ViewerSource(
      kind: value['kind']?.toString() ?? '',
      value: value['value']?.toString() ?? '',
    );
  }
}
