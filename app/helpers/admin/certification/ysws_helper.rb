module Admin::Certification::YswsHelper
  REVIEW_STATUS_LABELS = {
    in_unified_db: "in unified DB",
    returned: "returned",
    approved: "approved",
    rejected: "rejected",
    pending: "pending"
  }.freeze

  def review_status_badge(review)
    status = review.review_status
    tag.span(
      REVIEW_STATUS_LABELS.fetch(status),
      class: "status-badge status-#{status.to_s.dasherize}"
    )
  end

  # Queue header link that toggles the sort direction for a column. First click
  # sorts descending (highest first); clicking the active column again flips it.
  # Every other piece of queue state rides along so sorting doesn't silently drop
  # the caller's filters or their active search.
  def ysws_sort_link(column, label)
    active   = @sort == column
    next_dir = (active && @dir == "desc") ? "asc" : "desc"
    arrow    = active ? (@dir == "asc" ? "▲" : "▼") : "▾"

    link_to admin_certification_ysws_reviews_path(project_type: @project_type, sort: column,
                                                  dir: next_dir, search: @search.presence,
                                                  with_integrity: @with_integrity ? nil : "0"),
            class: [ "ysws-queue__sort", ("ysws-queue__sort--active" if active) ] do
      safe_join([ label, tag.span(arrow, class: "ysws-queue__sort-arrow", aria: { hidden: true }) ], " ")
    end
  end

  # The devlog pre-screen hint borrows the banner's severity tones: a suggested
  # time cut reads the same as a yellow banner flag, while a recommendation with
  # nothing to compare against stays neutral blue. The "deduction" key is set by
  # Certification::MACAnalysis#recommendation_for.
  def mac_hint_classes(recommendation)
    [ "mac-hint", "mac-hint--aside", ("mac-hint--deduction" if recommendation["deduction"]) ]
      .compact.join(" ")
  end

  def parse_repo_info(repo_url)
    return nil if repo_url.blank?

    git_host = GitHost::Base.for(repo_url)
    return nil unless git_host

    username = git_host.owner || extract_username_from_url(repo_url)
    return nil if username.blank?

    {
      platform: git_host.provider_name,
      platform_name: git_host.provider_display_name,
      username: username,
      icon: git_host.provider_name
    }
  end

  def fetch_platform_contributions(platform, username, contribution_data = nil)
    return nil if platform.blank? || username.blank?

    result = contribution_data || ::Certification::YswsService.fetch_contributions(platform, username)

    if result[:error]
      case result[:error]
      when :org_repo
        "org repo"
      else
        nil
      end
    elsif result[:total]
      pluralize(result[:total], "contribution")
    else
      nil
    end
  end

  def fetch_contribution_count(platform, username, contribution_data = nil)
    return nil if platform.blank? || username.blank?

    result = contribution_data || ::Certification::YswsService.fetch_contributions(platform, username)

    if result[:error]
      nil
    elsif result[:total]
      result[:total]
    else
      nil
    end
  end

  def fetch_platform_contribution_data(platform, username)
    return nil if platform.blank? || username.blank?

    result = ::Certification::YswsService.fetch_contributions(platform, username)

    if result[:error]
      nil
    elsif result[:contributions] && result[:total]
      {
        contributions: result[:contributions],
        total: result[:total]
      }
    else
      nil
    end
  end

  def prepare_contribution_calendar_data(platform, username, contribution_data = nil)
    return nil if platform.blank? || username.blank?

    result = contribution_data || ::Certification::YswsService.fetch_contributions(platform, username)
    return nil if result[:error] || result[:contributions].blank?

    contribution_map = result[:contributions].each_with_object({}) do |day, hash|
      hash[day["date"]] = day["count"]
    end

    today = Date.current
    one_year_ago = today - 364
    start_date = one_year_ago - one_year_ago.wday

    days = []
    current_date = start_date
    week_index = 0
    day_index = 0

    while current_date <= today || day_index % 7 != 0
      date_str = current_date.to_s
      count = contribution_map[date_str] || 0
      day_of_week = current_date.wday

      if current_date >= one_year_ago && current_date <= today
        days << {
          date: date_str,
          count: count,
          level: calculate_contribution_level(count),
          day_of_week: day_of_week,
          week_index: week_index
        }
      elsif current_date > today
        days << {
          date: date_str,
          count: 0,
          level: 0,
          day_of_week: day_of_week,
          week_index: week_index,
          future: true
        }
      end

      current_date += 1
      day_index += 1
      week_index = day_index / 7
    end

    days
  end

  def platform_profile_url(platform, username)
    return nil if platform.blank? || username.blank?

    case platform
    when "github"
      "https://github.com/#{username}"
    when "gitlab.com"
      "https://gitlab.com/#{username}"
    when "codeberg.org"
      "https://codeberg.org/#{username}"
    when "bitbucket.org"
      "https://bitbucket.org/#{username}"
    when "git.sr.ht", "sr.ht"
      username_with_tilde = username.start_with?("~") ? username : "~#{username}"
      "https://sr.ht/#{username_with_tilde}"
    else
      "https://#{platform}/#{username}"
    end
  end

  def contribution_skill_level(contribution_count)
    return nil if contribution_count.nil?

    if contribution_count < 500
      { label: "Beginner", class: "level-beginner" }
    elsif contribution_count < 1000
      { label: "Intermediate", class: "level-intermediate" }
    else
      { label: "Advanced", class: "level-advanced" }
    end
  end

  private

  def extract_username_from_url(repo_url)
    uri = URI.parse(repo_url)
    path_parts = uri.path.to_s.sub(/^\//, "").split("/")
    path_parts.first
  rescue URI::InvalidURIError
    nil
  end

  def calculate_contribution_level(count)
    return 0 if count == 0
    return 1 if count < 10
    return 2 if count < 20
    return 3 if count < 25
    return 4 if count < 30
    5
  end
end
