# Polyline for Julia

Encode and decode lists of coordinates as compact ASCII strings. Implements Google's Encoded Polyline Algorithm Format · Spec v0.1.1 · Conformance: **core ✓ full ✓** (44/44)

> **Coordinate order:** `LonLat` is `(lon, lat)`; the encoded string stores latitude first. The package converts at the boundary.

Package name: **`EncodedPolyline`**. Julia 1.10 (LTS) or later. No dependencies.

## Install

> **Not registered yet.** The first release goes to Julia's General registry; until then, add it from the repo:
> `Pkg.add(url="https://github.com/Xenoglyphiq/EncodedPolyline.jl")`

Once registered:

```julia
using Pkg
Pkg.add("EncodedPolyline")
```

## Quick start

```julia
using EncodedPolyline

text = EncodedPolyline.encode([LonLat(-120.2, 38.5), LonLat(-120.95, 40.7)])
points = EncodedPolyline.decode(text)
```

`encode` and `decode` are deliberately not exported, because the names are too generic; call them qualified.

## Examples

Each runs with `julia --project examples/<name>.jl`.

### 1. Encode a three-point route (`examples/encode_route.jl`)
```julia
route = [LonLat(-120.2, 38.5), LonLat(-120.95, 40.7), LonLat(-126.453, 43.252)]
println(EncodedPolyline.encode(route))   # _p~iF~ps|U_ulLnnqC_mqNvxq`@
```

### 2. Decode Google's example (`examples/decode_route.jl`)
```julia
points = try
    EncodedPolyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
catch e
    e isa PolylineError && println(stderr, sprint(showerror, e))
    rethrow()
end
for p in points
    println("lon $(p.lon), lat $(p.lat)")
end
```

### 3. Round-trip at precision 6 (`examples/precision_6.jl`)
```julia
text = EncodedPolyline.encode(route; precision=6)   # OSRM, Valhalla
back = EncodedPolyline.decode(text; precision=6)
```

## Limits and errors

| Limit | Default | Option name |
|---|---|---|
| Points accepted or produced | 1,000,000 | `Limits(; max_points)` |
| Input length for `decode` | 16 MiB | `Limits(; max_text_length)` |

Pass limits as `limits = Limits(max_points = 10_000)`. Precision (1–10, default 5) is the `precision` keyword.

Errors are `PolylineError` with a `kind` (`:invalid_input` or `:limit_exceeded`), a stable `code` such as `"polyline.invalid_char"`, and a zero-based byte `offset` where the spec defines one. Full list: spec §3.

`\` is a valid polyline character. Strings copied from JavaScript source often contain `\\` escapes and decode to different points without any error.

## Modules

| Module | Layer | Needs |
|---|---|---|
| `EncodedPolyline` | core | nothing beyond Base |

There is no io layer: everything works on in-memory strings and vectors.

## Development

| Command | What |
|---|---|
| `julia --project -e 'using Pkg; Pkg.test()'` | Unit tests, type-stability checks and every conformance case |
| `FUZZ_SECONDS=60 julia --project -e 'using Pkg; Pkg.test()'` | Also fuzz `decode` for 60 s (`FUZZ_SEED` to reproduce a run) |
| `julia --project bench/bench.jl` | Timings on `.spec/bench/route_100k.polyline` (method in `.spec/bench/README.md`) |

## Related packages

- [`Polyline.jl`](https://github.com/NikStoyanov/Polyline.jl) holds the `Polyline` name in General. It's unmaintained since 2020, truncates instead of rounding, and mis-decodes precision 6 and above.
- [`GooglePolyline.jl`](https://github.com/cluffa/GooglePolyline.jl) is active but unregistered. It rounds half to even and takes precision as a factor (`100_000`) rather than a number of decimal places.

This package rounds half away from zero, like the widely used Python `polyline` and Mapbox JavaScript packages, and passes the shared conformance suite.

## Performance

| Benchmark | Reference | This port | Ratio |
|---|---|---|---|
| Encode 100k points | Rust `polyline` 0.11.0: 0.892 ms | 1.466 ms | 1.64× |
| Decode 100k points | Rust `polyline` 0.11.0: 0.643 ms | 0.816 ms | 1.27× |

Medians on `.spec/bench/route_100k.polyline` (100,000 points), measured 2026-10-05 on an Apple M5 Pro with `julia --project bench/bench.jl`, Julia 1.13.1. Three rounds interleaved with the reference, following `.spec/bench/README.md`. Ratio = this port ÷ reference; the spec's target is within 2×.

## License

MIT OR Apache-2.0
