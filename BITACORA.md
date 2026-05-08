# Bitácora de Problemas y Soluciones - FirmaFacil

Este documento registra los problemas técnicos encontrados durante el desarrollo de FirmaFacil (ex-EasyScan) y las soluciones aplicadas para mantener la trazabilidad del proyecto.

---

## 2026-05-08

### 1. Diálogo de Bienvenida Bloqueado
- **Problema**: El diálogo de bienvenida para nuevos usuarios no se cerraba al pulsar "Comenzar", impidiendo el acceso al dashboard.
- **Causa**: El diálogo se disparaba en cada reconstrucción (rebuild) de `HomeScreen` porque la condición dependía de una petición asíncrona a Firebase que no se completaba antes del siguiente frame. Esto causaba que los diálogos se apilaran.
- **Solución**: Se implementó una bandera `hasSeenWelcome` en `SettingsService` persistida con `SharedPreferences`. Se marca como `true` **antes** de mostrar el diálogo para evitar duplicados.

### 2. Botón "Comenzar" Estrecho
- **Problema**: La palabra "Comenzar" se veía cortada en el botón de bienvenida.
- **Solución**: Se aplicó `minimumSize: const Size(180, 50)` y un diseño con bordes redondeados.

### 3. Documentos Firmados no Visibles
- **Problema**: Los PDFs firmados no aparecían en la galería de "Mis Documentos".
- **Causa**: Nomenclatura inconsistente (faltaba prefijo `FirmaFacil_`) y falta de refresco automático del estado.
- **Solución**: Se unificó la nomenclatura en `PdfSignatureScreen` y se forzó `_loadGallery()` tras cerrar el editor.

### 4. Desplazamiento de Firma (Shift Upward)
- **Problema**: La firma se movía ligeramente hacia arriba en el PDF guardado.
- **Causa**: Desajuste entre coordenadas lógicas y píxeles de canvas en alta resolución.
- **Solución**: Se añadió una compensación de `1.5 * scaleY` en el mapeo de coordenadas del canvas.

---

## Problemas Históricos Relevantes (Resueltos)

### 5. Bug del "Lienzo Gigante" (pdfrx + InteractiveViewer)
- **Problema**: Al abrir un PDF para firmar, el documento aparecía como una miniatura perdida en un lienzo blanco inmenso, dificultando la interacción.
- **Causa**: El `boundaryMargin` de `InteractiveViewer` estaba configurado de forma que permitía un desplazamiento infinito, y el escalado inicial de `pdfrx` no coincidía con las restricciones del contenedor.
- **Solución**: Se ajustó el `boundaryMargin` a valores finitos (`EdgeInsets.all(20)`), se forzó un `minScale: 1.0` (blindaje al ancho de pantalla) y se centró el `Container` del documento mediante un `Center` dentro del viewer.

### 6. Miniaturización y Pixelación en Exportación
- **Problema**: Los PDFs exportados tenían márgenes blancos gigantes y el contenido se veía pixelado.
- **Causa**: Uso de escalado basado en DPI del dispositivo en lugar de puntos lógicos del PDF (72 DPI estándar).
- **Solución**: Se eliminó la dependencia de la densidad de pantalla del dispositivo y se forzó un renderizado a **350 DPI nativos** mapeados 1:1 a los puntos del documento (A4/Carta/Oficio).

### 11. Selector de Calidad Dinámico (DPI)
- **Problema**: El procesamiento a 350 DPI era demasiado lento para algunos usuarios o documentos largos.
- **Solución**: Se implementó un selector de tres niveles (Baja, Media, Alta) que permite al usuario decidir la relación entre velocidad y calidad. Se mejoró el feedback visual con un diálogo detallado.

---

## Ideas y Próximos Pasos (Backlog)

### 1. Monetización con Anuncios Nativos
- **Concepto**: Reemplazar el diálogo de carga simple por una pantalla completa de "Procesando" que integre **Native Ads**.
- **Objetivo**: Mejorar el ingreso (eCPM) y la experiencia de usuario (UX) mediante anuncios que se integren visualmente con la estética premium de la app (mismo radio de borde, tipografía Outfit y colores oscuros).
- **Momento**: Se activará durante el proceso de aplanado de PDF para monetizar el tiempo de espera del usuario.

### 2. Sistema de Referidos Automatizado
- **Concepto**: Generar recompensas de 5 créditos por cada nuevo usuario que instale la app mediante un link de invitación.
- **Estado**: Interfaz y botón de compartir implementados; pendiente integración de backend para validación de instalaciones.

---

### 7. Bloqueo de UI (Application Hang)
- **Problema**: La aplicación se congelaba al procesar firmas complejas o documentos largos.
- **Causa**: Procesamiento intensivo de imágenes en el hilo principal de la UI.
- **Solución**: Se optimizó el uso de `Isolates` y se mejoró la gestión de memoria al liberar `ui.Image` y buffers de bytes inmediatamente después de su uso.

### 8. Errores de Posicionamiento por Zoom
- **Problema**: Al colocar una firma con zoom aplicado, esta aparecía en lugares incorrectos.
- **Causa**: El delta del gesto no se dividía por el factor de escala actual del `TransformationController`.

### 9. Desplazamiento de Firma en Exportación
- **Problema**: La firma aparecía movida verticalmente en el PDF final (`realidad.jpg` vs `usuario.jpg`).
- **Causa**: Se estaba forzando el formato **A4** en la exportación, lo que estiraba o centraba el documento original si este tenía otro tamaño (Carta/Oficio), rompiendo el mapa de coordenadas.
- **Solución**: Se eliminó el forzado a A4. Ahora el motor de exportación detecta y utiliza el **tamaño original exacto** de cada página, garantizando una sincronización 1:1 de las coordenadas.

### 10. Migración de Install Referrer
- **Cambio**: Se reemplazó el paquete descontinuado `android_play_install_referrer` por el nuevo estándar `play_install_referrer` (^0.5.0).
- **Impacto**: Mejora la estabilidad en la captura de referidos desde Google Play y asegura compatibilidad futura con Android 14+.

### 11. Refinamiento de UI y UX (Dashboard)
- **Problema**: El encabezado se veía desequilibrado y los botones de captura no coincidían con el estilo de los documentos.
- **Solución**: 
    - Se redistribuyeron los pesos en el encabezado (`flex`) y se restituyeron los iconos de acción.
    - Se rediseñaron los botones de **"Capturar archivo"** y **"Capturar firma"** como tarjetas estandarizadas que mantienen la simetría visual de la galería.
### 12. Corrección Final de Coordenadas de Firma
- **Problema**: Persistía un desplazamiento vertical (firma aparecía más arriba de lo seleccionado).
- **Solución**: Refactorización del mapeo de coordenadas en `_saveFinalPdf` usando el tamaño físico absoluto del PDF. Se eliminaron constantes de ajuste manual y se sincronizó el canvas de Flutter con los puntos nativos del documento.

### 13. Refinamientos Estéticos Finales
- **Cabecera**: 
    - Aumento de tamaño de iconos (20px) y textos en bloques de Créditos y Publicidad.
    - El botón de ayuda (`?`) ahora es rectangular para mantener la simetría de la fila.
    - Se invirtió el orden de los botones de **Publicidad** y **Compartir** para mejorar el flujo de usuario.
- **Galería**:
    - Renombrado de "Capturar archivo" a **"Capturar documento"**.
    - Aumento de tamaño y peso de fuente (`bold`, 12px) en los botones de acción de la cuadrícula.
---
