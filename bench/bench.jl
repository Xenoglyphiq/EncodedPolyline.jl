# Benchmark per `.spec/bench/README.md`: precision 5; decode once untimed;
# 3 warm-up runs, then 15 timed runs each of encode(points) and decode(text);
# report median and min. Run: julia --project bench/bench.jl [input]
# No dependencies; warm-up runs also absorb compilation.

using EncodedPolyline

const WARMUP = 3
const RUNS = 15

function timed(f)
    for _ in 1:WARMUP
        f()
    end
    ms = Float64[]
    for _ in 1:RUNS
        t = time_ns()
        f()
        push!(ms, (time_ns() - t) / 1e6)
    end
    sort!(ms)
    return ms[RUNS ÷ 2 + 1], ms[1]
end

function main(path=joinpath(@__DIR__, "..", ".spec", "bench", "route_100k.polyline"))
    text = rstrip(read(path, String), '\n') |> String
    points = EncodedPolyline.decode(text)
    EncodedPolyline.encode(points) == text || error("round trip must reproduce the input")

    enc_med, enc_min = timed(() -> EncodedPolyline.encode(points))
    dec_med, dec_min = timed(() -> EncodedPolyline.decode(text))
    fmt(x) = string(round(x; digits=3))
    println("polyline julia $(VERSION) ($(length(points)) points): ",
            "encode median $(fmt(enc_med)) ms (min $(fmt(enc_min))), ",
            "decode median $(fmt(dec_med)) ms (min $(fmt(dec_min)))")
end

main(ARGS...)
