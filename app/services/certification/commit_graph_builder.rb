require "cgi"

module Certification
  class CommitGraphBuilder
    ADDS_COLOR  = "#22c55e"
    DELS_COLOR  = "#ef4444"
    MUTED_COLOR = "#888888"
    AXIS_COLOR  = "#3a3a3a"
    DOT_R       = 5

    # Overall SVG canvas
    W  = 600
    H  = 155
    MT = 18   # top margin: space for meta row
    MR = 20
    MB = 35   # bottom margin: space for SHA labels
    ML = 48   # left margin: space for Y-axis labels

    def initialize(commits)
      @commits = Array(commits).sort_by { |c| c[:authored_at] || Time.at(0) }
    end

    def svg
      result = if @commits.empty?
        empty_svg
      elsif @commits.one?
        single_svg
      else
        multi_svg
      end
      result.html_safe
    end

    private

    def cw = W - ML - MR   # chart width  = 532
    def ch = H - MT - MB   # chart height = 102

    # X position (within chart group) for commit at index i.
    # DOT_R padding keeps dots from hitting the chart edges.
    def x_pos(i)
      n = @commits.size - 1
      n.zero? ? cw / 2.0 : DOT_R + i.to_f / n * (cw - 2 * DOT_R)
    end

    def y_max
      @y_max ||= [
        @commits.flat_map { |c| [ c[:additions].to_i, c[:deletions].to_i ] }.max || 0,
        1
      ].max
    end

    # Y position (within chart group). DOT_R padding keeps dots off the edges.
    def y_pos(val)
      ch - DOT_R - val.to_f / y_max * (ch - 2 * DOT_R)
    end

    STYLE = <<~CSS.freeze
      <style>
        .commit-graph a text { cursor: pointer; }
        .commit-graph a:hover text { text-decoration: underline; }
      </style>
    CSS

    def esc(text) = CGI.escapeHTML(text.to_s)

    def truncate_msg(message)
      msg = message.to_s.lines.first.to_s.strip
      msg.length > 50 ? "#{msg[0, 50]}…" : msg
    end

    def commit_tooltip(c)
      short  = c[:sha]&.first(7) || "?"
      adds   = c[:additions].to_i
      dels   = c[:deletions].to_i
      ts     = c[:authored_at]&.strftime("%Y-%m-%d %H:%M") || "unknown time"
      author = c[:author_name].to_s.presence || "unknown author"
      msg    = truncate_msg(c[:message])
      esc("#{short}\n+#{adds} / -#{dels}\n#{ts}\n#{author}\n#{msg}")
    end

    def empty_svg
      <<~SVG
        <svg viewBox="0 0 200 24" width="100%" style="overflow:visible" class="commit-graph">
          <text x="0" y="16" fill="#{MUTED_COLOR}" font-size="11" font-family="monospace">no commits in window</text>
        </svg>
      SVG
    end

    def single_svg
      c     = @commits.first
      short = esc(c[:sha]&.first(7) || "?")
      adds  = c[:additions].to_i
      dels  = c[:deletions].to_i
      msg   = esc(truncate_msg(c[:message]))
      url   = c[:url]

      sha_text = %(<text x="100" y="60" text-anchor="middle" fill="#{ADDS_COLOR}" font-size="12" font-family="monospace">#{short}</text>)
      sha_el   = url ? %(<a href="#{esc(url)}" target="_blank" rel="noopener noreferrer">#{sha_text}</a>) : sha_text

      <<~SVG
        <svg viewBox="0 0 200 88" width="100%" style="overflow:visible" class="commit-graph">
          #{STYLE}
          <text x="0"  y="12" fill="#{ADDS_COLOR}"  font-size="11" font-family="monospace">+#{adds}</text>
          <text x="40" y="12" fill="#{DELS_COLOR}"  font-size="11" font-family="monospace">-#{dels}</text>
          <text x="80" y="12" fill="#{MUTED_COLOR}" font-size="11" font-family="monospace">1 commit</text>
          <rect x="1" y="18" width="198" height="52" rx="4" fill="none" stroke="#{AXIS_COLOR}" stroke-width="1"><title>#{commit_tooltip(@commits.first)}</title></rect>
          #{sha_el}
          <text x="100" y="80" text-anchor="middle" fill="#{MUTED_COLOR}" font-size="9" font-family="monospace">#{msg}</text>
        </svg>
      SVG
    end

    def multi_svg
      total_adds = @commits.sum { |c| c[:additions].to_i }
      total_dels = @commits.sum { |c| c[:deletions].to_i }
      n          = @commits.size
      rotate     = n > 8

      buf = []
      buf << %(<svg viewBox="0 0 #{W} #{H}" width="100%" style="overflow:visible" class="commit-graph">)
      buf << STYLE

      # Meta row
      buf << %(<text x="0"  y="13" fill="#{ADDS_COLOR}"  font-size="11" font-family="monospace">+#{total_adds}</text>)
      buf << %(<text x="48" y="13" fill="#{DELS_COLOR}"  font-size="11" font-family="monospace">-#{total_dels}</text>)
      buf << %(<text x="96" y="13" fill="#{MUTED_COLOR}" font-size="11" font-family="monospace">#{n} commits</text>)

      # Chart group: origin at (ML, MT)
      buf << %(<g transform="translate(#{ML},#{MT})">)

      # Y-axis ticks at 0%, 33%, 67%, 100% of y_max
      [ 0.0, 0.33, 0.67, 1.0 ].each do |frac|
        val = (y_max * frac).round
        yp  = y_pos(val).round(1)
        buf << %(<text x="-5" y="#{(yp + 3.5).round(1)}" text-anchor="end" fill="#{MUTED_COLOR}" font-size="9" font-family="monospace">#{val}</text>)
        buf << %(<line x1="0" y1="#{yp}" x2="#{cw}" y2="#{yp}" stroke="#{AXIS_COLOR}" stroke-width="0.5" stroke-dasharray="3,3"/>)
      end

      # Dots — one green (adds) and one red (dels) per commit
      @commits.each_with_index do |c, i|
        xp   = x_pos(i).round(1)
        adds = c[:additions].to_i
        dels = c[:deletions].to_i

        tooltip = commit_tooltip(c)
        buf << %(<circle cx="#{xp}" cy="#{y_pos(adds).round(1)}" r="#{DOT_R}" fill="#{ADDS_COLOR}"><title>#{tooltip}</title></circle>)
        buf << %(<circle cx="#{xp}" cy="#{y_pos(dels).round(1)}" r="#{DOT_R}" fill="#{DELS_COLOR}"><title>#{tooltip}</title></circle>)
      end

      buf << %(</g>)

      # X-axis SHA labels (in SVG root coordinates, below the chart group)
      label_y = MT + ch + 14
      @commits.each_with_index do |c, i|
        xp    = (ML + x_pos(i)).round(1)
        short = esc(c[:sha]&.first(7) || "?")
        url   = c[:url]

        text_el = if rotate
          %(<text x="#{xp}" y="#{label_y}" text-anchor="end" transform="rotate(-45,#{xp},#{label_y})" fill="#{ADDS_COLOR}" font-size="8" font-family="monospace">#{short}</text>)
        else
          %(<text x="#{xp}" y="#{label_y}" text-anchor="middle" fill="#{ADDS_COLOR}" font-size="10" font-family="monospace">#{short}</text>)
        end

        buf << (url ? %(<a href="#{esc(url)}" target="_blank" rel="noopener noreferrer">#{text_el}</a>) : text_el)
      end

      buf << %(</svg>)
      buf.join("\n")
    end
  end
end
