# Auditoría técnica

Fecha: 2026-09-08

## Resumen

El proyecto es recuperable, pero la base no estaba lista para publicar nuevas versiones con garantías. La auditoría fue estática: el árbol Git estaba limpio, pero esta máquina no tenía FPC/Lazarus y el submódulo de Synapse no estaba inicializado, por lo que no se pudo compilar ni ejecutar la aplicación.

## Estado del repositorio

- Rama `develop`, sincronizada con `origin`; no hay remoto `upstream` ni etiquetas locales.
- Aplicación Lazarus/Free Pascal multiplataforma, aproximadamente 19.400 líneas Pascal.
- 39 unidades Pascal, 17 formularios y un submódulo técnico (`synapse/source/lib`).
- Licencia GPLv2+ con excepción de enlace para OpenSSL; no se encontraron secretos evidentes en el árbol.
- La cobertura de pruebas se limita a una prueba de `TrackerUri.Filter` con cinco aserciones.

## Hallazgos prioritarios

1. **Alta — TLS:** la aplicación no activa verificación de certificados del servidor. Las credenciales RPC pueden quedar expuestas ante un atacante de red.
2. **Alta — temporales:** usa nombres fijos en el directorio temporal para torrents y GeoIP, con riesgo de colisiones y enlaces simbólicos.
3. **Alta — CI:** los jobs de macOS usan `macos-13`, y el pipeline depende de acciones, imágenes y descargas externas antiguas o no fijadas criptográficamente.
4. **Alta — criptografía distribuida:** Windows descarga OpenSSL 3.1.8, rama fuera de soporte.
5. **Alta — mantenimiento:** documentación, enlaces de releases y comprobador de actualizaciones apuntaban al repositorio archivado.
6. **Media-alta — compatibilidad:** el cliente usa exclusivamente el protocolo RPC antiguo; Transmission 4.1 lo mantiene solo por compatibilidad y lo marca como obsoleto.
7. **Media — calidad:** no hay pruebas de RPC, bencode, TLS, persistencia, descargas ni integración con Transmission.
8. **Media — diseño:** `main.pas` concentra interfaz, RPC, configuración, descargas, procesos y rutas, dificultando cambios aislados.

## Defectos concretos observados

- `TBEncodedDataList.Last` devuelve el primer elemento.
- La validación de contraseñas con `{}` muestra un error pero continúa guardando el valor.
- El parser bencode no limita profundidad ni número de elementos.
- El código de descargas comparte estado entre hilos sin sincronización explícita.
- La versión del proyecto (`5.18.9.f`) no coincide con la declarada en el RPM (`5.18.8.f`).

## Plan recomendado

1. Tomar propiedad del fork y sanear enlaces/documentación.
2. Recuperar un CI reproducible y verificable.
3. Corregir TLS, almacenamiento de credenciales y archivos temporales.
4. Añadir pruebas de integración y compatibilidad RPC.
5. Implementar JSON-RPC 2.0 con compatibilidad dual.
6. Refactorizar gradualmente los servicios que hoy viven en `main.pas`.
