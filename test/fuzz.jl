# Mutation fuzzer for `decode` (no dependencies beyond the test env).
# Runs from runtests.jl only when FUZZ_SECONDS is set:
#   FUZZ_SECONDS=600 julia --project -e 'using Pkg; Pkg.test()'
# FUZZ_SEED fixes the seed; otherwise it's time-based and printed.
#
# Corpus: every decode input in the manifest plus random strings. Each
# iteration applies 1–4 mutations and checks:
#   - only PolylineError escapes `decode`, and it always has a code;
#   - accepted input re-encodes, or fails only with polyline.overflow.

using Random
using JSON3
using EncodedPolyline: EncodedPolyline, PolylineError

function fuzz_corpus(rng)
    manifest = JSON3.read(read(DEFAULT_MANIFEST, String))
    corpus = Vector{UInt8}[Vector{UInt8}(codeunits(String(c["input"]["value"])))
                           for c in manifest["cases"] if c["op"] == "decode"]
    for _ in 1:8
        push!(corpus, rand(rng, UInt8(63):UInt8(126), rand(rng, 0:40)))
    end
    return corpus
end

function mutate!(rng, s::Vector{UInt8})
    for _ in 1:rand(rng, 1:4)
        op = rand(rng, 1:6)
        if op == 1 && !isempty(s)                      # flip a byte
            i = rand(rng, eachindex(s)); s[i] ⊻= rand(rng, UInt8(1):UInt8(255))
        elseif op == 2                                  # insert a byte
            b = rand(rng) < 0.5 ? rand(rng, UInt8(63):UInt8(126)) : rand(rng, UInt8)
            insert!(s, rand(rng, 1:length(s)+1), b)
        elseif op == 3 && !isempty(s)                   # delete a byte
            deleteat!(s, rand(rng, eachindex(s)))
        elseif op == 4 && !isempty(s)                   # duplicate a slice
            a = rand(rng, eachindex(s)); b = rand(rng, a:min(lastindex(s), a + 16))
            append!(s, s[a:b])
        elseif op == 5 && !isempty(s)                   # truncate
            resize!(s, rand(rng, 0:length(s)-1))
        else                                            # long continuation run
            append!(s, fill(UInt8('~'), rand(rng, 1:16)))
        end
        length(s) > 512 && resize!(s, 512)
    end
    return s
end

function fuzz(seconds::Float64, seed::UInt64)
    rng = Xoshiro(seed)
    corpus = fuzz_corpus(rng)
    println("fuzz: seed $seed, $(seconds) s, corpus $(length(corpus))")
    deadline = time() + seconds
    iterations = 0
    while time() < deadline
        input = mutate!(rng, copy(rand(rng, corpus)))
        text = String(copy(input))
        iterations += 1
        points = try
            EncodedPolyline.decode(text)
        catch e
            if !(e isa PolylineError) || isempty(e.code)
                println("FUZZ FAILURE (decode) on ", repr(text)); rethrow()
            end
            continue
        end
        try
            EncodedPolyline.encode(points)
        catch e
            if !(e isa PolylineError && e.code == "polyline.overflow")
                println("FUZZ FAILURE (re-encode) on ", repr(text)); rethrow()
            end
        end
    end
    println("fuzz: $iterations iterations in $(round(seconds; digits=1)) s, clean")
    return iterations
end
