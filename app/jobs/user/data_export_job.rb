require "zip"

class User::DataExportJob < ApplicationJob
  queue_as :latency_5m

  def perform(data_export_id)
    @data_export = User::DataExport.find_by(id: data_export_id)
    return unless @data_export

    temp_zip = nil

    begin
      @data_export.update!(status: "processing")

      user = @data_export.user
      zip_filename = "stardance-export-#{user.display_name.parameterize}-#{Time.current.strftime("%Y%m%d%H%M%S")}.zip"

      temp_zip = Tempfile.new([ "stardance_export", ".zip" ])

      Zip::OutputStream.open(temp_zip.path) do |zip|
        write_profile(zip, user)
        write_projects(zip, user)
        write_readme(zip, user)
      end

      # Upload synchronously before entering a transaction.
      blob = ActiveStorage::Blob.create_and_upload!(
        io: File.open(temp_zip.path),
        filename: zip_filename,
        content_type: "application/zip"
      )

      @data_export.with_lock do
        # The user may delete an export while it is being generated.
        return unless @data_export.processing?

        @data_export.zip_file.attach(blob)
        @data_export.update!(status: "completed", zip_filename: zip_filename)
      end
    rescue ActiveRecord::RecordNotFound
      # The user deleted the export while it was being generated.
      nil
    rescue StandardError => e
      User::DataExport.where(id: @data_export.id).update_all(
        status: "failed",
        error_message: "#{e.class}: #{e.message}",
        updated_at: Time.current
      )
      raise
    ensure
      temp_zip&.close
      temp_zip&.unlink
    end
  end

  private

  def write_profile(zip, user)
    profile_data = {
      id: user.id,
      display_name: user.display_name,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      bio: user.bio,
      created_at: user.created_at,
      updated_at: user.updated_at
    }

    zip.put_next_entry("profile.json")
    zip.write(JSON.pretty_generate(profile_data))
  end

  def write_projects(zip, user)
    user.projects.includes(:devlogs).find_each do |project|
      safe_title = project.title.parameterize.presence || "project"
      # ID suffix keeps directories unique when two projects share a title
      project_dir = "projects/#{safe_title}-#{project.id}"

      project_data = {
        id: project.id,
        title: project.title,
        description: project.description,
        demo_url: project.demo_url,
        repo_url: project.repo_url,
        readme_url: project.readme_url,
        ship_status: project.ship_status,
        shipped_at: project.shipped_at,
        created_at: project.created_at,
        updated_at: project.updated_at
      }

      zip.put_next_entry("#{project_dir}/project.json")
      zip.write(JSON.pretty_generate(project_data))

      download_attachment(zip, project.banner, "#{project_dir}/banner") if project.banner.attached?
      download_attachment(zip, project.demo_video, "#{project_dir}/demo-video") if project.demo_video.attached?

      write_devlogs(zip, project, project_dir)
    end
  end

  def write_devlogs(zip, project, project_dir)
    project.devlogs.includes(:post).find_each do |devlog|
      devlog_dir = "#{project_dir}/devlogs"

      zip.put_next_entry("#{devlog_dir}/devlog-#{devlog.id}.md")
      zip.write(devlog.body.to_s)

      if devlog.attachments.attached?
        devlog.attachments.each_with_index do |attachment, index|
          ext = File.extname(attachment.filename.to_s).presence || ".bin"
          download_attachment(zip, attachment, "#{devlog_dir}/attachments/#{devlog.id}-#{index + 1}#{ext}")
        end
      end
    end
  end

  # Streams the blob straight into the ZIP entry instead of loading the whole file into memory
  def download_attachment(zip, attachable, entry_name)
    attachment = attachable.try(:attachment) || attachable
    return unless attachment&.blob

    zip.put_next_entry(entry_name)
    attachment.open { |file| IO.copy_stream(file, zip) }
  end

  def write_readme(zip, user)
    project_count = user.projects.count
    devlog_count = user.projects.joins(:devlog_posts).count

    readme = <<~README
      # Stardance Data Export

      **User:** #{user.display_name}
      **Exported:** #{Time.current.strftime("%B %d, %Y at %H:%M UTC")}

      ## Contents

      - `profile.json` - Your profile data
      - `projects/` - Your projects, each containing:
        - `project.json` - Project metadata
        - `banner` - Project banner image (if uploaded)
        - `demo-video` - Demo video (if uploaded)
        - `devlogs/` - Development logs as Markdown files
          - `attachments/` - Images and files from each devlog

      ## Stats

      - **Projects:** #{project_count}
      - **Devlogs:** #{devlog_count}
    README

    zip.put_next_entry("README.md")
    zip.write(readme)
  end
end
