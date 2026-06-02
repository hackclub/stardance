class DevlogCreator
  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(project:, user:, body:, attachments:, duration_seconds: nil, snapshot: nil)
    @project = project
    @user = user
    @body = body
    @attachments = Array(attachments).reject(&:blank?)
    @duration_seconds = duration_seconds
    @snapshot = snapshot
  end

  def call
    devlog = Post::Devlog.new(body: @body)
    devlog.attachments.attach(@attachments) if @attachments.present?
    devlog.duration_seconds = @duration_seconds || hackatime_duration_seconds
    devlog.hackatime_projects_key_snapshot = @snapshot || @project.hackatime_keys.join(",")

    if devlog.save
      Post.create!(project: @project, user: @user, postable: devlog)
    end

    devlog
  end

  private

  def hackatime_duration_seconds
    @project.reload
    result = @user.try_sync_hackatime_data!
    return 0 unless result

    project_times = result[:projects] || {}
    total_seconds = @project.hackatime_keys.sum { |key| project_times[key].to_i }
    [ total_seconds - @project.duration_seconds, 0 ].max
  end
end
