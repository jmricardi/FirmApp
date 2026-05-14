# FirmApp - Guía de Comandos Rápidos

Este archivo contiene los comandos más utilizados para el desarrollo, compilación y despliegue de FirmApp.

## 1. Compilación de APK (Android)

### Build Debug ARM64
Limpia el proyecto, descarga librerías y genera el APK para dispositivos modernos (64 bits).
```powershell
flutter clean; flutter pub get; flutter build apk --debug --target-platform android-arm64
```

### Build Release (Optimizado)
Genera APKs ligeros y optimizados divididos por arquitectura de procesador.
```powershell
flutter clean; flutter pub get; flutter build apk --release --split-per-abi
```

## 2. Mantenimiento de Flutter

### Limpiar y Actualizar
Elimina archivos temporales y descarga las dependencias del `pubspec.yaml`.
```powershell
flutter clean; flutter pub get
```

## 3. Análisis de Librerías

### Verificar dependencias desactualizadas
Muestra qué paquetes tienen versiones más recientes disponibles.
```powershell
flutter pub outdated
```

### Analizar peso de la APK
Genera un reporte detallado de qué archivos ocupan más espacio (usando ARM64 como referencia).
```powershell
flutter build apk --release --target-platform android-arm64 --analyze-size
```

---

## Cloudflare Worker (Backend)

### Desplegar Worker a Producción
Sube el código de `cloudflare_worker.js` a Cloudflare.
```powershell
npx wrangler deploy
```

### Probar Worker Localmente
Inicia un servidor local para pruebas de la API de créditos.
```powershell
npx wrangler dev
```

### Aplicar Migraciones D1 (Base de Datos)
Si has realizado cambios en el esquema de la base de datos `firmapp-db`.
```powershell
npx wrangler d1 migrations apply firmapp-db --remote
```
