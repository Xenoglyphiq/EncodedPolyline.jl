using Test
using EncodedPolyline
using EncodedPolyline: encode, decode

include("conformance.jl")

const GOOGLE_POINTS = [LonLat(-120.2, 38.5), LonLat(-120.95, 40.7), LonLat(-126.453, 43.252)]
const GOOGLE_TEXT = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"

@testset "EncodedPolyline" begin
    @testset "Google's example" begin
        @test encode(GOOGLE_POINTS) == GOOGLE_TEXT
        pts = decode(GOOGLE_TEXT)
        @test length(pts) == 3
        @test all(isapprox(a.lon, b.lon; atol=1e-12) && isapprox(a.lat, b.lat; atol=1e-12)
                  for (a, b) in zip(pts, GOOGLE_POINTS))
    end

    @testset "type stability" begin
        @inferred encode(GOOGLE_POINTS)
        @inferred encode(GOOGLE_POINTS; precision=6)
        @inferred decode(GOOGLE_TEXT)
        @inferred decode(GOOGLE_TEXT; precision=6)
    end

    @testset "rounding is half away from zero" begin
        @test EncodedPolyline.scale_value(2.5, 1.0) == 3
        @test EncodedPolyline.scale_value(-2.5, 1.0) == -3
        @test EncodedPolyline.scale_value(0.49999999999999994, 1.0) == 0
    end

    @testset "errors carry kind, code and offset" begin
        err = try decode("_p~iF ~ps|U"); nothing catch e; e end
        @test err isa PolylineError
        @test err.kind === :invalid_input
        @test err.code == "polyline.invalid_char"
        @test err.offset == 5
    end

    @testset "conformance" begin
        passed, total = run_conformance()
        @test total > 0
        @test passed == total
    end

    if haskey(ENV, "FUZZ_SECONDS")
        include("fuzz.jl")
        @testset "fuzz" begin
            seed = haskey(ENV, "FUZZ_SEED") ? parse(UInt64, ENV["FUZZ_SEED"]) : UInt64(time_ns())
            @test fuzz(parse(Float64, ENV["FUZZ_SECONDS"]), seed) > 0
        end
    end
end
