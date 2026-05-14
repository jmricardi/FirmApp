import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/custom_app_bar.dart';

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
        appBar: const FirmAppAppBar(showActions: false),
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
      appBar: FirmAppAppBar(
        showActions: false,
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
            final isSignature = file.path.contains('FRM_');
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
