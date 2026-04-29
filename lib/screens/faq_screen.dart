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
        padding: const EdgeInsets.all(16.0),
        children: const [
          _FAQItem(
            question: '¿Qué es EasyScan?',
            answer: 'Es una herramienta ligera que convierte la cámara de tu celular en un escáner profesional. Está diseñada para ser simple y rápida, sin procesos complejos que sobrecarguen o ralenticen tu dispositivo.',
          ),
          _FAQItem(
            question: '¿Cómo funcionan los créditos?',
            answer: 'Los créditos son la moneda de la aplicación. Se obtienen gratuitamente mirando breves anuncios publicitarios. \n\n'
                    '• 1 Escaneo = 1 Crédito.\n'
                    '• Reconocimiento de Texto (OCR) = +1 Crédito adicional.\n\n'
                    'De esta forma, puedes usar todas las funciones sin pagar dinero real.',
          ),
          _FAQItem(
            question: '¿Puedo usar la app sin internet?',
            answer: '¡Sí! El escaneo y el reconocimiento de texto se realizan mediante algoritmos optimizados que corren localmente en tu celular. No necesitas internet para procesar tus documentos.\n\n'
                    'Sin embargo, necesitarás conexión para sincronizar tus créditos o cargar nuevos anuncios.',
          ),
          _FAQItem(
            question: '¿Mis documentos son privados?',
            answer: 'Totalmente. EasyScan no envía tus imágenes a la nube para procesarlas. Todo el reconocimiento de imagen y texto se hace dentro de tu propio teléfono, garantizando que tu información nunca salga de tu dispositivo.',
          ),
          _FAQItem(
            question: '¿Dónde se guardan mis archivos?',
            answer: 'Todos tus documentos se guardan de forma organizada en la carpeta de Documentos de tu celular y en tu galería de fotos. La app mantiene un registro centralizado para que no tengas archivos duplicados ocupando espacio innecesario.',
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
      title: Text(
        question,
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurpleAccent),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(answer, style: const TextStyle(height: 1.5)),
        ),
      ],
    );
  }
}
