# GPU fractal renderer: one GPU thread per pixel computes a smooth-colored
# Mandelbrot (or Julia) escape-time value and writes RGB bytes.
#
# Usage: mojo run fractal.mojo -- <out.ppm> <width> <height> <center_x> <center_y>
#                                  <zoom> <max_iter> <julia 0|1> <julia_re> <julia_im>

from max.gpu import block_dim, block_idx, thread_idx
from max.gpu.host import DeviceContext
from std.math import cos, log2, sqrt
from std.sys import argv, has_accelerator
from std.time import perf_counter_ns

comptime BLOCK = 16


def fractal_kernel(
    buf: Pointer[UInt8, MutAnyOrigin],
    width_: Int32,
    height_: Int32,
    center_x: Float64,
    center_y: Float64,
    scale: Float64,
    max_iter_: Int32,
    julia_: Int32,
    julia_re: Float64,
    julia_im: Float64,
):
    var width = Int(width_)
    var height = Int(height_)
    var max_iter = Int(max_iter_)
    var julia = Int(julia_)
    var px = Int(block_idx.x * block_dim.x + thread_idx.x)
    var py = Int(block_idx.y * block_dim.y + thread_idx.y)
    if px >= width or py >= height:
        return

    # Map pixel to complex plane; scale = width of view in plane units.
    var x0 = center_x + (Float64(px) - Float64(width) / 2) * scale / Float64(width)
    var y0 = center_y - (Float64(py) - Float64(height) / 2) * scale / Float64(width)

    var zr: Float64
    var zi: Float64
    var cr: Float64
    var ci: Float64
    if julia != 0:
        zr = x0
        zi = y0
        cr = julia_re
        ci = julia_im
    else:
        zr = 0
        zi = 0
        cr = x0
        ci = y0

    var i = 0
    var r2 = zr * zr
    var i2 = zi * zi
    while i < max_iter and r2 + i2 <= 256.0:
        zi = 2 * zr * zi + ci
        zr = r2 - i2 + cr
        r2 = zr * zr
        i2 = zi * zi
        i += 1

    var idx = (py * width + px) * 3
    if i >= max_iter:
        buf[unsafe_offset=idx] = 0
        buf[unsafe_offset=idx + 1] = 0
        buf[unsafe_offset=idx + 2] = 0
        return

    # Smooth iteration count -> cosine palette (Inigo Quilez style).
    var mag = Float32(sqrt(r2 + i2))
    var mu = Float32(i) + 1 - log2(log2(mag))
    var t = mu * Float32(0.035)
    comptime TAU: Float32 = 6.2831853
    var r = 0.5 + 0.5 * cos(TAU * (t + 0.00))
    var g = 0.5 + 0.5 * cos(TAU * (t + 0.15))
    var b = 0.5 + 0.5 * cos(TAU * (t + 0.30))
    buf[unsafe_offset=idx] = UInt8(Int(r * 255))
    buf[unsafe_offset=idx + 1] = UInt8(Int(g * 255))
    buf[unsafe_offset=idx + 2] = UInt8(Int(b * 255))


def main() raises:
    var args = argv()
    var path = String(args[1]) if len(args) > 1 else "fractal.ppm"
    var width = Int(args[2]) if len(args) > 2 else 1024
    var height = Int(args[3]) if len(args) > 3 else 768
    var center_x = Float64(args[4]) if len(args) > 4 else -0.743643887037151
    var center_y = Float64(args[5]) if len(args) > 5 else 0.13182590420533
    var zoom = Float64(args[6]) if len(args) > 6 else 1.0
    var max_iter = Int(args[7]) if len(args) > 7 else 1000
    var julia = Int(args[8]) if len(args) > 8 else 0
    var julia_re = Float64(args[9]) if len(args) > 9 else -0.8
    var julia_im = Float64(args[10]) if len(args) > 10 else 0.156

    comptime if not has_accelerator():
        print("ERROR: no GPU accelerator found")
        return

    var ctx = DeviceContext()
    print("GPU:", ctx.name())
    var n = width * height * 3
    var dev = ctx.enqueue_create_buffer[DType.uint8](n)

    var scale = 3.5 / zoom
    var grid_x = (width + BLOCK - 1) // BLOCK
    var grid_y = (height + BLOCK - 1) // BLOCK

    var t0 = perf_counter_ns()
    ctx.enqueue_function[fractal_kernel](
        dev,
        Int32(width),
        Int32(height),
        center_x,
        center_y,
        scale,
        Int32(max_iter),
        Int32(julia),
        julia_re,
        julia_im,
        grid_dim=(grid_x, grid_y),
        block_dim=(BLOCK, BLOCK),
    )
    ctx.synchronize()
    var ms = Float64(perf_counter_ns() - t0) / 1e6
    print("kernel_ms:", ms)

    var header = String("P6\n", width, " ", height, "\n255\n")
    with dev.map_to_host() as host:
        with open(path, "w") as f:
            f.write(header)
            f.write_bytes(Span(unsafe_ptr=host.unsafe_ptr(), length=n))
    print("wrote:", path)
