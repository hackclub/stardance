class User
  TutorialStep = Data.define(:slug, :name, :description, :icon, :link, :deps, :verb, :video_url) do
    include ActiveModel::Conversion
    extend ActiveModel::Naming

    def initialize(params = {})
      params[:deps] ||= nil
      params[:verb] ||= :get
      params[:video_url] ||= nil
      super(**params)
    end

    # N.B.: this is not a proper graph, so be careful with your preconditions!
    # revoking a tutorial step (i.e. on delete) does not propagate up through dependency chains.
    Dep = Data.define(:slug, :hint) do
      def satisfied?(s)
        s.include?(slug)
      end
    end

    self::ALL = [
      new(:first_login, "First login", "Log into the platform for the first time!", "user", "/"),
      new(slug: :create_project,
          name: "Create your first project",
          description: "What are you cooking?",
          icon: "fork_spoon_fill",
          link: ->(_) { new_project_path }),
      new(slug: :post_devlog,
          name: "Post a devlog",
          description: "Dev your log!",
          icon: "edit",
          link: ->(_) { new_project_devlog_path(current_user.projects.first) },
          deps: [
            Dep[:create_project, "You need to create a project first!"]
          ]),
      new(slug: :identity_verified,
        name: "Confirm your age",
        description: "You must be a teenager to participate in Stardance",
        icon: "user",
        link: ->(_) { HCAService.verify_portal_url(return_to: kitchen_url) }),
      new(slug: :setup_hackatime,
          name: "Setup Hackatime",
          description: "Start tracking your time",
          icon: "time",
          link: "/auth/hackatime",
          verb: :post),
      new(slug: :setup_slack,
          name: "Join Slack",
          description: "Post in #flavortown-introduction after becoming a full member!",
          icon: "slack",
          link: ->(_) { "https://hackclub.slack.com/app_redirect?channel=USLACKBOT" }),
      new(slug: :free_stickers,
          name: "Get your stickers!",
          description: "Get your stickers!",
          icon: "sticker",
          link: ->(_) { shop_items_path },
          deps: [
            Dep[:setup_hackatime, "You need to setup Hackatime first!"]
          ]),
      new(slug: :learn_what_is_a_ship,
          name: "Learn what's a ship",
          description: "Watch a quick video on how to ship!",
          icon: "ship",
          link: "#tutorial-video-modal",
          verb: :modal,
          video_url: VimeoEmbedComponent.video_url(:what_is_a_ship)
        )
    ].freeze

    self::SLUGGED = self::ALL.index_by(&:slug).freeze
    self::ALL_SLUGS = self::SLUGGED.keys.freeze

    class << self
      def all
        self::ALL
      end

      def slugged
        self::SLUGGED
      end

      def all_slugs
        self::ALL_SLUGS
      end

      def find(s)
        self::SLUGGED.fetch(s.to_sym)
      end

      # console affordance - don't let me catch you using this in application code
      alias_method :[], :find
    end

    def deps_satisfied?(s)
      return true unless deps&.any?

      deps.all? { |d| d.satisfied?(s) }
    end

    def to_param
      slug
    end

    def persisted?
      true
    end
  end
end
