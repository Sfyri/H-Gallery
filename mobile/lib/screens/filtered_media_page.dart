import 'package:flutter/material.dart';

import '../models/gallery_browse_models.dart';
import '../models/gallery_profile.dart';
import '../services/gallery_browse_service.dart';
import '../services/media_bridge.dart';
import '../widgets/media_query_grid.dart';

class FilteredMediaPage extends StatelessWidget {
  const FilteredMediaPage({
    required this.gallery,
    required this.title,
    required this.query,
    this.mediaService = const PlatformMediaService(),
    this.browseService = const PlatformGalleryBrowseService(),
    super.key,
  });

  final GalleryProfile gallery;
  final String title;
  final MediaQuerySpec query;
  final MediaService mediaService;
  final GalleryBrowseService browseService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: MediaQueryGrid(
        gallery: gallery,
        query: query,
        mediaService: mediaService,
        browseService: browseService,
        emptyTitle: 'Cartella vuota',
        emptyMessage: 'Non ci sono media indicizzati in questa raccolta.',
      ),
    );
  }
}
