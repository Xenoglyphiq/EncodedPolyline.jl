# Conformance runner: every case in the vendored spec's manifest.
# Loaded by runtests.jl. Set POLYLINE_MANIFEST to run against another manifest.

using JSON3
using EncodedPolyline: EncodedPolyline, LonLat, PolylineError, Limits

const DEFAULT_MANIFEST = joinpath(@__DIR__, "..", ".spec", "conformance", "manifest.json")

# Canonical JSON floats: numbers, or "NaN" / "Infinity" / "-Infinity" strings.
function canon_float(v)::Float64
    v isa Number && return Float64(v)
    v == "NaN" && return NaN
    v == "Infinity" && return Inf
    v == "-Infinity" && return -Inf
    error("not a canonical float: $(repr(v))")
end

to_points(v) = LonLat[LonLat(canon_float(p["lon"]), canon_float(p["lat"])) for p in v]

function call_options(case)
    o = get(case, "options", nothing)
    precision = o === nothing ? 5 : get(o, "precision", 5)
    limits = Limits(;
        max_points=UInt64(o === nothing ? 1_000_000 : get(o, "max_points", 1_000_000)),
        max_text_length=UInt64(o === nothing ? 16 * 1024 * 1024 : get(o, "max_text_length", 16 * 1024 * 1024)))
    return (; precision, limits)
end

"""Run one case; return `nothing` on pass, or a reason string on failure."""
function run_case(case)::Union{Nothing,String}
    op = case["op"]
    input = case["input"]["value"]
    expect = case["expect"]
    kw = call_options(case)
    result = try
        op == "encode" ? EncodedPolyline.encode(to_points(input); kw...) :
        op == "decode" ? EncodedPolyline.decode(String(input); kw...) :
        return "unknown op $op"
    catch e
        e isa PolylineError || return "unexpected exception $(sprint(showerror, e))"
        haskey(expect, "error") || return "unexpected error $(e.code) ($(e.kind))"
        want = expect["error"]
        (String(e.kind) == want["kind"] && e.code == want["code"]) ||
            return "expected $(want["kind"])/$(want["code"]), got $(e.kind)/$(e.code)"
        if haskey(want, "offset")
            e.offset == want["offset"] || return "expected offset $(want["offset"]), got $(e.offset)"
        end
        return nothing
    end
    haskey(expect, "value") || return "expected an error, got $(repr(result))"
    if op == "encode"
        result == expect["value"] && return nothing
        return "expected $(repr(String(expect["value"]))), got $(repr(result))"
    end
    want = to_points(expect["value"])
    tol = Float64(get(case, "tolerance", 0.0))
    length(result) == length(want) || return "expected $(length(want)) points, got $(length(result))"
    for (k, (g, w)) in enumerate(zip(result, want))
        (abs(g.lon - w.lon) <= tol && abs(g.lat - w.lat) <= tol) ||
            return "point $k: expected ($(w.lon), $(w.lat)), got ($(g.lon), $(g.lat))"
    end
    return nothing
end

"""Run the manifest; print failures and the summary line; return (passed, total)."""
function run_conformance(path=get(ENV, "POLYLINE_MANIFEST", DEFAULT_MANIFEST))
    manifest = JSON3.read(read(path, String))
    passed = 0
    cases = manifest["cases"]
    for case in cases
        why = run_case(case)
        why === nothing ? (passed += 1) : println("FAIL $(case["id"]): $why")
    end
    # No io-level cases exist; every case is core, so full == core.
    total = length(cases)
    println("polyline julia (spec $(manifest["spec_version"])): core $passed/$total, full $passed/$total")
    return passed, total
end
