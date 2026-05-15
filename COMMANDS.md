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

## 4. Gestión de Base de Datos (D1)

### Inicializar Esquema (Crear Tablas)
Crea las tablas `users` y `movements` si no existen.
```powershell
npx wrangler d1 execute firmapp-db --remote --command "CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, email TEXT, display_name TEXT, app_version TEXT, credits INTEGER DEFAULT 0, created_at TEXT, updated_at TEXT, version_hash TEXT, is_deleted INTEGER DEFAULT 0); CREATE TABLE IF NOT EXISTS movements (id INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT, amount INTEGER, description TEXT, idempotency_key TEXT UNIQUE, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP);"
```

### Borrado Total (Reset de Datos)
Elimina todos los registros de usuarios y transacciones (¡Cuidado!).
```powershell
npx wrangler d1 execute firmapp-db --remote --command "DELETE FROM users; DELETE FROM movements;"
```

### Auditoría y Estado
Verifica estructura de tablas, conteo de registros y últimos movimientos.

**Ver columnas:**
```powershell
npx wrangler d1 execute firmapp-db --remote --command "PRAGMA table_info(users); PRAGMA table_info(movements);"
```

**Ver conteo y últimos datos:**
```powershell
npx wrangler d1 execute firmapp-db --remote --command "SELECT 'Usuarios:' as tabla, COUNT(*) as total FROM users UNION SELECT 'Movimientos:', COUNT(*) FROM movements; SELECT * FROM movements ORDER BY timestamp DESC LIMIT 5;"
```

