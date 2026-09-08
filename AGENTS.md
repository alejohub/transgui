# Instrucciones de trabajo

- La única plataforma soportada es Windows 11 x64, con Lazarus 4.8 y FPC 3.2.2.
- La build oficial es `build-windows.ps1`; usa el toolchain nativo de Windows. WSL2 Debian 13 se usa para Codex y Git.
- Mantén los cambios pequeños y acotados. No corrijas problemas ajenos a la tarea solicitada.
- Después de cambiar código, ejecuta la build y las pruebas disponibles.
- RPC, TLS, concurrencia y persistencia son zonas de alto riesgo: no las modifiques sin una tarea explícita.
- No reintroduzcas trabajo para Linux, macOS, Win32 o ARM salvo petición explícita.
