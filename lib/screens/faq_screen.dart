import 'package:flutter/material.dart';

class FAQScreen extends StatelessWidget {
  const FAQScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preguntas Frecuentes'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _FAQItem(
            question: '¿Qué es FirmaFacil?',
            answer: 'Es una aplicación ligera que convierte la cámara de tu celular en un escáner potente. Está optimizada para ser rápida y no sobrecargar la memoria de tu dispositivo.',
          ),
          _FAQItem(
            question: '¿Cómo funcionan los créditos?',
            answer: 'El uso de la herramienta se basa en créditos que puedes ganar mirando publicidad gratuita:\n'
                '• Escaneo inicial: 1 crédito\n'
                '• Guardar como JPG: 1 crédito\n'
                '• Guardar como PDF: 1 crédito',
          ),
          _FAQItem(
            question: '¿Puedo usar la app sin internet?',
            answer: 'Sí, puedes escanear y usar tus funciones siempre y cuando tengas créditos cargados previamente. Sin embargo, no podrás cargar nuevos créditos (ver publicidad) hasta que recuperes la conexión a internet.',
          ),
          _FAQItem(
            question: '¿Mis documentos están seguros?',
            answer: 'Totalmente. FirmaFacil utiliza algoritmos optimizados que corren localmente en tu celular. Tus documentos no se suben a la nube para el procesamiento, garantizando tu privacidad.',
          ),
          _FAQItem(
            question: '¿Dónde se guardan mis archivos?',
            answer: 'Todos los archivos se gestionan de forma centralizada en la carpeta interna de la app para evitar duplicados. Puedes exportarlos a tu galería pública o compartirlos en cualquier momento.',
          ),
        ],
      ),
    );
  }
}

class _FAQItem extends StatelessWidget {
  final String question;
  final String answer;

  const _FAQItem({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(question, style: const TextStyle(fontWeight: FontWeight.bold)),
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(answer),
        ),
      ],
    );
  }
}
