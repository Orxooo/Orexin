# Historial de cambios

[简体中文](CHANGELOG.md) · [繁體中文](CHANGELOG.zh-Hant.md) · [English](CHANGELOG.en.md) · [日本語](CHANGELOG.ja.md) · [Français](CHANGELOG.fr.md) · [Deutsch](CHANGELOG.de.md) · **Español**

[Volver al README](README.es.md)

Los paquetes de instalación y las instrucciones de actualización están en la [página de versiones](https://github.com/Orxooo/Orexin/releases).

## V1.0.5 HotFix 1 — 2026-10-28

- Corregidos los avisos que indicaban por error que el servicio auxiliar no estaba autorizado. Ahora se comprueba la conexión firmada real y los fallos de conexión se pueden recuperar al reintentar.
- El bloqueo por inactividad se pausa mientras se impide el reposo de la pantalla. Mantener el escritorio visible y evitar el salvapantallas tienen prioridad, sin cambiar las reglas guardadas.
- Aclarados los mensajes del modo de escritorio y de autorización. Añadida la etiqueta HotFix 1 y su ordenación como actualización estable.

## V1.0.5 — 2026-10-27

- Corregido el retorno del brillo a cero tras abrir la tapa, despertar la pantalla o desbloquear durante el trabajo en segundo plano. Se restaura el brillo anterior y las tareas continúan.
- Cerrar de nuevo la tapa o seleccionar explícitamente el brillo mínimo reactiva la atenuación. Se conservan los ajustes de pantalla, también cuando el servicio independiente gestiona las tareas.

## V1.0.4 — 2026-10-26

- Corregidos los interruptores de sesión anulados por la política de pantalla. La prevención del salvapantallas se puede desactivar por separado; al activarla se elige una política compatible.
- La autorización de accesibilidad muestra su estado y abre Ajustes del Sistema. El movimiento del puntero explica por qué está esperando o en pausa.
- Editor de reglas reorganizado con campos etiquetados, opciones avanzadas plegables, acciones Guardar y Cancelar fijas y menos bordes y zonas de desplazamiento anidados.

## V1.0.3 — 2026-10-25

- Se añade «Mensajes y avisos», que guarda los mensajes de actualización, fallos del servicio, vencimiento de solicitudes, advertencias de fin de sesión y protección térmica.
- Se admiten ventanas emergentes y notificaciones de macOS para los eventos importantes, sin repetir avisos ni mostrar alertas pendientes cuya causa ya se haya resuelto.
- Se buscan actualizaciones después del inicio y cada 6 horas. Solo se avisa una vez por versión; la descarga y la instalación son manuales.
- Se actualizan las instrucciones de uso y las capturas de pantalla en chino e inglés.

## V1.0.2 — 2026-10-22

- Se corrige el problema que impedía cerrar la ventana principal y el panel de acceso rápido, así como usar el menú «Cerrar» y `⌘W`. La barra de menús y las tareas en segundo plano siguen funcionando al cerrar las ventanas.

## V1.0.1 — 2026-10-18

- Se corrigen el parpadeo cada segundo del panel de la barra de menús durante el trabajo, los textos superpuestos y los saltos de diseño.

## V1.0.0 — 2026-10-18

Primera versión estable.

- Se añade un servicio de tareas independiente en segundo plano para que los comandos y los planes de ejecución continúen después de cerrar la interfaz.
- Se añaden planes de ejecución JSON con dependencias, ejecución secuencial y en paralelo, límites de concurrencia, ramas en caso de error y registros por elemento.
- Se pueden cancelar los comandos de un plan que aún no hayan empezado. Los comandos ya iniciados siguen ejecutándose, y el reinicio del servicio no vuelve a ejecutar las tareas.
- Se unifican los botones, selectores e interruptores; se corrige el diseño de tarjetas, filtros y registros; y se mejora el uso en ventanas estrechas y con el teclado.
- Se corrige el problema que impedía a la CLI incluida en el paquete de instalación iniciar el servicio en segundo plano.

## V0.3.0 Preview.1 — 2026-10-18

La página de publicación se llama V0.3.1 Preview; la etiqueta original es `v0.3.0-preview.1` y la versión de la aplicación es `0.3.0`.

- Se añaden reglas avanzadas con condiciones anidadas, prioridades, cumplimiento sostenido de condiciones, intervalos entre activaciones y simulaciones.
- Se añade el análisis de energía para consultar las aserciones de energía del sistema, los procesos de origen identificables y la cronología de eventos.
- Se añaden perfiles de trabajo e importación y exportación en JSON, con vista previa de diferencias y opciones de combinar o sustituir. Las reglas y los scripts importados deben activarse en el equipo local.
- La CLI admite perfiles de trabajo, simulaciones de reglas, consultas de energía e importación y exportación de configuraciones.
- Se corrigen la alineación y el diseño en ventanas estrechas de la página de gestión de tareas, además de los errores de compilación con Xcode 26.3.

## V0.2.0 Preview — 2026-10-14

- Se añade la gestión de tareas en paralelo, con códigos de salida, registros y estados de mantenimiento de actividad independientes para cada tarea.
- Se añade la CLI integrada `orexin`, que permite ejecutar comandos, registrar tareas externas, enviar señales de actividad y consultar estados.
- La finalización de una tarea no afecta a las demás. Cuando todas terminan correctamente y ninguna otra fuente mantiene activo el Mac, puede comenzar una cuenta atrás de 60 segundos antes del reposo.
- Se puede liberar el mantenimiento de actividad por tarea o para todas las tareas, sin terminar los comandos en ejecución.
- Se ajusta el diseño de la página de tareas y se completan los textos en los siete idiomas.

## V0.1.0 Preview — 2026-10-12

Primera versión preliminar pública.

- Modos de trabajo en segundo plano y en el escritorio, sesiones programadas o condicionales, control del brillo y apagado de pantalla.
- Activación automática, tareas de comandos, protección térmica y por batería baja, e historial local de ejecución.
- Panel en la barra de menús, tres temas, siete idiomas y sonidos de clic opcionales.
- Búsqueda de actualizaciones de versiones preliminares.
- Se corrigen las solicitudes repetidas de reposo al finalizar una sesión programada y el desplazamiento horizontal al cambiar entre algunas páginas.
- Publicación con la licencia GPL-3.0-only.
