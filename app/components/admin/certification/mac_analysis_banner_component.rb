module Admin
  module Certification
    # Pre-screen summary banner for a YSWS review, shown along the top of the
    # review page (see Onboarding::GuestBannerComponent for the banner pattern).
    # The strip carries the verdict; a details drawer expands in place to the
    # signals and the cached evidence behind it.
    #
    # Flag labels are derived from the report data rather than mapped here on
    # purpose: this repo is public, so the flag taxonomy stays out of it. Only
    # `severity` — a neutral four-level scale — drives presentation.
    class MACAnalysisBannerComponent < ViewComponent::Base
      # Signal keys whose value is a percentage already expressed as 0-100.
      PERCENTAGE_KEY_SUFFIX = "_pct".freeze
      # Long list values are truncated in the drawer so one noisy signal (every
      # user-agent string, say) can't push the rest of the report off-screen.
      LIST_PREVIEW_LIMIT = 12
      # Evidence column holding commit SHAs, linked back to the repo host.
      SHA_COLUMN = "sha".freeze
      # Signals the category pie already shows: listing them again beside it only
      # repeats the same numbers in a worse form.
      CHARTED_SIGNAL_KEYS = %w[other_categories].freeze
      # Signals whose entries read "<name> <opaque id>", where one name can
      # contribute dozens of ids. Rendered as collapsed first-word groups so the
      # names are scannable and the ids stay one click away.
      GROUPED_SIGNAL_KEYS = %w[phantom_entities].freeze
      # Signals whose entries are raw wakatime user-agent strings.
      USER_AGENT_SIGNAL_KEYS = %w[editor_agents].freeze
      # Pie geometry. A circumference of exactly 100 lets each slice's dash length be
      # its percentage outright, so no trigonometry is needed. The stroke is the full
      # diameter so slices meet at the centre rather than leaving a donut hole —
      # which means the painted disc reaches PIE_DIAMETER, and the canvas has to be
      # twice PIE_DIAMETER for it not to clip.
      PIE_RADIUS = 15.915
      PIE_DIAMETER = 31.83
      PIE_CENTER = 31.83
      PIE_CANVAS = 63.66
      # Surface gap between adjacent slices, in the same 100-unit terms. Slices
      # thinner than this keep a hairline so a 0.7% category doesn't vanish.
      PIE_GAP = 0.4
      PIE_MIN_SLICE = 0.2
      # User-agent tokens carrying no information about which tools were used: the
      # wakatime CLI, its per-editor plugin, and the Go runtime it was built with.
      # Every entry repeats them, so they only crowd out the part that differs.
      USER_AGENT_NOISE = %r{\A(?:go\d|(?:[\w.-]+-)?wakatime/)}i

      def initialize(analysis:, repo_url: nil, total_minutes: nil)
        @analysis = analysis
        @repo_url = repo_url
        @total_minutes = total_minutes
      end

      def render?
        analysis.present?
      end

      private

        attr_reader :analysis, :repo_url, :total_minutes

        def severity
          analysis.worst_severity
        end

        def banner_classes
          [ "mac-banner", severity && "mac-banner--#{severity}" ].compact.join(" ")
        end

        def chip_classes(flag)
          [ "mac-banner__chip", flag["severity"].presence && "mac-banner__chip--#{flag['severity']}" ]
            .compact.join(" ")
        end

        def flag_label(flag)
          flag["type"].to_s.humanize.presence || "Flag"
        end

        def generated_ago
          return if analysis.generated_at.blank?

          "#{time_ago_in_words(analysis.generated_at)} ago"
        end

        # One signal value, formatted on shape alone. Percent-suffixed keys are
        # the only name-based branch (mirroring the integrity helper), so new
        # signals render sensibly without being enumerated here.
        def format_signal(key, value)
          case value
          when Numeric
            if key.to_s.end_with?(PERCENTAGE_KEY_SUFFIX)
              number_to_percentage(value, precision: 1)
            else
              number_with_delimiter(value)
            end
          when Array
            format_array_signal(key, value)
          when Hash
            format_list(value.map { |name, inner| "#{name}: #{inner}" })
          when true, false
            value ? "yes" : "no"
          else
            value.to_s
          end
        end

        # The recommendation's devlog id as an in-page jump to that devlog's review
        # card (see the anchor on .devlog-item), so a reviewer can go straight from
        # the summary table to the devlog it's about. Stays plain text when the
        # report names no devlog, since there'd be nothing to scroll to.
        def devlog_review_link(devlog_review_id)
          return tag.span("—", class: "mac-banner__placeholder") if devlog_review_id.blank?

          link_to("##{devlog_review_id}", "#devlog-review-#{devlog_review_id}",
            class: "mac-banner__devlog-link")
        end

        # The core signals that get a half-width card of their own: the list-valued
        # ones (editor agents, phantom entities), minus anything the pie already
        # covers. The core scalars aren't shown — the drawer leads with the verdict
        # and the evidence behind it instead of a wall of counts.
        def detail_signals
          @detail_signals ||= analysis.core_signals
            .except(*CHARTED_SIGNAL_KEYS)
            .select { |_key, value| value.is_a?(Array) }
        end

        # The category breakdown's rows as { name:, pct: }, largest share first so
        # the pie reads clockwise from its dominant slice. Falls back to deriving the
        # share from the raw counts when the analyzer didn't include one.
        def category_slices(table)
          rows = table[:rows].grep(Hash)
          total = rows.sum { |row| row["count"].to_f }

          rows.filter_map { |row| category_slice(row, total) }
            .sort_by { |slice| -slice[:pct] }
        end

        def category_slice(row, total)
          pct = row["pct"].is_a?(Numeric) ? row["pct"].to_f : share_of(row["count"], total)
          return if pct <= 0

          { name: row["category"].to_s.presence || "unknown", pct: pct }
        end

        def share_of(count, total)
          total.positive? ? count.to_f / total * 100 : 0
        end

        # The breakdown as a pie: one <circle> per slice, dashed to its share of the
        # 100-unit circumference and rotated to start at twelve o'clock. Colour rides
        # on a per-category class so the mapping stays in the stylesheet.
        def category_pie(slices)
          offset = 0.0
          circles = slices.map do |slice|
            circle = pie_slice(slice, offset)
            offset += slice[:pct]
            circle
          end

          tag.svg(safe_join(circles), class: "mac-banner__pie",
            viewBox: "0 0 #{PIE_CANVAS} #{PIE_CANVAS}", "aria-hidden": true)
        end

        # Each slice is rotated to its own start angle rather than offset along a
        # shared dash pattern: stroke-dashoffset's sign convention isn't reliable
        # across renderers, while a rotate transform is. -90 puts 0% at twelve
        # o'clock, and one percent of the circumference is 3.6 degrees.
        def pie_slice(slice, offset)
          dash = [ slice[:pct] - PIE_GAP, PIE_MIN_SLICE ].max.round(3)

          tag.circle(cx: PIE_CENTER, cy: PIE_CENTER, r: PIE_RADIUS,
            class: "mac-banner__slice #{category_modifier('slice', slice[:name])}",
            "stroke-width": PIE_DIAMETER,
            "stroke-dasharray": "#{dash} #{(100 - dash).round(3)}",
            transform: "rotate(#{(offset * 3.6 - 90).round(3)} #{PIE_CENTER} #{PIE_CENTER})")
        end

        # Identity never rests on colour alone: every slice is named here, with its
        # share as time against the review's total. Doubles as the pie's text
        # alternative, which is why the svg itself is aria-hidden.
        def category_legend(slices)
          items = slices.map do |slice|
            tag.li(safe_join([
              tag.span(nil, class: "mac-banner__swatch #{category_modifier('swatch', slice[:name])}"),
              "#{slice[:name]} — #{format_share(slice[:pct])}"
            ]), class: "mac-banner__legend-item")
          end

          tag.ul(safe_join(items), class: "mac-banner__legend")
        end

        def category_modifier(element, name)
          "mac-banner__#{element}--#{name.parameterize}"
        end

        # The evidence table markup, shared by the Evidence dropdowns and the
        # category breakdown beside the signals. A flat list (no columns, e.g. bare
        # filenames) renders as a list instead.
        def evidence_table_tag(table)
          return format_list(table[:rows]) if table[:columns].empty?

          header = tag.tr(safe_join(table[:columns].map { |column| tag.th(column.to_s.humanize) }))
          rows = table[:rows].map do |row|
            tag.tr(safe_join(table[:columns].map { |column| tag.td(evidence_cell(row, column)) }))
          end

          tag.div(tag.table(safe_join([ tag.thead(header), tag.tbody(safe_join(rows)) ]),
            class: "mac-banner__table"), class: "mac-banner__table-scroll")
        end

        # Array signals differ in how their entries want reading: user agents get
        # reduced to the tools they name, "<name> <opaque id>" lists get grouped by
        # the name, everything else is a flat list.
        def format_array_signal(key, value)
          case key.to_s
          when *USER_AGENT_SIGNAL_KEYS then format_user_agent_list(value)
          when *GROUPED_SIGNAL_KEYS then format_grouped_list(value)
          else format_list(value)
          end
        end

        def format_list(values)
          bounded_list(values.map { |entry| entry.is_a?(Hash) ? format_list_entry(entry) : entry.to_s }) do |entry|
            tag.li(entry, class: "mac-banner__list-item")
          end
        end

        # User agents reduced to the tools they name. Entries that reduce to the
        # same tools collapse into one row, and the raw strings behind a row stay
        # available as its tooltip so nothing is lost from the evidence.
        def format_user_agent_list(values)
          groups = values.map(&:to_s).group_by { |value| simplify_user_agent(value) }

          bounded_list(groups.to_a) do |simplified, raw|
            tag.li(simplified, class: "mac-banner__list-item", title: raw.join("\n"))
          end
        end

        # One raw user-agent string as just its tools, e.g. "OpenCode/1.15.13 ·
        # vscode/1.115.0". The platform triple in parentheses and the boilerplate
        # tokens go; whatever's left is kept verbatim, since the analyzer's own
        # naming is what a reviewer would compare against the raw report. Falls back
        # to the original when stripping leaves nothing, so an unfamiliar format
        # still shows something.
        def simplify_user_agent(value)
          tokens = value.to_s.gsub(/\([^)]*\)/, " ").split
            .reject { |token| token.match?(USER_AGENT_NOISE) }

          tokens.any? ? tokens.join(" · ") : value.to_s
        end

        # Up to LIST_PREVIEW_LIMIT rows plus an overflow count, so the drawer stays
        # scannable when the analyzer emits hundreds of entries. The block turns one
        # entry into its <li>.
        def bounded_list(entries)
          preview = entries.first(LIST_PREVIEW_LIMIT)
          overflow = entries.size - preview.size

          items = preview.map { |entry| yield entry }
          items << tag.li("+#{overflow} more", class: "mac-banner__list-item mac-banner__list-item--overflow") if overflow.positive?
          tag.ul(safe_join(items), class: "mac-banner__list")
        end

        # One hash entry from a list value. The analyzer's "named share" shape — a
        # name plus a percentage — is common enough to read properly, as
        # "building — 0h 10m". Any other shape falls back to a key/value dump so an
        # unrecognised entry still shows every field it carries.
        def format_list_entry(entry)
          name = entry["name"]
          pct = entry["pct"]
          return entry.map { |key, value| "#{key} #{value}" }.join(" ") if name.blank? || !pct.is_a?(Numeric)

          "#{name} — #{format_share(pct)}"
        end

        # A percentage share as the time it works out to against the review's
        # claimed total — a reviewer weighs minutes, not proportions. Falls back to
        # the bare percentage when there's no total to apply it to, rather than
        # showing a duration derived from nothing.
        def format_share(pct)
          return number_to_percentage(pct, precision: 1) if total_minutes.to_i <= 0

          helpers.format_hours_minutes((total_minutes * pct / 100.0).round * 60)
        end

        # A list value grouped by each entry's first word. Entries sharing a first
        # word collapse into one <details> labelled with that word; a word with a
        # single entry stays a plain row, since a dropdown around one line is only
        # a click in the way. Groups are capped like any other list, but a group's
        # own entries aren't — it starts collapsed, so it can't crowd the drawer.
        def format_grouped_list(values)
          groups = values.map(&:to_s).group_by { |entry| entry.split.first.to_s }

          bounded_list(groups.to_a) do |word, entries|
            grouped_list_item(word, entries)
          end
        end

        def grouped_list_item(word, entries)
          return tag.li(entries.first, class: "mac-banner__list-item") if entries.one?

          tag.li(class: "mac-banner__list-item") do
            tag.details(class: "mac-banner__group") do
              safe_join([
                tag.summary(safe_join([ word, " ", tag.span("(#{entries.size})", class: "mac-banner__count") ]),
                  class: "mac-banner__group-toggle"),
                tag.ul(safe_join(entries.map { |entry| tag.li(entry, class: "mac-banner__group-item") }),
                  class: "mac-banner__group-list")
              ])
            end
          end
        end

        # One evidence cell. SHAs become links to the commit on the repo host so a
        # reviewer can open the commit the analyzer cited; anything else is
        # formatted on shape alone. Falls back to plain text when the project has
        # no usable repo URL.
        def evidence_cell(row, column)
          value = row.is_a?(Hash) ? row[column] : row
          url = commit_url(value) if column.to_s == SHA_COLUMN
          return format_cell(value) if url.blank?

          link_to(value, url, class: "mac-banner__sha", target: "_blank", rel: "noopener noreferrer")
        end

        # Web URL for a commit on the project's repo host, built from the repo URL's
        # path shape. No API call, so an abbreviated SHA works and a link costs no
        # request; an unrecognised host just gets the common /commit/<sha> shape.
        def commit_url(sha)
          return if repo_url.blank? || sha.blank?

          base = repo_url.sub(/\.git$/, "")

          if base.include?("gitlab")
            "#{base}/-/commit/#{sha}"
          elsif base.include?("bitbucket")
            "#{base}/commits/#{sha}"
          else
            "#{base}/commit/#{sha}"
          end
        end

        def format_cell(value)
          case value
          when nil then tag.span("—", class: "mac-banner__placeholder")
          when Numeric then number_with_delimiter(value)
          when true, false then value ? "yes" : "no"
          when Array, Hash then value.to_json
          else value.to_s
          end
        end

        def minutes_delta(recommendation)
          original = recommendation["original_minutes"].to_i
          recommended = recommendation["recommended_minutes"].to_i
          helpers.number_with_sign(recommended - original)
        end

        def format_minutes(minutes)
          return tag.span("—", class: "mac-banner__placeholder") if minutes.blank?

          "#{number_with_delimiter(minutes.to_i)} min (#{helpers.format_minutes_as_time(minutes.to_i)})"
        end
    end
  end
end
