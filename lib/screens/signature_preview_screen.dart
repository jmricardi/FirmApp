import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../services/signature_service.dart';
import '../services/credit_service.dart';
import '../services/localization_service.dart';
import '../services/settings_service.dart';

class SignaturePreviewScreen extends StatefulWidget {
  final String imagePath;
  const SignaturePreviewScreen({super.key, required this.imagePath});

  @override
  State<SignaturePreviewScreen> createState() => _SignaturePreviewScreenState();
}

class _SignaturePreviewScreenState extends State<SignaturePreviewScreen> {
  final Map<int, String> _versions = {}; // 0: Base, 1: Local, 2: Worker, 3: Premium
  int _viewingVersion = 0;
  final Set<int> _selectedToSave = {0}; // Por defecto base seleccionada
  bool _isProcessing = false;
  bool _hasInternet = false;

  @override
  void initState() {
    super.initState();
    _versions[0] = widget.imagePath;
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      if (mounted) {
        setState(() {
          _hasInternet = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasInternet = false;
        });
      }
    }
  }

  Future<void> _refineLocally() async {
    setState(() => _isProcessing = true);
    final service = SignatureService();
    final newPath = await service.improveSignatureLocally(_versions[0]!);
    if (newPath != null) {
      setState(() {
        _versions[1] = newPath;
        _viewingVersion = 1;
        _selectedToSave.add(1);
      });
    }
    setState(() => _isProcessing = false);
  }

  Future<void> _refineWithAI() async {
    final credits = Provider.of<CreditService>(context, listen: false);
    setState(() => _isProcessing = true);
    try {
      final bytes = await File(_versions[_viewingVersion] ?? _versions[0]!).readAsBytes();
      final url = 'https://easyscan-credits-worker.jmricardi-3d1.workers.dev?action=refine_signature&uid=${credits.uid}&amount=0';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Authorization': 'SuperEasyScan2024', 'Content-Type': 'image/png'},
        body: bytes,
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final scansDir = Directory('${directory.path}/scans');
        final newPath = '${scansDir.path}/TEMP_FRM_IA_${DateTime.now().millisecondsSinceEpoch}.png';
        await File(newPath).writeAsBytes(response.bodyBytes);
        await credits.fetchCredits();
        setState(() {
          _versions[2] = newPath;
          _viewingVersion = 2;
          _selectedToSave.add(2);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final lang = settings.localeCode;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(LocalizationService.translate('signature', lang)), backgroundColor: Colors.transparent),
      body: Column(
        children: [
          // Selector de versiones
          Container(
            height: 70,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _versionTab(0, 'BASE'),
                if (_versions.containsKey(1)) _versionTab(1, 'NITIDEZ'),
                if (_versions.containsKey(2)) _versionTab(2, 'IA WORKER'),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: _isProcessing 
                ? const CircularProgressIndicator(color: Colors.deepPurpleAccent)
                : Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.1), blurRadius: 20)],
                    ),
                    child: Image.file(File(_versions[_viewingVersion]!)),
                  ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              decoration: const BoxDecoration(color: Color(0xFF1A1A1A), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_versions.containsKey(1)) _refineBtn('Mejorar Nitidez', 'Filtro local para un trazo con apariencia tinta fresca', Icons.auto_awesome, _refineLocally, Colors.greenAccent),
                  if (!_versions.containsKey(2)) _refineBtn(
                    _hasInternet ? 'Proceso en la nube' : 'Proceso en la nube (No disponible)', 
                    'Reconstrucción inteligente para un acabado digital perfecto. (Requiere Internet)', 
                    Icons.cloud, 
                    _hasInternet ? _refineWithAI : null, 
                    _hasInternet ? Colors.blueAccent : Colors.grey.shade700
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _selectedToSave.isEmpty ? null : () {
                        final paths = _selectedToSave.map((idx) => _versions[idx]!).toList();
                        Navigator.pop(context, paths);
                      }, 
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                      child: FittedBox(
                        child: Text(
                          'GUARDAR SELECCIONADAS (${_selectedToSave.length})', 
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)
                        )
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _versionTab(int index, String label) {
    bool isViewing = _viewingVersion == index;
    bool isSelected = _selectedToSave.contains(index);
    return GestureDetector(
      onTap: () => setState(() => _viewingVersion = index),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isViewing ? Colors.deepPurpleAccent.withOpacity(0.2) : Colors.white10,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isViewing ? Colors.deepPurpleAccent : Colors.white24, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: isSelected, 
              onChanged: (val) => setState(() => val! ? _selectedToSave.add(index) : _selectedToSave.remove(index)),
              activeColor: Colors.deepPurpleAccent,
              visualDensity: VisualDensity.compact,
              side: const BorderSide(color: Colors.white54),
            ),
            Text(label, style: TextStyle(color: isViewing ? Colors.white : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _refineBtn(String title, String subtitle, IconData icon, VoidCallback? onTap, Color color) {
    final isEnabled = onTap != null;
    return Card(
      color: isEnabled ? Colors.grey.shade900 : Colors.grey.shade900.withOpacity(0.5),
      child: ListTile(
        leading: Icon(icon, color: isEnabled ? color : Colors.grey),
        title: Text(title, style: TextStyle(color: isEnabled ? Colors.white : Colors.grey, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: TextStyle(color: isEnabled ? Colors.white70 : Colors.grey.shade600, fontSize: 11)),
        onTap: onTap,
        enabled: isEnabled,
      ),
    );
  }
}
