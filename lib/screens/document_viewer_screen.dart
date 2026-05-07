import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart';

class DocumentViewerScreen extends StatefulWidget {
  final List<File> files;
  final int initialIndex;

  const DocumentViewerScreen({
    super.key, 
    required this.files, 
    this.initialIndex = 0,
  });

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  bool _isPdf(String path) => path.toLowerCase().endsWith('.pdf');

  @override
  Widget build(BuildContext context) {
    if (widget.files.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(
          child: Text(
            "No hay documentos para visualizar",
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentIndex < widget.files.length 
                ? widget.files[_currentIndex].path.split(Platform.pathSeparator).last
                : "Cargando...",
              style: const TextStyle(color: Colors.white, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.files.length > 1)
              Text(
                '${_currentIndex + 1} de ${widget.files.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: () => Share.shareXFiles([XFile(widget.files[_currentIndex].path)]),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.files.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          final file = widget.files[index];
          if (_isPdf(file.path)) {
            return PdfViewer.file(
              file.path,
              key: ValueKey(file.path),
              params: const PdfViewerParams(
                backgroundColor: Colors.black,
              ),
            );
          } else {
            final isSignature = file.path.contains('Firma_');
            return PhotoView(
              imageProvider: FileImage(file),
              backgroundDecoration: BoxDecoration(color: isSignature ? Colors.white : Colors.black),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 2,
              heroAttributes: PhotoViewHeroAttributes(tag: file.path),
            );
          }
        },
      ),
    );
  }
}
