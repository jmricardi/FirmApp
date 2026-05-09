# Bitácora de Problemas y Soluciones - FirmApp (ex-FirmaFacil / EasyScan)

Este documento registra los problemas técnicos encontrados durante el desarrollo de FirmApp y las soluciones aplicadas para mantener la trazabilidad del proyecto.

---

## 2026-05-09 — v1.4: Resolución Definitiva del Desplazamiento de Firma

### Problema
La firma digital se incrustaba **desplazada verticalmente hacia arriba** en el PDF exportado. El error era **proporcional a la posición Y** (mayor desplazamiento cuanto más abajo se colocaba la firma). El eje X funcionaba correctamente.

- **Ratio de error medido**: ~1.15x constante (firma en Y=650 → telemetría capturaba Y=562)
- **Patrón**: Lineal, NO aditivo. En Y=0 el error era 0, en Y=650 el error era ~87pt.

### Causa Raíz
El sistema tenía **3 fuentes de verdad geométrica distintas e inconsistentes** para mapear coordenadas:

1. `displayScale = sheetWidth / pdfWidth` — usado para posicionar en X
2. `sheetHeight / pdfHeight` — usado para posicionar en Y 
3. `box.size.height` (RenderBox real) — usado para capturar coordenadas del toque

Cuando la captura usaba `box.size` pero el render usaba `displayScale` o `sheetHeight`, cualquier diferencia de redondeo o layout entre estas tres fuentes producía un escalado vertical incorrecto.

Adicionalmente, el `InteractiveViewer` sin `constrained: false` podía alterar el tamaño del layout interno sin que `box.size` coincidiera con lo visible.

### Iteraciones de Debug (5 intentos)

| # | Enfoque | Resultado |
|---|---|---|
| 1 | Ajuste de rasterización en exportación | Fallido — el error era de captura, no de dibujo |
| 2 | Exportación vectorial (`pw.Stack` + `pw.Positioned`) | Confirmó que el PDF exportaba correctamente lo capturado, pero lo capturado estaba mal |
| 3 | Eliminación del zoom inicial 1.15x | Fallido — el ratio ~1.15 persistió (no era el zoom) |
| 4 | `RenderBox.globalToLocal()` para posiciones absolutas | Mejoró estabilidad pero mantuvo el error porque seguía dividiendo por `displayScale` único |
| 5 | **Fuente única de verdad geométrica** | ✅ RESUELTO |

### Solución Final (Iteración 5)

**Archivo**: `lib/screens/pdf_signature_screen.dart`

1. **Eliminación de `displayScale`** — ya no existe una sola escala para ambos ejes
2. **Escalas independientes calculadas una sola vez**:
   ```dart
   final double scaleX = sheetWidth / _pdfPageSize!.width;
   final double scaleY = sheetHeight / _pdfPageSize!.height;
   ```
3. **Misma escala usada en TODOS los pipelines**:
   - Posicionamiento visual de firma activa: `left: pos.dx * scaleX, top: pos.dy * scaleY`
   - Captura de arrastre: `pdfX = sigCorner.dx / scaleX`, `pdfY = sigCorner.dy / scaleY`
   - Renderizado de stamps confirmados: `_buildStamp(stamp, scaleX, scaleY)`
   - Tamaño del widget de firma: `width * scaleX, height * scaleY`
4. **`constrained: false`** agregado al `InteractiveViewer`
5. **Clamp de coordenadas**: `pdfY.clamp(0, pdfHeight - sigHeight)` para prevenir valores fuera de rango
6. **`globalToLocal()`** sobre el Container con `GlobalKey` para captura de toque precisa

### Cómo Reproducir el Bug (si reaparece)
1. Cargar un PDF con grilla de coordenadas (marcas cada 50pt)
2. Arrastrar la firma a una posición conocida (ej. Y=650 en la grilla)
3. Verificar la telemetría (panel verde): si `PDF Y` ≠ 650, hay desacoplamiento de escalas
4. Comparar `scaleX` vs `scaleY` en los logs — si difieren, ese es el bug

### Otros cambios en v1.4
- **Renombrado**: App renombrada de "FirmaFacil" a "FirmApp" en AndroidManifest, iOS Info.plist, web manifest
- **Eliminación de `play_install_referrer`**: Removido de dependencias (causaba crash al inicio)


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
