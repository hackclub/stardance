class Admin::Certification::DevlogCommitsController < Admin::Certification::ApplicationController
  def index
    devlog = Post::Devlog.find(params[:devlog_id])
    authorize devlog, :index?, policy_class: Admin::Certification::DevlogCommitsPolicy

    project  = devlog.post.project
    provider = GitHost::Base.for(project.repo_url)
    return render json: { commits: [] } unless provider

    owner = project.memberships.find_by(role: :owner)&.user
    author_emails = [ owner&.email, owner&.guest_email ].compact.uniq

    start_time, end_time = commit_window(devlog, project)

    raw_commits = provider.fetch_commits(since: start_time, before: end_time)

    # Filter to only this user's commits
    commits = author_emails.any? ?
      raw_commits.select { |c| author_emails.include?(c[:author_email]) } :
      raw_commits

    # Fetch per-commit stats (additions/deletions aren't in the list response)
    commits_with_stats = commits.map do |c|
      provider.fetch_commit(c[:sha]) || c
    end

    render json: {
      commits: commits_with_stats.map { |c|
        {
          sha:         c[:sha],
          short_sha:   c[:sha]&.first(7),
          message:     c[:message]&.lines&.first&.strip,
          author_name: c[:author_name],
          authored_at: c[:authored_at],
          additions:   c[:additions] || 0,
          deletions:   c[:deletions] || 0,
          url:         c[:url]
        }
      },
      repo_url: project.repo_url
    }
  end

  private

  def commit_window(devlog, project)
    all_posts = project.posts
      .where(postable_type: "Post::Devlog")
      .joins("INNER JOIN post_devlogs ON post_devlogs.id = posts.postable_id AND post_devlogs.deleted_at IS NULL")
      .order("posts.created_at ASC")

    idx = all_posts.index { |p| p.postable_id == devlog.id }
    return [ project.created_at, Time.current ] if idx.nil?

    is_first = idx == 0
    is_last  = idx == all_posts.size - 1
    this_post = all_posts[idx]

    start_time = if is_first
      prior = project.ship_event_posts
        .where("posts.created_at < ?", this_post.created_at)
        .order("posts.created_at DESC").first
      prior&.created_at || project.created_at
    else
      all_posts[idx - 1].created_at
    end

    end_time = if is_last
      next_ship = project.ship_event_posts
        .where("posts.created_at >= ?", this_post.created_at)
        .order("posts.created_at ASC").first
      next_ship&.created_at || Time.current
    else
      this_post.created_at
    end

    [ start_time, end_time ]
  end
end
