<p align="center">
  <img src="Assets/README/cover.png" width="100%" alt="Orexin: un eclipse azul noche y arcos de color ámbar. Mantente despierto. Descansa a tiempo.">
</p>

# Orexin

[简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [English](README.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · **Español**

[![Versión](https://img.shields.io/github/v/release/Orxooo/Orexin?color=56d7df&label=release)](https://github.com/Orxooo/Orexin/releases/latest)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-8ba6b8)
[![CI](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml/badge.svg?branch=main)](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml)
[![GPL-3.0-only](https://img.shields.io/badge/license-GPL--3.0--only-b7c8d6)](LICENSE)

Orexin es una utilidad para la barra de menús de macOS que permite controlar cuándo el Mac permanece activo y cuándo puede entrar en reposo.

Úsala para compilaciones, descargas, presentaciones o tareas de larga duración, en el escritorio o con la tapa cerrada. Las sesiones programadas, las reglas automáticas y las tareas de comandos permiten elegir cuándo dejar de mantener activo el Mac.

[Descargar la última versión](https://github.com/Orxooo/Orexin/releases/latest) · [Historial de cambios](CHANGELOG.es.md) · [Manual de uso](https://github.com/Orxooo/Orexin/wiki)

![Modos de trabajo de Orexin con el tema Tron, mostrados en chino simplificado](Assets/README/orexin-1.0.3-modes.png)

## Funciones

- **Modos de trabajo:** Trabajo en segundo plano impide el reposo con la tapa cerrada. Trabajo en el escritorio impide el reposo por inactividad, pero lo permite al cerrar la tapa.
- **Control de pantalla:** reduce el brillo al 0 %, conserva el brillo normal, sigue el tiempo de apagado configurado en el sistema o apaga la pantalla inmediatamente. Cada modo de trabajo recuerda su ajuste.
- **Sesiones de trabajo:** finaliza una sesión tras una duración, a una hora concreta, cuando se cierre una aplicación o un proceso, o cuando termine una descarga.
- **Comandos y planes de ejecución:** ejecuta comandos en paralelo y consulta sus códigos de salida y registros. Define en JSON las dependencias, los límites de concurrencia y las ramas que se seguirán en caso de error.
- **Reglas automáticas y perfiles:** inicia el trabajo según la alimentación, las pantallas, los dispositivos, las aplicaciones, la red o la hora. Admite condiciones anidadas, simulaciones e importación y exportación de configuraciones.
- **Protección y avisos:** activa opcionalmente la protección por batería baja y temperatura elevada, y consulta los avisos de fallos del servicio, las advertencias de fin de sesión y los recordatorios de actualización. Admite notificaciones del sistema y ventanas emergentes dentro de la aplicación. Las actualizaciones se instalan manualmente.

Incluye los temas Tron, Zima Blue y Blade Runner 2049, y está disponible en chino simplificado, chino tradicional, inglés, japonés, francés, alemán y español. Consulta la [lista de funciones](FEATURES.md) para obtener más información.

## Primeros pasos

Requiere un **Mac con Apple Silicon y macOS 15 o posterior**.

1. Descarga el paquete para Apple Silicon (cuyo nombre termina en `-arm64.zip`) desde la [página de versiones](https://github.com/Orxooo/Orexin/releases/latest), descomprímelo y mueve `Orexin.app` a Aplicaciones.
2. Abre la aplicación y elige un modo de trabajo y una condición de finalización. Para trabajar con la tapa cerrada, debes autorizar el servicio auxiliar en Preferencias.
3. Para recibir notificaciones del sistema, permítelas en **Mensajes y avisos** y envía un aviso de prueba.

El paquete está **firmado con Apple Development y aún no está notarizado con Developer ID**. Si macOS bloquea el primer inicio, comprueba el origen de la descarga y sigue las indicaciones de Privacidad y seguridad. No es necesario desactivar SIP ni desactivar Gatekeeper en todo el sistema.

Para verificar la descarga, coloca el archivo ZIP y el archivo `SHA256SUMS.txt` de la versión en el mismo directorio:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

### Actualización

Espera a que terminen los comandos y los planes de ejecución, finaliza todas las solicitudes de mantener activo el Mac y detén el servicio de tareas en segundo plano:

```sh
/Applications/Orexin.app/Contents/Helpers/orexin service-stop
```

Después, sal de Orexin, sustituye la aplicación y vuelve a abrirla. Omite el paso `service-stop` si tu versión anterior no incluye ese comando. Se conservan las preferencias, el historial y los registros; las tareas anteriores no se vuelven a ejecutar.

### Consideraciones de uso

- «Mantener desbloqueado al trabajar» es una opción que requiere una autorización independiente. Desactiva la solicitud de contraseña al salir del reposo durante la sesión y restablece la protección inmediata con contraseña al terminar el trabajo. Orexin no guarda contraseñas ni desbloquea un Mac que ya esté bloqueado.
- Un brillo del 0 % no equivale al reposo de la pantalla. Apagarla puede afectar a las capturas de pantalla o a la automatización de la interfaz que dependan de ella.
- Volver a Reposo normal solo libera las solicitudes de Orexin para mantener activo el Mac. Otras aplicaciones pueden seguir impidiendo el reposo.
- La protección térmica utiliza los niveles de presión térmica de macOS, no lecturas en grados Celsius. Cuando baja la temperatura, el trabajo detenido no se reinicia automáticamente.

## Gestión de tareas y CLI

Los comandos y los planes en segundo plano pueden seguir ejecutándose después de cerrar la interfaz. Las sesiones manuales y las reglas automáticas necesitan que el proceso de la interfaz siga en ejecución. Al reiniciar el servicio, las tareas sin terminar se marcan como desconectadas y no se vuelven a ejecutar automáticamente.

La CLI está incluida en el paquete de la aplicación y no necesita una instalación adicional:

```sh
orexin=/Applications/Orexin.app/Contents/Helpers/orexin
"$orexin" service-start
"$orexin" run --title Build -- make
"$orexin" list --json
```

De forma predeterminada, al terminar un comando se libera la solicitud de esa tarea para mantener activo el Mac. Añade `--after sleep` para iniciar una cuenta atrás de 60 segundos antes del reposo si el comando termina correctamente. Todas las solicitudes que se solapen deben finalizar correctamente, y ninguna otra sesión o regla debe seguir necesitando mantener activo el Mac. Liberar una solicitud no termina su comando.

La opción «Mantener desbloqueado al trabajar» debe autorizarse primero en la interfaz; la CLI no muestra diálogos de contraseña. Consulta la [guía de la CLI](docs/CLI.md) y la [guía de planes de ejecución](docs/EXECUTION-PLANS.md) para conocer las opciones, la integración de tareas externas y el formato de los planes.

## Compilar desde el código fuente

Requiere **Xcode 26+ y Swift 6**.

```sh
git clone https://github.com/Orxooo/Orexin.git
cd Orexin
swift test --arch arm64 --scratch-path /tmp/orexin-test-build
./scripts/build-app.sh
```

La aplicación se genera en `/tmp/orexin-dist/Orexin.app` y utiliza una firma ad hoc de forma predeterminada. El funcionamiento con la tapa cerrada exige que la aplicación y el servicio auxiliar estén firmados con el mismo certificado de desarrollador de Apple:

```sh
OREXIN_SIGN_IDENTITY='Nombre del certificado o SHA-1' ./scripts/build-app.sh
```

Usa `OREXIN_BUILD_DIR` y `OREXIN_OUTPUT_DIR` para definir los directorios de compilación y de salida. La CI está configurada con Xcode 26.3 en macOS 15 / 26; consulta los resultados en [Actions](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml).

## Documentación y comentarios

- [Perfiles de trabajo](docs/WORK-CONFIGURATION.md) · [Diccionario de AppleScript](Resources/Orexin.sdef) · [Seguridad](SECURITY.md)
- [Informar de un problema](https://github.com/Orxooo/Orexin/issues/new/choose) · [Debates](https://github.com/Orxooo/Orexin/discussions) · [Informes privados de vulnerabilidades](https://github.com/Orxooo/Orexin/security/advisories/new)
- [Guía de contribución](CONTRIBUTING.md) · [Código de conducta](CODE_OF_CONDUCT.md)

El historial y los registros locales se guardan en `~/Library/Application Support/Orexin/`. Los datos antiguos de WakeMac no se migran ni se eliminan automáticamente. Revisa los registros para detectar información privada antes de compartirlos.

## Licencia

[GPL-3.0-only](LICENSE) · © 2026 Orxooo. Las licencias de recursos de terceros se detallan en [NOTICE](NOTICE).
