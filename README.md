# Zero Graphics

A very minimal OpenGL ES 2.0 library for Zig. Opens you a window and let's you draw things.
Comes with a pixel-perfect 2D renderer and maybe some day even with a bit of a 3D api.

![Logo](design/logo.png)


## Features

- WebAssembly support
- Pixel perfect 2D rendering
  - Primitives (line, rectangle, triangle, ...)
  - Text / TTF fonts
  - Textures
- Basic 3D rendering
  - Multi-mesh models with flat textures
- Zig-style immediate-mode user interface
- Proper DPI scaling support in renderer


## Project status

### CI

The CI coverage currently looks like this:

<table>
  <thead>
    <tr>
      <th rowspan="2" scope='colgroup'>Target Feature</th>
      <th colspan="3" scope='colgroup'>Build Host Platform</th>
    </tr>
    <tr>
      <th scope='col'>Windows</th>
      <th scope='col'>macOS</th>
      <th scope='col'>Linux</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>zero-init</td>
      <td>❔</td>
      <td>❔</td>
      <td>✅</td>
    </tr>
    <tr>
      <td>zero-convert</td>
      <td>❔</td>
      <td>❔</td>
      <td>✅</td>
    </tr>
    <tr>
      <td>WebAssembly demo</td>
      <td>❔</td>
      <td>❔</td>
      <td>✅</td>
    </tr>
  </tbody>
</table>

Status: [![Nightly Build](https://github.com/mm318/zero-graphics/actions/workflows/nightly.yml/badge.svg)](https://github.com/mm318/zero-graphics/actions/workflows/nightly.yml)

### Previews

Work-in-progress, but works quite well already.

![Preview screenshot in Chrome](documentation/screen01.png)

## Project Goals

### Basic Framework

- [ ] Support the following target platforms
  - [x] WebAssembly
    - [x] Create OpenGL ES 2.0 context
    - [x] Input Mouse
    - [x] Input Keyboard
- [x] Create an OpenGL ES 2.0 context
- [x] Provide input events
  - [x] Single pointer motion (finger or mouse)
  - [x] Single click event (finger, mouse)
  - [ ] Text input for keyboard (utf-8 encoded)
- [x] Provide window events
  - [x] Resize
  - [x] Close
- [x] Provide access to the underlying backend
- [ ] Allow creation of single-file applications
  - [ ] Single executable for easy distribution
  - [ ] Embedded resources

### 2D Rendering library

- [ ] Pixel perfect drawing of
  - [x] Lines
  - [x] Rectangles
  - [ ] Images
    - [x] Basic "copy full texture to rectangle"
    - [ ] Copy portion of texture ("atlas rendering")
- [x] TTF font rendering via [`stb_ttf`](https://github.com/nothings/stb)
- [x] Image loading via [`zigimg`](https://github.com/zigimg/zigimg)
- [ ] Stack based/nested scissoring

### 3D Rendering library

- [ ] Tool based on Assimp to convert models into loadable format
  - [x] static geometry
  - [ ] dynamic/animated geometry
- [ ] Blender export script
- [x] Draw static geometry
- [ ] Draw animated geometry
  - [ ] Skinning based on skeletons
- [ ] Axis- and camera aligned billboards
- [ ] Basic particles
- [ ] Tiny built-in pipeline with
  - [ ] shadow mapping
  - [ ] planar reflections
  - [ ] water reflections

## Dependencies

### WebAssembly Target

- [zig 0.12.0](https://ziglang.org/download/)
- [js glue code](www/zero-graphics.js)
- [root page](www/application.ztt)

## Building / Running

To get started, clone the repo:

```sh-session
[user@computer work]$ git clone https://github.com/mm318/zero-graphics
```

### WebAssembly Target

Includes a teeny tiny web server for debugging.

```sh-session
[user@computer zero-graphics]$ zig build run-wasm
```

Now visit http://127.0.0.1:8000/demo_application.htm to see the demo.

## Documentation

### Getting started

To create a new project, build this repository with `zig build` first. Then use the tool `zero-init` from `zig-out/bin` to initialize a new project:

```sh-session
[felix@denkplatte-v2 ~]$ mkdir game
[felix@denkplatte-v2 ~]$ cd game
[felix@denkplatte-v2 game]$ /path/to/zero-graphics/zig-out/bin/zero-init symlink # initialize via symlink, quickest option. use zero-init -h to see all options
[felix@denkplatte-v2 game]$ ls
src  vendor  build.zig
[felix@denkplatte-v2 game]$ zig build
[felix@denkplatte-v2 game]$ zig build run
info(sdl): SDL Video Driver:     x11
info(sdl): Render resolution:  1280×720
info(sdl): Virtual resolution: 1280×720
info(demo): OpenGL Version:       OpenGL ES 3.2 Mesa 21.2.3
info(demo): OpenGL Vendor:        AMD
info(demo): OpenGL Renderer:      AMD Radeon(TM) Vega 10 Graphics (RAVEN, DRM 3.41.0, 5.13.19_1, LLVM 12.0.1)
info(demo): OpenGL GLSL:          OpenGL ES GLSL ES 3.20
info(zero_graphics): [shader compiler] [other] Shader Stats: SGPRS: 16 VGPRS: 8 Code Size: 212 LDS: 0 Scratch: 0 Max Waves: 10 Spilled SGPRs: 0 Spilled VGPRs: 0 PrivMem VGPRs: 0
info(zero_graphics): [shader compiler] [other] Shader Stats: SGPRS: 16 VGPRS: 8 Code Size: 40 LDS: 0 Scratch: 0 Max Waves: 10 Spilled SGPRs: 0 Spilled VGPRs: 0 PrivMem VGPRs: 0
info(zero_graphics): [shader compiler] [other] Shader Stats: SGPRS: 8 VGPRS: 24 Code Size: 52 LDS: 0 Scratch: 0 Max Waves: 10 Spilled SGPRs: 0 Spilled VGPRs: 0 PrivMem VGPRs: 0
info(zero_graphics): [shader compiler] [other] Shader Stats: SGPRS: 8 VGPRS: 24 Code Size: 24 LDS: 0 Scratch: 0 Max Waves: 10 Spilled SGPRs: 0 Spilled VGPRs: 0 PrivMem VGPRs: 0
info(zero_graphics): [shader compiler] [other] Shader Stats: SGPRS: 8 VGPRS: 8 Code Size: 60 LDS: 0 Scratch: 0 Max Waves: 10 Spilled SGPRs: 0 Spilled VGPRs: 0 PrivMem VGPRs: 0
info(zero_graphics): [shader compiler] [other] Shader Stats: SGPRS: 16 VGPRS: 20 Code Size: 392 LDS: 0 Scratch: 0 Max Waves: 10 Spilled SGPRs: 0 Spilled VGPRs: 0 PrivMem VGPRs: 0
```

Check out the file [`src/main.zig`](tools/zero-init/template/src/main.zig) to see your app skeleton.
You can also adjust the [`build.zig`](tools/zero-init/template/build.zig) to set your project name.

The functions are roughly called in this order:

![Application workflow](documentation/app_flow.svg)

The separation between _application init_ and _graphics init_ is so that your application state will not be destroyed,
so the rendering can render the same data as before.

### Architecture

`zero-graphics` follows a somewhat unusual architecture for Zig applications.
Your applications is a _package_ that will be consumed by a `zero-graphics` host. This host is implementing the "main loop"
and will invoke both `update` and `render` periodically. It will also initialize and open the window and pump events.

This design allows `zero-graphics` to run on several different platforms, including WebAssembly.

You can check out the [Sdk.zig](Sdk.zig) file to find out how a application is built.
