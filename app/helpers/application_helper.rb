module ApplicationHelper
  def in_beta? = request.host.include?("beta")

  def main_app_base_url
    host = request.host.sub(/\Araffle\./, "")
    port = request.port
    scheme = request.scheme
    port_suffix = [ 80, 443 ].include?(port) ? "" : ":#{port}"
    "#{scheme}://#{host}#{port_suffix}"
  end

  def raffle_base_url
    host = request.host.sub(/\Araffle\./, "")
    port = request.port
    scheme = request.scheme
    port_suffix = [ 80, 443 ].include?(port) ? "" : ":#{port}"
    "#{scheme}://raffle.#{host}#{port_suffix}"
  end

  def stardust_icon(extra_class: nil)
    image_tag "icons/stardust.png", alt: "Stardust", class: [ "currency-icon", extra_class ].compact.join(" ")
  end

  def hack_club_auth_path(login_hint: nil)
    if login_hint.present?
      "/auth/hack_club?login_hint=#{CGI.escape(login_hint.to_s)}"
    else
      "/auth/hack_club"
    end
  end

  def onboarding_count_up(n)
    content_tag(:span, number_with_delimiter(n),
      class: "onboarding-counter",
      data: { controller: "count-up", count_up_target_value: n })
  end

  def admin_tool(&block)
    if current_user&.admin?
      content_tag(:div, class: "admin tools-do", &block)
    end
  end

  def sign(num)
    # 1 => "+"
    # -1 => "-"
    # 0 => ""

    case (num <=> 0)
    when 1
      "+"
    when -1
      "-"
    else
      ""
    end
  end

  def number_with_sign(num)
    sign(num) + num.abs.to_s
  end

  def format_minutes_as_time(minutes)
    return "0:00" if minutes.nil? || minutes <= 0

    hours = minutes / 60
    mins = minutes % 60
    format("%d:%02d", hours, mins)
  end

  def format_seconds(seconds, include_days: false)
    # ie: 2h 3m 4s
    # ie. 37h 15m (if include_days is false)
    # ie. 1d 13h 15m (if include_days is true)
    return "0s" if seconds.nil? || seconds <= 0

    days = seconds / 86400
    hours = include_days ? (seconds % 86400) / 3600 : seconds / 3600
    minutes = (seconds % 3600) / 60
    secs = seconds % 60

    parts = []
    parts << "#{days}d" if include_days && days > 0
    parts << "#{hours}h" if hours > 0 || parts.any?
    parts << "#{minutes}m" if minutes > 0 || parts.any?
    parts << "#{secs}s" if secs > 0

    parts.join(" ")
  end

  def dev_tool(&block)
    if Rails.env.development?
      content_tag(:div, class: "dev tools-do", &block)
    end
  end
  def random_carousel_transform
    "rotate(#{rand(-3..3)}deg) scale(#{(rand(97..103).to_f / 100).round(2)}) translateY(#{rand(-8..8)}px)"
  end

  def back_path(fallback = home_path)
    pages = session[:previous_pages]
    return fallback if pages.blank? || pages.size < 2

    pages[-2]
  end

  def safe_external_url(url)
    return nil if url.blank?

    uri = URI.parse(url)
    uri.scheme&.downcase.in?(%w[http https]) ? url : nil
  rescue URI::InvalidURIError
    nil
  end

  def achievement_icon(icon_name, earned: true, **options)
    asset_path = find_achievement_asset(icon_name)

    if earned
      if asset_path
        if asset_path.end_with?(".svg")
          inline_svg_tag(asset_path, **options)
        else
          image_tag(asset_path, **options)
        end
      else
        content_tag(:span, "?", class: "achievement-icon-placeholder", **options)
      end
    else
      silhouette_path = AchievementSilhouettes.silhouette_path(icon_name)

      if silhouette_path && achievement_asset_exists?(silhouette_path)
        if silhouette_path.end_with?(".svg")
          inline_svg_tag(silhouette_path, **options)
        else
          image_tag(silhouette_path, **options)
        end
      elsif asset_path
        silhouette_style = "filter: brightness(0) opacity(0.4)"
        merged_style = options[:style] ? "#{options[:style]}; #{silhouette_style}" : silhouette_style
        if asset_path.end_with?(".svg")
          inline_svg_tag(asset_path, **options.merge(style: merged_style))
        else
          image_tag(asset_path, **options.merge(style: merged_style))
        end
      else
        content_tag(:span, "?", class: "achievement-icon-placeholder", style: "filter: brightness(0) opacity(0.4)", **options)
      end
    end
  end


  def cache_stats
    hits = Thread.current[:cache_hits] || 0
    misses = Thread.current[:cache_misses] || 0
    { hits: hits, misses: misses }
  end

  def requests_per_second
    rps = RequestCounter.per_second
    rps == :high_load ? "lots of req/sec" : "#{rps} req/sec"
  end

  def active_users_stats
    counts = ActiveUserTracker.counts
    "#{counts[:signed_in]} signed in, #{counts[:anonymous]} visitors"
  end

  private

  def find_achievement_asset(icon_name)
    @achievement_asset_cache ||= {}
    return @achievement_asset_cache[icon_name] if @achievement_asset_cache.key?(icon_name)

    @achievement_asset_cache[icon_name] = %w[achievements icons].product(%w[png svg jpg jpeg gif webp]).each do |folder, ext|
      path = "#{folder}/#{icon_name}.#{ext}"
      break path if achievement_asset_exists?(path)
    end.then { |result| result.is_a?(String) ? result : nil }
  end

  def achievement_asset_exists?(path)
    # In production, check the asset pipeline (Propshaft) for digested assets
    if Rails.application.assets
      Rails.application.assets.load_path.find(path).present?
    else
      # Fallback to filesystem check for development
      File.exist?(Rails.root.join("app/assets/images", path)) ||
        File.exist?(Rails.root.join("secrets/assets/images", path))
    end
  end
end
