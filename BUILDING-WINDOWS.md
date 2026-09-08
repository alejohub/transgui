# Build Windows x64

## Plataforma oficial

La única plataforma soportada es Windows 11 x86-64. Linux, macOS, ARM y Windows de 32 bits no se compilan ni se prueban como plataformas oficiales.

## Toolchain fijado

- Lazarus 4.8 para Windows x64
- Free Pascal Compiler 3.2.2 para `x86_64-win64`

Instala el paquete oficial firmado `lazarus-4.8-fpc-3.2.2-win64.exe`. No instales el complemento de Win32: este proyecto solo genera ejecutables Win64.

El instalador oficial y sus sumas de verificación están publicados en la [página de Lazarus 4.8](https://sourceforge.net/projects/lazarus/files/Lazarus%20Windows%2064%20bits/Lazarus%204.8/).

## Dependencias

1. Git con el submódulo Synapse inicializado:

   ```powershell
   git submodule update --init --recursive
   ```

2. Lazarus instalado, por ejemplo en `C:\lazarus`.
3. No hace falta instalar OpenSSL manualmente. El script obtiene y verifica el runtime fijado OpenSSL 3.5.8 Win64, y lo incluye junto al ejecutable.

El build local no descarga compiladores. Solo descarga el instalador OpenSSL fijado si no se proporciona previamente con `-OpenSslInstaller`; su SHA-256 y firma Authenticode se verifican antes de usarlo.

La ventana **About** muestra el SHA corto del código compilado. El script no necesita `git.exe` en Windows: GitHub Actions suministra `BUILD_COMMIT`, y desde WSL se pasa el SHA calculado por Git. Si no se proporciona, muestra `local`.

## Compilar desde Windows

```powershell
.\build-windows.ps1 -LazarusDir C:\lazarus
```

El resultado se crea en `dist\windows-x64\`:

- `transgui.exe`
- `lang\transgui.*`
- `libcrypto-3-x64.dll` y `libssl-3-x64.dll` (OpenSSL 3.5.8)
- `SHA256SUMS.txt`

El script reconstruye las pruebas, ejecuta `transguitest.exe -a`, recompila en modo `Release`, verifica que el ejecutable y las DLL sean PE x86-64, comprueba que Windows puede cargar las DLL y que exportan los símbolos usados por Synapse, y falla ante cualquier error. Para omitir únicamente las pruebas durante diagnóstico, usa `-SkipTests`.

El runtime se descarga desde [Shining Light Productions](https://slproweb.com/products/Win32OpenSSL.html), proveedor listado por el proyecto OpenSSL como distribución binaria de Windows. El instalador se ejecuta de forma silenciosa con directorio de destino `build\\openssl\\win64\\3.5.8`. Para un build sin descarga, descarga previamente el mismo instalador y pasa su ruta con `-OpenSslInstaller`; el hash debe coincidir con el fijado en el script.

## Ejecutarlo desde WSL2

Compila de forma nativa en Windows. Para evitar problemas con rutas UNC de `\\wsl$`, el checkout que se construye debe estar en el sistema de archivos de Windows, por ejemplo `C:\src\transgui`, accesible desde WSL como `/mnt/c/src/transgui`.

Desde ese checkout en WSL:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD")\\build-windows.ps1" -LazarusDir 'C:\lazarus' -BuildCommit "$(git rev-parse --short=12 HEAD)"
```

La interoperabilidad WSL debe estar operativa. Si `powershell.exe` falla antes de iniciar PowerShell, reinicia WSL desde Windows con `wsl --shutdown` y abre una nueva sesión.

## Nota sobre FPC

FPC 3.2.2 es la versión estable incluida en Lazarus 4.8. El historial de este proyecto documenta errores de análisis JSON de FPC 3.2.2 corregidos posteriormente en desarrollo. Esta base fija el compilador estable y no descarga compiladores de desarrollo de forma implícita; antes de una release debe verificarse el comportamiento JSON contra un daemon real.
