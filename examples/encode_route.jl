# Canonical example `encode_route`: encode a three-point route and print the string.
using EncodedPolyline

route = [LonLat(-120.2, 38.5), LonLat(-120.95, 40.7), LonLat(-126.453, 43.252)]
println(EncodedPolyline.encode(route))
