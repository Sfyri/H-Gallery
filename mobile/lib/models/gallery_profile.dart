class GalleryProfile {
  const GalleryProfile({
    required this.galleryUuid,
    required this.name,
    required this.treeUri,
    required this.directoryName,
    required this.locationLabel,
    required this.accessible,
    required this.layoutReady,
  });

  final String galleryUuid;
  final String name;
  final String treeUri;
  final String directoryName;
  final String locationLabel;
  final bool accessible;
  final bool layoutReady;

  factory GalleryProfile.fromPlatform(Map<Object?, Object?> value) {
    String readString(String key) => value[key]?.toString() ?? '';

    return GalleryProfile(
      galleryUuid: readString('galleryUuid'),
      name: readString('name'),
      treeUri: readString('treeUri'),
      directoryName: readString('directoryName'),
      locationLabel: readString('locationLabel'),
      accessible: value['accessible'] == true,
      layoutReady: value['layoutReady'] == true,
    );
  }
}
