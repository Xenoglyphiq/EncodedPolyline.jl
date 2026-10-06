# Canonical example `decode_route`: decode Google's example and print each point.
using EncodedPolyline

points = try
    EncodedPolyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
catch e
    e isa PolylineError && println(stderr, sprint(showerror, e))
    rethrow()
end
for p in points
    println("lon $(p.lon), lat $(p.lat)")
end
