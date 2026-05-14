import 'package:flutter/material.dart';
import '../widgets/custom_app_bar.dart';

class FAQScreen extends StatelessWidget {
  const FAQScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const FirmAppAppBar(showActions: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _FAQItem(
            question: '¿Qué es FirmApp?',
            answer: 'Es una herramienta profesional para digitalizar y firmar documentos PDF con la máxima fidelidad. Todo el proceso ocurre en tu dispositivo para garantizar rapidez y privacidad.',
          ),
          _FAQItem(
            question: '¿Cómo funcionan los créditos?',
            answer: 'Cada acción principal (Normalizar un PDF o Procesar un nuevo escaneo) consume 1 crédito. Puedes obtener créditos ilimitados viendo anuncios cortos desde el botón "+" en la parte superior.',
          ),
          _FAQItem(
            question: '¿Cómo firmo mis documentos?',
            answer: 'Selecciona un archivo PDF en la galería y pulsa "Firmar". Podrás elegir entre tus firmas guardadas (con prefijo FRM_) o crear una nueva. La firma se incrusta con calidad profesional sin perder resolución.',
          ),
          _FAQItem(
            question: '¿Mis firmas y documentos están seguros?',
            answer: 'Sí. FirmApp no sube tus documentos ni tus firmas a ningún servidor externo. El procesamiento de transparencia y la incrustación de firmas se realizan localmente en el hardware de tu celular.',
          ),
          _FAQItem(
            question: '¿Dónde encuentro mis archivos?',
            answer: 'Tus documentos se organizan por tamaño (A4, CARTA u OFICIO) y tus firmas bajo el nombre FRM_. Puedes compartir cualquier archivo directamente desde la galería de la app.',
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
