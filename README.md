# mojo-fractal: a Mojo GPU kernel running on Modal

`fractal.mojo` is a Mojo GPU kernel (one GPU thread per pixel) that renders
smooth-coloured Mandelbrot and Julia sets.

## Build

The kernel is built with pixi's Mojo build backend
([pixi-build-mojo](https://prefix-dev.github.io/pixi-build-backends/backends/pixi-build-mojo/)).
`pixi.toml` declares `fractal` as a package, and `pixi install` compiles
`fractal.mojo` into a conda package whose `fractal` binary lands on the env's PATH.

```bash
pixi install                                   # builds fractal.mojo with pixi-build-mojo
pixi run render out.png 1024 768 <cx> <cy> <zoom> <max_iter> [1 <julia_re> <julia_im>]
```

The binary runs only where there's an NVIDIA GPU; it is compiled for the L4 (sm_89).

## Editor support

The env includes the Mojo language server. Point your editor's LSP client at
`pixi run lsp` (it speaks LSP over stdio), run from this folder so it picks up
the env's `max.gpu` packages for completion, hover and diagnostics.

For Zed, open this folder as the project with a Mojo extension installed.
Zed extensions look for `mojo-lsp-server` on PATH, so the folder ships an `.envrc`
that loads the pixi env, and `.zed/settings.json` sets `"load_direnv": "direct"`
so Zed runs it. Install direnv, run `pixi install` once and `direnv allow` in this
folder, then reopen it in Zed. Starting Zed from inside `pixi shell` also works
when no Zed window is already open.

## Running on Modal

It runs on Modal through the Modal MCP connector, which supplies the auth. No
Modal token or `modal deploy` is needed. The connector's `deploy_command_function`
deploys the app `mojo-fractal-gpu` on an L4. Its setup step copies these files
to `/app` and runs `bash modal_sandbox.sh setup` (installs pixi, then `pixi install`).
Each call then runs:

```bash
bash modal_sandbox.sh render /tmp/out.jpg 1024 768 <cx> <cy> <zoom> <max_iter>
```

Use `spawn_function` and `get_function_call_result` for the first call, since the
cold start (installing pixi and building) takes longer than `call_function` waits.

Measured on a Modal L4 at 1024×768:

- Seahorse valley at zoom 200 with 2000 iterations: about 27 ms of kernel time.
- Julia set: about 3.5 ms.
- Spiral at zoom 1e5 with 5000 iterations: about 3 ms (the first launch in a
  fresh container is about 50 ms while the GPU initialises).

`sample_l4.jpg`, `spiral_l4.jpg` and `renders/` show the results.

## Notes

- Packages come from `https://conda.modular.com/max`: `mojo` 1.1.0 for the
  compiler and `max-core` 26.6.0 for the `max.gpu` modules the kernel imports.
- Mojo links with a C compiler, so on linux-64 the build pulls conda-forge `gcc`
  with a glibc 2.34 sysroot. The linux platform in `pixi.toml` declares glibc 2.34
  because Mojo's runtime libraries need it.
- Iteration runs in Float64 so deep zooms stay sharp. Colouring uses Float32
  because `cos` on NVIDIA GPUs only supports 32-bit floats.
