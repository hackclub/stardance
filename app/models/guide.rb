Guide = Data.define(:slug, :title, :description, :category, :icon, :reading_minutes, :related, :markdown) do
  include ActiveModel::Conversion
  extend ActiveModel::Naming

  self::CATEGORY_ORDER = %i[shipping craft program outpost].freeze

  self::CATEGORY_LABELS = {
    shipping: "Shipping",
    craft: "Craft",
    program: "Program",
    outpost: "Hardware | Outpost"
  }.freeze

  # Root directory that `markdown:` paths are resolved against.
  self::TOPICS_ROOT = "app/views/guides/topics".freeze

  def initialize(params = {})
    params[:related] ||= []
    params[:icon] ||= "info"
    params[:reading_minutes] ||= 5
    params[:markdown] ||= nil
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
      reading_minutes: 4,
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
      slug: :devlogs,
      title: "Devlogs that get noticed",
      description: "What to put in a devlog, how often to post, and why this affects voting.",
      category: :craft,
      icon: "edit",
      reading_minutes: 4,
      related: %i[what_is_shipping]
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
      slug: :outpost,
      title: "Outpost",
      description: "Stardance's hardware track — a 6-day hardware hackathon and expo with Open Sauce in San Francisco.",
      category: :outpost,
      icon: "rocket",
      reading_minutes: 5,
      related: %i[starting-hardware shipping-hardware outpost-tiers outpost-faq],
      markdown: "outpost/outpost.md"
    ),
    new(
      slug: :"starting-hardware",
      title: "Starting your hardware project",
      description: "How to get started with your hardware project — coming up with an idea and advice for working on it.",
      category: :outpost,
      icon: "compass_fill",
      reading_minutes: 5,
      related: %i[outpost shipping-hardware outpost-tiers],
      markdown: "outpost/starting-hardware.md"
    ),
    new(
      slug: :"shipping-hardware",
      title: "Shipping your hardware project",
      description: "Get your project ready to ship — required files, repository structure, and the step-by-step.",
      category: :outpost,
      icon: "ship",
      reading_minutes: 5,
      related: %i[starting-hardware outpost outpost-tiers],
      markdown: "outpost/shipping-hardware.md"
    ),
    new(
      slug: :"outpost-tiers",
      title: "Project tier examples",
      description: "What the different Outpost project tiers look like, with budgets, points, and examples for each.",
      category: :outpost,
      icon: "code",
      reading_minutes: 4,
      related: %i[outpost starting-hardware],
      markdown: "outpost/tiers.md"
    ),
    new(
      slug: :"outpost-faq",
      title: "Outpost FAQ",
      description: "Frequently asked questions about Outpost — channels, logistics, and more.",
      category: :outpost,
      icon: "info",
      reading_minutes: 4,
      related: %i[outpost starting-hardware shipping-hardware],
      markdown: "outpost/faq.md"
    ),
    new(
      slug: :"super-hardware-builder",
      title: "Becoming a Super Hardware Builder",
      description: "How to earn Super Hardware Builder status — the requirement to qualify for Outpost.",
      category: :outpost,
      icon: "rocket",
      reading_minutes: 4,
      related: %i[outpost starting-hardware],
      markdown: "outpost/super-hardware-builder.md"
    )
  ].freeze

  self::SLUGGED = self::ALL.index_by(&:slug).freeze

  class << self
    def all = self::ALL
    def find(s) = self::SLUGGED[s.to_sym] or raise ActiveRecord::RecordNotFound, "Unknown guide: #{s}"
    def find_by_slug(s) = self::SLUGGED[s&.to_sym]
    def by_category = self::ALL.group_by(&:category)
    def category_label(c) = self::CATEGORY_LABELS[c.to_sym]
    def category_order = self::CATEGORY_ORDER
  end

  def to_param = slug.to_s
  def persisted? = true

  def category_label = self.class::CATEGORY_LABELS[category]

  def related_guides = related.map { |s| Guide.find_by_slug(s) }.compact

  def partial_path = "guides/topics/#{slug}"

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
