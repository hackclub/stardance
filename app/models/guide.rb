Guide = Data.define(:slug, :title, :description, :category, :icon, :reading_minutes, :related, :markdown, :hidden) do
  include ActiveModel::Conversion
  extend ActiveModel::Naming

  self::CATEGORY_ORDER = %i[stardance_101 hardware shipping craft program].freeze

  self::CATEGORY_LABELS = {
    stardance_101: "Stardance 101",
    shipping: "Shipping",
    craft: "Craft",
    program: "Program",
    hardware: "Hardware"
  }.freeze

  # Root directory that `markdown:` paths are resolved against.
  self::TOPICS_ROOT = "app/views/guides/topics".freeze

  def initialize(params = {})
    params[:related] ||= []
    params[:icon] ||= "info"
    params[:reading_minutes] ||= 5
    params[:markdown] ||= nil
    params[:hidden] ||= false
    super(**params)
  end

  self::ALL = [
    new(
      slug: :what_is_shipping,
      title: "What does shipping mean?",
      description: "What it means to ship a project on Stardance, what review looks for, and what happens after you click the button.",
      category: :shipping,
      icon: "ship",
      reading_minutes: 5,
      related: %i[how_to_ship great_readme]
    ),
    new(
      slug: :how_to_ship,
      title: "How to ship: by project type",
      description: "Pick what you built, get a tailored checklist of what 'shipped' means for that kind of project — from web apps to hardware to OSS contributions.",
      category: :shipping,
      icon: "compass_fill",
      reading_minutes: 4,
      related: %i[what_is_shipping great_readme]
    ),
    new(
      slug: :great_readme,
      title: "Writing a README that doesn't suck",
      description: "Structure, must-haves, and common mistakes — the README is the first thing reviewers and voters see.",
      category: :craft,
      icon: "edit",
      reading_minutes: 5,
      related: %i[github_repository what_is_shipping how_to_ship]
    ),
    new(
      slug: :github_repository,
      title: "Create your GitHub repository",
      description: "Set up a public GitHub repository for your project's code and link it back to Stardance.",
      category: :craft,
      icon: "code",
      reading_minutes: 10,
      related: %i[good_git_commits great_readme]
    ),
    new(
      slug: :good_git_commits,
      title: "Good git commits",
      description: "Small, atomic, well-named commits make your project easier to read, review, and revisit. Here's how.",
      category: :craft,
      icon: "code",
      reading_minutes: 4,
      related: %i[github_repository great_readme]
    ),
    new(
      slug: :hackatime,
      title: "Hackatime isn't working?",
      description: "Troubleshooting Hackatime: linking your account, time not showing up, and common fixes.",
      category: :craft,
      icon: "info",
      reading_minutes: 4,
      related: %i[devlogs how_to_ship]
    ),
    new(
      slug: :devlogs,
      title: "Devlogs that get noticed",
      description: "What to put in a devlog, how often to post, and why this affects voting.",
      category: :craft,
      icon: "edit",
      reading_minutes: 4,
      related: %i[what_is_shipping hackatime]
    ),
    new(
      slug: :why_we_ask,
      title: "Why we ask for your info",
      description: "What Stardance does with your birthday, region, and address — and what we don't do.",
      category: :program,
      icon: "info",
      reading_minutes: 3,
      related: []
    ),
    new(
      slug: :now_what,
      title: "I've set up my account. Now what?",
      description: "Just signed up? Here's the whole Stardance loop — from your first project to spending Stardust — in one place.",
      category: :stardance_101,
      icon: "compass_fill",
      reading_minutes: 3,
      related: %i[software hardware what_is_shipping],
      markdown: "now_what.md",
      hidden: true
    ),
    new(
      slug: :hardware,
      title: "Hardware in Stardance 101",
      description: "Step-by-step on how to make hardware projects in Stardance!",
      category: :stardance_101,
      icon: "rocket",
      reading_minutes: 2,
      related: %i[starting-hardware shipping-hardware tiers],
      markdown: "hardware/hardware.md"
    ),
    new(
      slug: :"starting-hardware",
      title: "Starting your hardware project",
      description: "A quick crash course on how to start a hardware project from scratch, great for beginners!",
      category: :hardware,
      icon: "compass_fill",
      reading_minutes: 5,
      related: %i[hardware shipping-hardware tiers],
      markdown: "hardware/starting-hardware.md"
    ),
    new(
      slug: :"shipping-hardware",
      title: "Shipping your hardware project",
      description: "Learn how to get your hardware project ready to submit, step-by-step!",
      category: :hardware,
      icon: "ship",
      reading_minutes: 5,
      related: %i[hardware starting-hardware tiers],
      markdown: "hardware/shipping-hardware.md"
    ),
    new(
      slug: :tiers,
      title: "Hardware funding tiers",
      description: "What the different funding tiers are for hardware projects, including funding amounts!",
      category: :hardware,
      icon: "info",
      reading_minutes: 3,
      related: %i[hardware starting-hardware shipping-hardware],
      markdown: "hardware/tiers.md"
    ),
    new(
      slug: :software,
      title: "Software in Stardance 101",
      description: "Step-by-step on how to make software projects in Stardance!",
      category: :stardance_101,
      icon: "rocket",
      reading_minutes: 2,
      related: %i[github_repository hackatime good_git_commits devlogs what_is_shipping how_to_ship],
      markdown: "software.md"
    ),
    new(
      slug: :virality_bonus,
      title: "Virality Bonus",
      description: "If your project goes viral outside Hack Club, you can earn bonus stardust and an enhanced payout multiplier.",
      category: :shipping,
      icon: "rocket",
      reading_minutes: 4,
      related: %i[what_is_shipping how_to_ship great_readme],
      markdown: "virality_bonus.md"
    )
  ].freeze

  self::SLUGGED = self::ALL.index_by(&:slug).freeze

  class << self
    def all
      self::ALL
    end
    def find(s)
      guide = self::SLUGGED[s.to_sym] or raise ActiveRecord::RecordNotFound, "Unknown guide: #{s}"
      raise ActiveRecord::RecordNotFound, "Unknown guide: #{s}" unless all.include?(guide)
      guide
    end
    def find_by_slug(s)
      guide = self::SLUGGED[s&.to_sym]
      guide if guide && all.include?(guide)
    end
    # Guides shown in the resources index. Hidden guides stay reachable by
    # direct URL (e.g. linked from the funding modal) but aren't listed.
    def listed = all.reject(&:hidden)
    def by_category = listed.group_by(&:category)
    def category_label(c) = self::CATEGORY_LABELS[c.to_sym]
    def category_order = self::CATEGORY_ORDER
  end

  def to_param = slug.to_s
  def persisted? = true

  def category_label = self.class::CATEGORY_LABELS[category]

  def related_guides = related.map { |s| Guide.find_by_slug(s) }.compact.reject(&:hidden)

  # Hardware partials live under topics/hardware/; everything else sits
  # directly in topics/.
  def partial_path = "guides/topics/#{"hardware/" if category == :hardware}#{slug}"

  # A guide renders from a markdown file when `markdown:` points at one;
  # otherwise it falls back to its `_<slug>.html.erb` partial (see show.html.erb).
  def markdown? = markdown.present?

  def markdown_path = markdown && Rails.root.join(self.class::TOPICS_ROOT, markdown)

  # Raw markdown source for the body; nil for partial-backed guides. The view
  # feeds this to MarkdownContentComponent (flavor: :guide), which renders via
  # MarkdownRenderer.render_guide and wraps the output in .guide-content for
  # styling. Read fresh each request; render_guide caches by content hash, so
  # edits to the .md file appear immediately without a server restart.
  def markdown_source
    return nil unless markdown?
    File.read(markdown_path)
  end
end
