# frozen_string_literal: true

module Posts
  class ComposerComponent < ViewComponent::Base
    delegate :inline_svg_tag, to: :helpers

    attr_reader :post, :current_user, :projects, :selected_project, :test_time_granted,
                :url, :scope, :aria_label, :body_label, :placeholder, :submit_text,
                :disable_with, :simple_mode, :show_project_chips, :show_attachments,
                :show_time_preview, :show_record, :quote_preview_post

    def initialize(post:, current_user:, projects:, selected_project:, test_time_granted: false,
      url: nil, scope: nil, aria_label: "Create a devlog", body_label: "What are you working on?",
      placeholder: "What are you working on?", submit_text: "Post", disable_with: "Posting...",
      simple_mode: false, show_project_chips: true, show_attachments: true, show_time_preview: true,
      show_record: false, quote_preview_post: nil)
      @post = post
      @current_user = current_user
      @projects = projects
      @selected_project = selected_project
      @test_time_granted = test_time_granted
      @url = url
      @scope = scope
      @aria_label = aria_label
      @body_label = body_label
      @placeholder = placeholder
      @submit_text = submit_text
      @disable_with = disable_with
      @simple_mode = simple_mode
      @show_project_chips = show_project_chips
      @show_attachments = show_attachments
      @show_time_preview = show_time_preview
      @show_record = show_record
      @quote_preview_post = quote_preview_post
    end

    # When a post to quote is supplied, the composer shows it below the text box
    # (rendered as it appears nested in a quote repost on the timeline) so the
    # composer reads like the final card — your thought up top, the quoted post
    # beneath — without echoing your text a second time.
    def quote_preview?
      quote_preview_post.present?
    end

    def enabled?
      if simple_mode?
        current_user.present?
      else
        selected_project.present? && !setup_pending?
      end
    end

    def simple_mode?
      simple_mode
    end

    def show_project_chips?
      show_project_chips && projects.any?
    end

    def show_attachments?
      show_attachments
    end

    def show_time_preview?
      show_time_preview
    end

    # Only the /home composer shows the "Record a timelapse" button (toggled per
    # selected project by the composer controller). The project page has its own
    # dedicated record button, so its composer leaves this off.
    def show_record?
      show_record
    end

    # Where the Record button points for a given project chip, or "" when the
    # button shouldn't render. Lookout recording is offered for hardware projects,
    # and for every project once the :lookout flag is on (Lookout becomes the
    # default time path there). The view keys both the create-URL and the button's
    # visibility off this one method, so they can never drift apart.
    def record_url_for(project)
      return "" unless show_record? && project
      return "" unless project.hardware? || Flipper.enabled?(:lookout, current_user)
      helpers.project_lookout_sessions_path(project)
    end

    def form_url
      url || helpers.project_devlogs_path(selected_project)
    end

    # Guest user who has already started the first-project setup flow but
    # hasn't finished linking HCA. Their draft project exists but should be
    # gated behind link completion — surface a "finish setup" prompt instead
    # of the regular composer or empty-state banner.
    def setup_pending?
      current_user&.has_pending_setup_project?
    end

    def hackatime_linked?
      test_time_granted || selected_project&.hackatime_keys&.present?
    end

    def preview_time_url
      if selected_project.present?
        helpers.preview_time_project_devlogs_path(selected_project)
      end
    end
  end
end
