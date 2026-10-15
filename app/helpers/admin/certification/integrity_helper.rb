module Admin::Certification::IntegrityHelper
  # Coordinate space of the treemap SVG (scaled to 100% width via CSS).
  TREEMAP_WIDTH = 600
  TREEMAP_HEIGHT = 340
  # Default treemap/long-tail cutoff, relative to the biggest file: any file
  # whose share is at least this fraction of the top file's share gets its own
  # cell; smaller ones are listed horizontally underneath. Reviewers can override
  # it per-request via the ?treemap_cutoff= query param (see the controls form).
  TREEMAP_CUTOFF_RATIO = 0.1
  # Number of cell colours defined in the SCSS (fills cycle through these).
  TREEMAP_PALETTE_SIZE = 6

  # Translates the codenamed fraud_detection_data blob back into human-readable
  # rows for the review page. The name → codename map (and therefore the labels)
  # lives only in the secrets submodule (Certification::Fraud::FraudDetectionData),
  # so this returns an empty hash when secrets isn't loaded — the public repo
  # never carries the signal names itself.
  def integrity_signal_rows(review)
    return {} unless defined?(::Certification::Fraud::FraudDetectionData)

    ::Certification::Fraud::FraudDetectionData
      .unpack(review.fraud_detection_data)
      .reject { |_name, value| value.nil? }
  end

  # Renders one signal value. Formatting branches on the value's shape and a
  # generic "percentage" name prefix only — it never spells out a signal name.
  def format_integrity_signal(name, value)
    return tag.span("—", class: "integrity-review__placeholder") if value.blank?

    case value
    when Hash
      # A map of entity => share of heartbeats — visualised as a treemap.
      integrity_heartbeat_treemap(value)
    when Numeric
      if name.to_s.start_with?("percentage")
        number_to_percentage(value * 100, precision: 1)
      else
        number_with_precision(value, precision: 3, strip_insignificant_zeros: true)
      end
    else
      value.to_s
    end
  end

  # Builds a treemap for an entity => share hash: cells sized by share for the
  # major files (share >= TREEMAP_CUTOFF_RATIO of the top file's share), with the
  # long tail listed horizontally beneath.
  def integrity_heartbeat_treemap(files)
    files = files.to_h.transform_values(&:to_f).reject { |_name, share| share <= 0 }
    return tag.span("—", class: "integrity-review__placeholder") if files.empty?

    ratio = integrity_treemap_cutoff_ratio
    sorted = files.sort_by { |_name, share| -share }
    cutoff = sorted.first.last * ratio
    major = sorted.select { |_name, share| share >= cutoff }
    minor = sorted.select { |_name, share| share < cutoff }

    parts = [ integrity_treemap_controls(ratio) ]
    parts << integrity_treemap_svg(major) if major.any?
    parts << integrity_treemap_minor(minor, cutoff) if minor.any?
    tag.div(safe_join(parts), class: "integrity-review__treemap")
  end

  private

  # Effective cutoff ratio for this request: the ?treemap_cutoff= query param
  # (a percentage of the top file's share) when present and valid, otherwise the
  # TREEMAP_CUTOFF_RATIO default. Clamped so it can't hide every cell.
  def integrity_treemap_cutoff_ratio
    raw = params[:treemap_cutoff]
    return TREEMAP_CUTOFF_RATIO if raw.blank?

    (raw.to_f / 100).clamp(0.01, 1.0)
  end

  # A GET form letting the reviewer retune the cutoff (as a % of the top file).
  # Submits back to the same review page with the chosen ?treemap_cutoff=.
  def integrity_treemap_controls(ratio)
    percent = number_with_precision(ratio * 100, precision: 1, strip_insignificant_zeros: true)

    tag.form(method: "get", class: "integrity-review__treemap-controls") do
      safe_join([
        tag.label("Long-tail cutoff", for: "treemap_cutoff",
                  class: "integrity-review__treemap-controls-label"),
        tag.input(type: "number", name: "treemap_cutoff", id: "treemap_cutoff",
                  value: percent, min: 1, max: 100, step: 0.5,
                  class: "integrity-review__treemap-controls-input"),
        tag.span("% of top file", class: "integrity-review__treemap-controls-suffix"),
        tag.button("Apply", type: "submit", class: "integrity-review__treemap-controls-btn")
      ])
    end
  end

  def integrity_treemap_svg(items)
    cells = integrity_treemap_layout(items, TREEMAP_WIDTH, TREEMAP_HEIGHT)
      .each_with_index
      .map { |rect, index| integrity_treemap_cell(rect, index) }

    tag.svg(
      safe_join(cells),
      class: "integrity-review__treemap-svg",
      viewBox: "0 0 #{TREEMAP_WIDTH} #{TREEMAP_HEIGHT}",
      role: "img",
      "aria-label": "Heartbeat share by file"
    )
  end

  def integrity_treemap_cell(rect, index)
    x = rect[:x].round(2)
    y = rect[:y].round(2)
    w = rect[:w].round(2)
    h = rect[:h].round(2)
    pct = number_to_percentage(rect[:share] * 100, precision: 1)
    palette = "integrity-review__treemap-rect--#{index % TREEMAP_PALETTE_SIZE}"

    nodes = [
      tag.title("#{rect[:name]} — #{pct}"),
      tag.rect(x: x, y: y, width: w, height: h, rx: 4,
               class: "integrity-review__treemap-rect #{palette}")
    ]

    # A cell noticeably taller than it is wide is "too thin" for horizontal
    # text, so the label is rotated to run vertically; otherwise it's labelled
    # horizontally. Cells too small for either rely on the <title> tooltip,
    # which always carries the full name + share.
    if h > w * 1.3 && h >= 50 && w >= 16
      cx = (x + w / 2.0).round(2)
      cy = (y + h / 2.0).round(2)
      nodes << tag.text(treemap_truncate(rect[:name], h - 16), x: cx, y: cy,
                        transform: "rotate(-90 #{cx} #{cy})",
                        "text-anchor": "middle", "dominant-baseline": "central",
                        class: "integrity-review__treemap-label")
    elsif w >= 70 && h >= 26
      nodes << tag.text(treemap_truncate(rect[:name], w - 16), x: x + 8, y: y + 20,
                        class: "integrity-review__treemap-label")
      nodes << tag.text(pct, x: x + 8, y: y + 38, class: "integrity-review__treemap-pct") if h >= 44
    end

    tag.g(safe_join(nodes), class: "integrity-review__treemap-cell")
  end

  # Truncates a label to roughly the pixel budget available (≈8.2px per glyph
  # at the treemap's font size), adding an ellipsis when it doesn't fit.
  def treemap_truncate(name, budget_px)
    max_chars = (budget_px / 8.2).floor
    return name if max_chars >= name.length

    "#{name[0, [ max_chars - 1, 1 ].max]}…"
  end

  def integrity_treemap_minor(items, cutoff)
    chips = items.map do |name, share|
      tag.span("#{name} #{number_to_percentage(share * 100, precision: 1)}",
               class: "integrity-review__treemap-minor-item")
    end

    label = "Under #{number_to_percentage(cutoff * 100, precision: 1)}"
    tag.div(
      safe_join([ tag.span(label, class: "integrity-review__treemap-minor-label"), *chips ]),
      class: "integrity-review__treemap-minor"
    )
  end

  # Squarified treemap (Bruls, Huizing & van Wijk): lays each item out as a
  # rectangle whose area is proportional to its share, keeping aspect ratios
  # near 1. Returns [{ name:, share:, x:, y:, w:, h: }, ...] filling width×height.
  def integrity_treemap_layout(items, width, height)
    total = items.sum { |_name, share| share }
    return [] if total <= 0

    scale = (width.to_f * height) / total
    remaining = items.map { |name, share| { name: name, share: share, area: share * scale } }

    rects = []
    x = 0.0
    y = 0.0
    w = width.to_f
    h = height.to_f

    until remaining.empty?
      side = [ w, h ].min
      row = []
      # Grow the row while it keeps (or improves) the worst aspect ratio.
      until remaining.empty?
        candidate = row + [ remaining.first ]
        break if row.any? && treemap_worst_ratio(candidate, side) > treemap_worst_ratio(row, side)

        row << remaining.shift
      end

      row_area = row.sum { |item| item[:area] }
      if w >= h
        row_w = row_area / h
        cursor = y
        row.each do |item|
          cell_h = item[:area] / row_w
          rects << item.merge(x: x, y: cursor, w: row_w, h: cell_h)
          cursor += cell_h
        end
        x += row_w
        w -= row_w
      else
        row_h = row_area / w
        cursor = x
        row.each do |item|
          cell_w = item[:area] / row_h
          rects << item.merge(x: cursor, y: y, w: cell_w, h: row_h)
          cursor += cell_w
        end
        y += row_h
        h -= row_h
      end
    end

    rects
  end

  def treemap_worst_ratio(row, side)
    sum = row.sum { |item| item[:area] }
    return Float::INFINITY if sum <= 0 || side <= 0

    areas = row.map { |item| item[:area] }
    side_sq = side * side
    sum_sq = sum * sum
    [ (side_sq * areas.max) / sum_sq, sum_sq / (side_sq * areas.min) ].max
  end
end
