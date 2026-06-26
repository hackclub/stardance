module ExpeditionsHelper
  def expedition_signup_url(expedition)
    query = { expedition: expedition.airtable_id }.to_query
    "https://forms.hackclub.com/stardance-expedition-signup?#{query}"
  end

  def expedition_distance_label(distance_km)
    return nil unless distance_km
    return "< 1 km" if distance_km < 1

    "#{number_with_delimiter(distance_km.round)} km"
  end

  def expedition_map_embed_url(expedition)
    return nil unless expedition.latitude && expedition.longitude

    lat = expedition.latitude.round(5)
    lon = expedition.longitude.round(5)
    bbox = [ lon - 0.01, lat - 0.01, lon + 0.01, lat + 0.01 ].map { |n| n.round(5) }.join(",")
    query = { bbox: bbox, layer: "mapnik", marker: "#{lat},#{lon}" }.to_query

    "https://www.openstreetmap.org/export/embed.html?#{query}"
  end
end
