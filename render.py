"""Render a fractal on a Modal L4 GPU using the local source files.

    pixi run render --out out.png --cx -0.75 --cy 0.1 --zoom 200 --max-iter 2000
    pixi run render --out julia.png --julia-re -0.8 --julia-im 0.156

A ".svg" --out traces the render into vector color bands (--colors 1-8 sets the
colour precision: higher means more bands and a bigger file).

Local fractal.mojo / pixi.toml are copied into the image, so edits deploy without a push.
The image build (pixi install, which compiles the kernel) is cached until those files change.
"""

import modal

APP_DIR = "/app"
BUILT_MARKER = "/tmp/fractal_built"
PROJECT_FILES = ["fractal.mojo", "pixi.toml", "pixi.lock", "render.sh"]

image = (
    modal.Image.debian_slim()
    .apt_install("curl", "ca-certificates")
    .pip_install("vtracer")
    .run_commands("curl -fsSL https://pixi.sh/install.sh | bash")
    .env({"PATH": "/root/.pixi/bin:/usr/local/bin:/usr/bin:/bin"})
)
for name in PROJECT_FILES:
    image = image.add_local_file(name, f"{APP_DIR}/{name}", copy=True)
image = image.workdir(APP_DIR).run_commands("pixi install")

app = modal.App("mojo-fractal-gpu", image=image)


@app.function(gpu="L4", timeout=600)
def render(args: list[str], svg: bool = False, colors: int = 6) -> tuple[bytes, str]:
    import os
    import subprocess

    out = "/tmp/out.png"
    # The kernel is compiled for the build host's CPU; rebuild here so it matches this
    # container's CPU (a binary built at image-build time can die with SIGILL).
    if not os.path.exists(BUILT_MARKER):
        subprocess.run(["pixi", "reinstall", "fractal"], cwd=APP_DIR, check=True)
        open(BUILT_MARKER, "w").close()
    proc = subprocess.run(
        ["pixi", "run", "render-gpu", out, *args],
        cwd=APP_DIR,
        capture_output=True,
        text=True,
    )
    log = proc.stdout + proc.stderr
    if proc.returncode != 0:
        raise RuntimeError(f"render failed ({proc.returncode}):\n{log}")
    if svg:
        import vtracer

        # Trace the render into stacked, filled color-band polygons. Fewer colour bits
        # means fewer, larger bands; speckle filtering drops sub-pixel noise.
        vtracer.convert_image_to_svg_py(
            out,
            "/tmp/out.svg",
            colormode="color",
            hierarchical="stacked",
            mode="spline",
            filter_speckle=8,
            color_precision=colors,
            layer_difference=16,
        )
        out = "/tmp/out.svg"
    with open(out, "rb") as f:
        return f.read(), log


@app.local_entrypoint()
def main(
    out: str = "out.svg",
    width: int = 1024,
    height: int = 768,
    cx: float = -0.75,
    cy: float = 0.1,
    zoom: float = 200.0,
    max_iter: int = 2000,
    julia_re: float | None = None,
    julia_im: float | None = None,
    colors: int = 6,
):
    args = [str(width), str(height), str(cx), str(cy), str(zoom), str(max_iter)]
    if julia_re is not None and julia_im is not None:
        args += ["1", str(julia_re), str(julia_im)]

    data, log = render.remote(args, svg=out.endswith(".svg"), colors=colors)
    with open(out, "wb") as f:
        f.write(data)
    print(log.strip())
    print(f"saved {out}")
