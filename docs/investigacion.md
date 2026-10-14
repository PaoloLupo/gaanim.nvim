# Investigación: un plugin de Neovim para hacer videos y diapositivas con Gaanim

Octubre de 2026 · Neovim 0.12, LazyVim, Windows 11, Gaanim 0.12

## Conclusión

Casi todo lo que hace bueno a un plugin para Gaanim ya se puede construir con
la CLI y los archivos del proyecto, porque Gaanim ya hace lo difícil: recarga
la vista previa al guardar, valida con `gaanim check`, abre líneas de código
en el editor que diga `GAANIM_EDITOR` y lee el guion de la charla desde
Markdown. El plugin aporta lo que el editor sabe y la app no: **dónde está el
cursor**. Con eso puede previsualizar o presentar desde la diapositiva actual,
seguir el guion de esa diapositiva, estimar cuánto se tarda en decirla y llevar
cada error a su línea.

Lo que falta para que editor y vista previa funcionen como una sola
herramienta está del lado de Gaanim: un canal para mover la vista previa desde
el editor, un índice de la línea de tiempo con sus líneas de código y salida en
JSON. La sección [Lo que Gaanim podría exponer](#lo-que-gaanim-podría-exponer)
lo detalla.

## Lo que Gaanim ya ofrece

| Pieza | Cómo la usa el plugin |
|---|---|
| `gaanim <proyecto>` recarga al guardar (vigila la raíz, 200 ms) e imprime `▸ reload`, `✓ ready …` o el traceback y `✗ python Script failed` | El plugin lee esa salida en vivo: estado en la statusline y el error de Python como diagnóstico en su línea, sin volver a ejecutar nada |
| `--from <segmento>` y `--sections a,b` | `:Gaanim preview here` / `only` con la diapositiva bajo el cursor |
| `--present --duration 20m --monitor N` | `:Gaanim present here 20m monitor=1` |
| `gaanim check` (0,8 s en una charla corta; salida 0/1/2) | Al guardar, en segundo plano: quickfix y diagnósticos situados en la marca del guion, el segmento o el stop que nombra el aviso |
| `gaanim export` elige el formato por la extensión; `--frame`, `--from/--to` con marcadores, `--notes` | Presets con mensajes de progreso nativos de 0.12 (Windows Terminal los muestra también en la barra de tareas) |
| `GAANIM_EDITOR` con `{file}` y `{line}`: lo usan el inspector, la consola, el doble clic en la línea de animaciones y el panel de error | Las vistas previas lanzadas desde Neovim reciben un `GAANIM_EDITOR` que llama a **este** Neovim por su servidor RPC (`--remote-expr`) |
| Guion en `narration/script.md`: `## nombre`, `[stop]`/`[stop nombre]`/`[stop: nombre]`, `###` no se lee, comentarios HTML ignorados, encabezados sin distinguir mayúsculas | Ventana lateral que sigue al cursor, salto código ↔ sección, secciones nuevas con sus marcas, tiempos estimados |
| `scene.voiceover(key)` con tomas `narration/<key>.wav` y su `.json` (palabras con tiempos) | Marca `● take` / `○ no take` en cada voiceover |
| Documentación en Typst dentro del wheel (`.venv/Lib/site-packages/gaanim/_docs`), con `#api-entry(name: "Scene.voiceover", …)` | `:Gaanim docs` y `:Gaanim api` buscan en la versión instalada |
| Stubs `.pyi` completos en el `.venv` del proyecto | El plugin apunta pyright/basedpyright a ese `.venv` |

Detalles comprobados en el código: `crates/gaanim_launcher/src/file_watcher.rs`,
`crates/gaanim_launcher/src/hot_reload.rs`, `crates/gaanim_editor/src/source_link.rs`,
`crates/gaanim_media/src/narration.rs`, `crates/gaanim_timeline/src/notes.rs`,
`crates/gaanim_core/src/console.rs`.

## Qué hace el plugin hoy

| Necesidad del flujo | Comando |
|---|---|
| Empezar | `:Gaanim new slides charla` → `gaanim init` en `projects_dir`, entra con `:tcd` y abre `main.py`; `:Gaanim projects` para volver |
| Ver mientras escribo | `:Gaanim preview [here\|only]` |
| Saber si algo se rompió | Check al guardar + errores de la vista previa como diagnósticos; `:Gaanim log` |
| Orientarme en un proyecto grande | `:Gaanim outline` y movimientos `]v`/`[v` (diapositiva) y `]V`/`[V` (stop) |
| Escribir lo que voy a decir | `:Gaanim script` (sigue al cursor), `:Gaanim script goto` (ida y vuelta, crea secciones), tiempos frente a `target=` |
| Sacar el resultado | `:Gaanim export`, `:Gaanim still`, `:Gaanim present` |
| Recordar la API | `:Gaanim api` (palabra bajo el cursor), `:Gaanim docs`, snippets `gseg`, `gstop`, `gplay`, `gvo`… |
| Volver al código desde la app | Automático en las vistas previas lanzadas desde Neovim |

Probado contra el Gaanim instalado: vista previa desde la diapositiva del
cursor, error de Python en vivo como diagnóstico en su línea, recarga a
`ready`, `check`, exportación MP4 y PNG fijo, y el comando de `GAANIM_EDITOR`
abriendo `main.py:36` en otro Neovim. 26 pruebas automáticas con
`nvim -l tests/run.lua`.

## Flujos recomendados

### Diapositivas: primero lo que vas a decir

1. `:Gaanim new slides charla`. Fija la duración con `scene.slides.target()` y
   un `target=` por segmento.
2. Escribe el esqueleto: un `scene.segment(...)` por diapositiva (snippet
   `gseg`) con sus `scene.stop("nombre")`, sin animar todavía.
3. `:Gaanim script goto` en cada segmento crea su sección con una marca por
   stop. Escribe el guion ahí: la virtual text dice si cada diapositiva cabe
   en su tiempo (verde, ámbar, rojo) y el título, si cabe la charla.
4. Anima con `:Gaanim preview here` abierto: cada guardado recarga; los errores
   llegan a su línea.
5. Ensaya y graba los tiempos reales en la app (*Record the talk*, Scribe) y
   presenta con `:Gaanim present 20m`.

Es el guion a dos columnas (audio primero, imagen después) que usa la
producción de video explicativo, con la estimación por palabras que la
industria usa para planificar duraciones (130–150 palabras por minuto; el
plugin y Gaanim usan 150).

### Video con narración

1. `:Gaanim new video explicacion`. Un `## clave` por bloque de narración en
   `script.md`; en el código, `with scene.voiceover("clave") as vo:`.
2. Sin tomas grabadas, Gaanim estima la duración del bloque por su texto: se
   puede animar entero antes de grabar. El plugin muestra `○ no take`.
3. Graba las tomas en la app; `vo.wait_until("palabra")` sincroniza con la
   palabra dicha (marcas, luego la transcripción de whisper, luego la
   posición proporcional).
4. `:Gaanim export draft` para revisar, `:Gaanim export production` al final;
   `--from`/`--to` con `scene.marker()` para exportar un tramo.

### Proyectos grandes

Un módulo por diapositiva (como un capítulo con veinte diapositivas) funciona
si el plugin sabe cómo se llaman. `outline.patterns` le enseña la convención
del proyecto, por ejemplo `NOMBRE = "Portada"` en cada módulo.

## Ideas de otras herramientas

- **Vista previa enlazada al cursor.** typst-preview.nvim habla con su
  servidor por websocket: el editor manda `panelScrollTo` al mover el cursor y
  la vista previa manda `editorScrollTo` al hacer clic. Es el modelo para un
  canal de control en Gaanim.
- **Línea de tiempo dirigida por eventos de audio.** Motion Canvas nombra
  instantes (`waitUntil('evento')`) que se arrastran en su editor para
  alinearlos con la voz. Gaanim ya tiene el equivalente en
  `vo.wait_until("palabra")`.
- **Abrir en el editor desde todo.** Remotion abre composiciones, secuencias y
  frames de error en el editor, y tiene marcas de entrada y salida que acotan
  la exportación.
- **Notas que avanzan solas.** Slidev ilumina el tramo de notas de cada clic
  (`[click]`); Gaanim ya lo hace con `[stop]` y el prompter.
- **Presentar desde la terminal.** presenterm.nvim ofrece movimientos entre
  diapositivas, un picker, un componente de statusline y estimaciones de
  tiempo; las notas van en una segunda instancia sincronizada.
- **Subtítulos.** Remotion normaliza las transcripciones (whisper.cpp,
  OpenAI…) a un solo tipo de subtítulo. SRT usa coma antes de los
  milisegundos y cues numerados; WebVTT, cabecera `WEBVTT` y punto.

## Hoja de ruta del plugin (sin cambios en Gaanim)

1. **Esquema con Tree-sitter.** Una consulta propia
   (`queries/python/gaanim_outline.scm`) en lugar de patrones de texto:
   nombres en llamadas de varias líneas, `live_take`, y sin falsos positivos en
   docstrings.
2. **Del guion al código.** Generar los `segment`/`voiceover`/`stop` que faltan
   a partir de los `##` y `[stop]` de `script.md` (el camino inverso de
   `script goto`).
3. **Inspector de tomas.** Leer `narration/<key>.json` (palabras y tiempos),
   avisar cuando un `wait_until("…")` no aparece en la transcripción (caería en
   la posición proporcional) y reproducir desde una palabra con `ffplay -ss`.
4. **Subtítulos por toma** en SRT/VTT desde las palabras del sidecar.
5. **Duración real de las tomas** con `ffprobe` junto a la estimada y al
   `target=`.
6. **Resaltado Typst** dentro de las cadenas de matemáticas y texto
   enriquecido (inyecciones de Tree-sitter con `; extends`).
7. **Plantillas de overseer** (`lua/overseer/template/gaanim.lua`) para quien
   prefiera sus tareas y su `restart_on_save`.
8. **Fotogramas en la terminal.** snacks.image solo habla el protocolo de
   gráficos de kitty (kitty, Ghostty, WezTerm con limitaciones); Windows
   Terminal tiene sixel desde 1.22 pero no ese protocolo. Hoy `:Gaanim still`
   escribe el PNG; mostrarlo dentro de Neovim solo vale con otra terminal.
9. **Ayudas de presentación:** elegir monitor, pedir la duración, ensayar desde
   un segmento, PDF de notas en un paso.
10. **Publicar:** etiquetas `vX.Y.Z` (las fijan lazy.nvim y `vim.pack`),
    vimdoc generado desde las anotaciones (vimcats) y luarocks con
    luarocks-tag-release si se quiere distribuir.

## Lo que Gaanim podría exponer

Ordenado por lo que desbloquea:

Propuesto en [#529](https://github.com/PaoloLupo/gaanim/issues/529) (puntos 1–3),
[#530](https://github.com/PaoloLupo/gaanim/issues/530) (punto 4) y
[#531](https://github.com/PaoloLupo/gaanim/issues/531) (puntos 5 y 6); el 7 ya
estaba en [#430](https://github.com/PaoloLupo/gaanim/issues/430) (subtítulos),
[#427](https://github.com/PaoloLupo/gaanim/issues/427) (capítulos) y
[#429](https://github.com/PaoloLupo/gaanim/issues/429) (palabras con tiempos).

1. **Canal de control de la vista previa** (tubería con nombre o JSON por
   stdin): `seek` a un tiempo, segmento o stop; «seguir al cursor»; y eventos
   de vuelta (cabezal, diapositiva actual). Hoy `preview here` reinicia la
   vista previa entera, y lo único que la mueve desde fuera es escribir un
   archivo.
2. **Índice de la línea de tiempo** (`gaanim inspect --json`): segmentos,
   stops, marcadores y voiceovers con sus tiempos y sus líneas de código. Los
   datos ya existen en el editor (`AuthoredIndex`, `clip_origins`,
   `op_locations`) pero solo se graban en sesiones del editor y no se exportan.
   Daría tiempos en el esquema, línea → tiempo para el canal anterior,
   capítulos de YouTube y subtítulos del video entero.
3. **Salida para máquinas** (`--message-format json`) en `check`, `export` y la
   vista previa: diagnósticos con archivo y línea (hoy casi todos los avisos de
   `check` no la tienen y el plugin la deduce), progreso en porcentaje (hoy el
   porcentaje solo sale con `GAANIM_EXPORT_WORKER`), inicio y fin de cada
   recarga.
4. **Nombres de segmento y stop en `--frame`, `--from` y `--to` de `export`**,
   como ya acepta `--from` de la vista previa. Hoy `--frame Problema` falla con
   «unknown marker» y `:Gaanim still` no puede exportar «esta diapositiva».
5. **Abrir el guion con `GAANIM_EDITOR`.** *Open and complete* abre
   `script.md` con la aplicación por defecto del sistema en vez del editor.
6. **Proyectos listos para el editor:** `[tool.pyright] venvPath = "."` y
   `venv = ".venv"` en el `pyproject.toml` de `gaanim init` (pyright no busca
   el `.venv` solo).
7. **Narración desde la CLI:** `gaanim export --captions out.srt|vtt` y un
   archivo de capítulos; `gaanim narration record|transcribe <clave>` para
   reutilizar la grabadora, whisper y el formato del sidecar de la app.

## Limitaciones conocidas

- `preview here` reinicia la vista previa (no hay forma de moverla desde
  fuera). En la charla de prueba la escena estuvo lista en 0,3–0,8 s, pero la
  ventana se cierra y se vuelve a abrir.
- El esquema lee el código con patrones de texto: los nombres construidos en
  tiempo de ejecución (`f"burn {i}"`, `modulo.NOMBRE`) necesitan
  `outline.patterns`.
- En Windows los procesos hijos de Neovim mueren con él (libuv los mete en un
  *job object* con `KILL_ON_JOB_CLOSE`); por eso `preview.stop_on_exit` es lo
  natural.
- `--remote-expr` no trae la terminal al frente: el salto llega a Neovim y
  avisa, pero hay que cambiar de ventana.
- No probado de punta a punta: hacer clic en *Open in the editor* dentro de la
  ventana de Gaanim (sí se probó el comando exacto que Gaanim ejecuta).
- En esta máquina no hay servidor LSP de Python instalado: sin él no hay
  autocompletado de la API. En LazyVim, el extra `lang.python`.

## Fuentes

- Buenas prácticas de plugins: https://github.com/lumen-oss/nvim-best-practices
- Neovim 0.12: `:h news-0.12`, `:h progress-message`, `:h vim.pack`, `:h remote.txt`
- Barra de progreso de Windows Terminal (OSC 9;4): https://learn.microsoft.com/en-us/windows/terminal/tutorials/progress-bar-sequences
- typst-preview.nvim: https://github.com/chomosuke/typst-preview.nvim
- presenterm.nvim: https://github.com/Piotr1215/presenterm.nvim
- overseer.nvim: https://github.com/stevearc/overseer.nvim/blob/master/doc/guides.md
- snacks.nvim (picker, image): https://github.com/folke/snacks.nvim/tree/main/docs
- Windows Terminal y sixel: https://devblogs.microsoft.com/commandline/windows-terminal-preview-1-22-release
- Motion Canvas, eventos de tiempo: https://motioncanvas.io/docs/time-events
- Remotion, subtítulos y abrir en el editor: https://www.remotion.dev/docs/captions/api, https://remotion.dev/docs/studio/open-in-editor
- Slidev, marcas de clic: https://sli.dev/features/click-marker
- WebVTT: https://www.w3.org/TR/webvtt1/
- Captura de audio con FFmpeg en Windows: https://trac.ffmpeg.org/wiki/Capture/Desktop
- Guion a dos columnas: https://www.studiobinder.com/templates/av-scripts/two-column-script-template/
- Resolución de importaciones de pyright: https://github.com/microsoft/pyright/blob/main/docs/import-resolution.md
