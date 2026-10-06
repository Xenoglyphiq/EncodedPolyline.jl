# Canonical example `precision_6`: round-trip a route at precision 6 (OSRM, Valhalla).
using EncodedPolyline

route = [LonLat(-73.985713, 40.748441), LonLat(-73.978569, 40.751657), LonLat(-73.968285, 40.785091)]
text = EncodedPolyline.encode(route; precision=6)
back = EncodedPolyline.decode(text; precision=6)

println(text)
for (a, b) in zip(route, back)
    println("($(a.lon), $(a.lat)) -> ($(b.lon), $(b.lat))")
    abs(a.lon - b.lon) <= 1e-6 && abs(a.lat - b.lat) <= 1e-6 || error("round trip mismatch")
end
println("round trip matches")
