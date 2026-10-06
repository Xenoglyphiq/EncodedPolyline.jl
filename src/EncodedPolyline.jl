"""
    EncodedPolyline

Google's Encoded Polyline Algorithm Format: encode and decode lists of
coordinates as compact ASCII strings.

Implements the polyline spec (see `.spec/spec/SPEC.md`). Points are
`(lon, lat)`; the encoded string stores latitude first.

The two operations are deliberately not exported (the names are too generic);
call them qualified: `EncodedPolyline.encode`, `EncodedPolyline.decode`.
"""
module EncodedPolyline

export LonLat, PolylineError, Limits

"""
    LonLat(lon, lat)

A WGS84 coordinate in degrees. Field order matches the API, not the string.
"""
struct LonLat
    lon::Float64
    lat::Float64
end

"""
    PolylineError(kind, code, offset)

Raised by `encode` and `decode`. `kind` is the spec's error kind
(`:invalid_input` or `:limit_exceeded`), `code` the stable spec code such as
`"polyline.invalid_char"`, and `offset` the byte offset into the input when
the spec defines one (zero-based), otherwise `nothing`.
"""
struct PolylineError <: Exception
    kind::Symbol
    code::String
    offset::Union{Nothing,UInt64}
end

function Base.showerror(io::IO, e::PolylineError)
    print(io, "PolylineError(", e.kind, "): ", e.code)
    e.offset === nothing || print(io, " at byte ", e.offset)
end

"""
    Limits(; max_points = 1_000_000, max_text_length = 16 MiB)

Limits on untrusted input, with the spec's defaults.
"""
Base.@kwdef struct Limits
    max_points::UInt64 = 1_000_000
    max_text_length::UInt64 = 16 * 1024 * 1024
end

# Exact powers of ten for precision 0–10 (index p + 1).
const POW10 = (1.0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10)
const TWO63 = 0x1p63

@noinline invalid(code::String, offset=nothing) =
    throw(PolylineError(:invalid_input, "polyline." * code, offset === nothing ? nothing : UInt64(offset)))
@noinline limit(code::String) = throw(PolylineError(:limit_exceeded, "polyline." * code, nothing))

function scale_for(precision::Integer)
    1 <= precision <= 10 || invalid("precision_out_of_range")
    return POW10[precision + 1]
end

# Spec §3 `encode`, step 3. RoundNearestTiesAway is the family-wide rule;
# Julia's default `round` is half to even and must not be used here.
function scale_value(x::Float64, scale::Float64)::Int64
    isfinite(x) || invalid("non_finite")
    s = x * scale
    -TWO63 <= s < TWO63 || invalid("overflow")
    return Int64(round(s, RoundNearestTiesAway))
end

zigzag(d::Int64)::UInt64 = reinterpret(UInt64, d << 1) ⊻ reinterpret(UInt64, d >> 63)

function encoded_len(d::Int64)::Int
    u = zigzag(d)
    n = 1
    while u >= 0x20
        u >>= 5
        n += 1
    end
    return n
end

function write_value!(out::Vector{UInt8}, i::Int, d::Int64)::Int
    u = zigzag(d)
    while u >= 0x20
        out[i] = UInt8((0x20 | (u & 0x1f)) + 63)
        i += 1
        u >>= 5
    end
    out[i] = UInt8(u + 63)
    return i + 1
end

function checked_delta(curr::Int64, prev::Int64)::Int64
    d, overflowed = Base.Checked.sub_with_overflow(curr, prev)
    overflowed && invalid("overflow")
    return d
end

"""
    EncodedPolyline.encode(points; precision = 5, limits = Limits()) -> String

Spec operation `encode`. Encodes `points` (`LonLat` values) as a polyline
string. `precision` is the number of decimal places kept, 1–10.

Throws `PolylineError` with code `polyline.precision_out_of_range`,
`polyline.too_many_points`, `polyline.non_finite` or `polyline.overflow`.
"""
function encode(points::AbstractVector{LonLat}; precision::Integer=5, limits::Limits=Limits())::String
    scale = scale_for(precision)
    length(points) > limits.max_points && limit("too_many_points")

    # Pass 1: validate and scale every coordinate before any delta (spec error order).
    for p in points
        scale_value(p.lat, scale)
        scale_value(p.lon, scale)
    end

    # Pass 2: deltas, overflow checks and the exact output length.
    len = 0
    prev_lat, prev_lon = Int64(0), Int64(0)
    for p in points
        lat, lon = scale_value(p.lat, scale), scale_value(p.lon, scale)
        len += encoded_len(checked_delta(lat, prev_lat)) + encoded_len(checked_delta(lon, prev_lon))
        prev_lat, prev_lon = lat, lon
    end

    # Pass 3: write. Nothing can fail past this point.
    out = Vector{UInt8}(undef, len)
    i = 1
    prev_lat, prev_lon = Int64(0), Int64(0)
    for p in points
        lat, lon = scale_value(p.lat, scale), scale_value(p.lon, scale)
        i = write_value!(out, i, lat - prev_lat)
        i = write_value!(out, i, lon - prev_lon)
        prev_lat, prev_lon = lat, lon
    end
    return String(out)
end

"""
    EncodedPolyline.decode(text; precision = 5, limits = Limits()) -> Vector{LonLat}

Spec operation `decode`. Decodes a polyline string into points. `precision`
must match the one used to encode.

Throws `PolylineError` with code `polyline.precision_out_of_range`,
`polyline.text_too_long`, `polyline.invalid_char`, `polyline.truncated`,
`polyline.overflow` or `polyline.too_many_points`. Byte offsets are zero-based.
"""
function decode(text::AbstractString; precision::Integer=5, limits::Limits=Limits())::Vector{LonLat}
    scale = scale_for(precision)
    data = codeunits(String(text))
    n = length(data)
    n > limits.max_text_length && limit("text_too_long")

    points = LonLat[]
    sums = (Int64(0), Int64(0))
    axis = 0
    lat_start = 0
    i = 0                                   # zero-based byte offset
    while i < n
        start = i
        u = UInt64(0)
        chunks = 0
        while true
            i >= n && invalid("truncated", start)
            c = data[i + 1]
            63 <= c <= 126 || invalid("invalid_char", i)
            b = UInt64(c - 63)
            chunks += 1
            chunks > 13 && invalid("overflow", start)
            shift = 5 * (chunks - 1)
            # At shift 60 only 4 bits fit in a UInt64.
            shift == 60 && (b & 0x1f) > 0xf && invalid("overflow", start)
            u |= (b & 0x1f) << shift
            i += 1
            b < 0x20 && break
        end
        half = reinterpret(Int64, u >> 1)
        d = isodd(u) ? ~half : half
        if axis == 0
            total, overflowed = Base.Checked.add_with_overflow(sums[1], d)
            overflowed && invalid("overflow", start)
            sums = (total, sums[2])
            lat_start = start
            axis = 1
        else
            total, overflowed = Base.Checked.add_with_overflow(sums[2], d)
            overflowed && invalid("overflow", start)
            sums = (sums[1], total)
            length(points) + 1 > limits.max_points && limit("too_many_points")
            push!(points, LonLat(Float64(sums[2]) / scale, Float64(sums[1]) / scale))
            axis = 0
        end
    end
    axis == 1 && invalid("truncated", lat_start)
    return points
end

end # module
