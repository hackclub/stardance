# == Schema Information
#
# Table name: missions
#
#  id                           :bigint           not null, primary key
#  achievement_description      :text
#  achievement_name             :string
#  default_project_description  :text
#  default_project_title        :string
#  deleted_at                   :datetime
#  description                  :text             not null
#  difficulty                   :string
#  enabled                      :boolean          default(TRUE), not null
#  end_at                       :datetime
#  estimated_completion_minutes :integer
#  featured_at                  :datetime
#  name                         :string           not null
#  prizes_count                 :integer          default(0), not null
#  slug                         :string           not null
#  start_at                     :datetime
#  steps_count                  :integer          default(0), not null
#  submission_guide             :text
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_missions_on_deleted_at   (deleted_at)
#  index_missions_on_enabled      (enabled)
#  index_missions_on_featured_at  (featured_at)
#  index_missions_on_slug         (slug) UNIQUE
#
class Mission < ApplicationRecord
  include SoftDeletable

  has_paper_trail

  has_one_attached :icon
  has_one_attached :banner

  has_many :steps, class_name: "Mission::Step", dependent: :destroy
  has_many :prizes, class_name: "Mission::Prize", dependent: :destroy
  has_many :memberships, class_name: "Mission::Membership", dependent: :destroy
  has_many :shop_unlocks, class_name: "Mission::ShopUnlock", dependent: :destroy
  has_many :submissions, class_name: "Mission::Submission", dependent: :destroy
  has_many :attachments, class_name: "Project::MissionAttachment", dependent: :destroy
  has_many :projects, through: :attachments
  has_many :guide_variants, -> { order(:position, :id) },
           class_name: "Mission::GuideVariant", dependent: :destroy, inverse_of: :mission
  has_many :section_completions, class_name: "Mission::SectionCompletion", dependent: :destroy

  accepts_nested_attributes_for :guide_variants, allow_destroy: true,
                                                 reject_if: ->(attrs) { attrs[:language].blank? && attrs[:body].blank? }

  has_many :owners,    -> { where(mission_memberships: { role: :owner }) },
           through: :memberships, source: :user
  has_many :reviewers, -> { where(mission_memberships: { role: :reviewer }) },
           through: :memberships, source: :user

  DIFFICULTIES = %w[beginner intermediate advanced].freeze
  enum :difficulty, DIFFICULTIES.index_with(&:itself), prefix: true

  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9][a-z0-9_-]*\z/, message: "must be URL-safe" }
  validates :name, presence: true
  validates :description, presence: true
  validates :estimated_completion_minutes,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100_000 },
            allow_nil: true
  validates :default_project_title, length: { maximum: 120 }, allow_blank: true
  validates :default_project_description, length: { maximum: 1_000 }, allow_blank: true

  scope :enabled,  -> { where(enabled: true) }
  scope :featured, -> { where.not(featured_at: nil) }

  scope :visible_for, ->(user) {
    if user&.admin?
      all
    elsif user
      owned_ids = Mission::Membership.where(user_id: user.id, role: :owner).select(:mission_id)
      where(enabled: true).or(where(id: owned_ids))
    else
      enabled
    end
  }

  scope :available, -> {
    enabled
      .where("start_at IS NULL OR start_at <= ?", Time.current)
      .where("end_at   IS NULL OR end_at   > ?", Time.current)
  }

  def started?(at = Time.current) = start_at.nil? || start_at <= at
  def ended?(at = Time.current)   = end_at.present? && end_at <= at
  def coming_soon?(at = Time.current) = !started?(at)
  def available_at?(at = Time.current) = started?(at) && !ended?(at)

  def index_bucket
    return :draft unless enabled?
    return :upcoming if coming_soon?
    return :ended if ended?
    :available
  end

  def available_to_builders?
    enabled? && started? && !ended?
  end

  def has_steps?  = steps.any?
  def has_prizes? = prizes.any?

  def achievement_slug
    return nil if achievement_name.blank?
    "mission_#{slug}_completed"
  end

  def default_guide
    guide_variants.order(:position, :id).first
  end

  def has_guide? = guide_variants.any?

  def available_languages
    guide_variants.order(:position, :id).pluck(:language)
  end

  def has_multiple_guide_languages? = available_languages.length > 1

  def primary_guide_language_label
    default_guide&.language.presence || "Guide"
  end

  def resolve_storage_language(requested)
    label = requested.to_s.strip
    return default_guide&.language || "Default" if label.blank?
    existing = guide_variants.find_by("LOWER(language) = ?", label.downcase)&.language
    existing || label
  end

  def guide_body_for(language)
    return nil if language.blank?
    variant = guide_variants.find_by("LOWER(language) = ?", language.to_s.downcase)
    variant&.body || default_guide&.body
  end

  def guide_sections
    steps.where(deleted_at: nil).ordered.map.with_index do |step, idx|
      { index: idx, id: "step-#{step.id}", text: step.title, mission_step_id: step.id }
    end
  end

  def guide_body_updated_at = default_guide&.body_updated_at


  def self.parse_h2_sections(text)
    return [] if text.to_s.strip.empty?
    sections = []
    current = nil
    # CRLF tolerance — CRLF-pasted guides would otherwise leave \r in headings.
    text.split(/\r?\n/).each do |line|
      if (m = line.match(/\A##\s+(.*)\z/))
        sections << current if current
        current = { title: m[1].strip, body: [] }
      elsif current
        current[:body] << line
      end
    end
    sections << current if current
    sections.map { |s| { title: s[:title], body: s[:body].join("\n").strip } }
  end

  # Demote step-body headings so the topmost lands at H3 (step title is H2).
  def self.shift_headings_for_step(body)
    return body.to_s if body.to_s.strip.empty?
    lines = body.split("\n")
    levels = lines.filter_map { |l| l.match(/\A(#+)\s+/)&.captures&.first&.length }
    return body if levels.empty?
    shift = 3 - levels.min
    return body if shift <= 0
    lines.map { |l|
      if (m = l.match(/\A(#+)(\s+.*)\z/))
        new_level = [ [ m[1].length + shift, 1 ].max, 6 ].min
        "#{'#' * new_level}#{m[2]}"
      else
        l
      end
    }.join("\n")
  end

  def regenerate_text_for_language!(language)
    return if language.blank?

    ordered = steps.where(deleted_at: nil).ordered.to_a
    new_body = ordered.map { |step|
      title = step.title.to_s.strip
      raw   = step.body_for(language).to_s.strip
      body  = Mission.shift_headings_for_step(raw)
      body.present? ? "## #{title}\n\n#{body}" : "## #{title}"
    }.join("\n\n").strip

    save_variant_atomically(language, new_body)
  end

  # Retry once on RecordNotUnique: two concurrent first-paste requests for the
  # same brand-new language race on the (mission_id, language) unique index.
  def save_variant_atomically(language, new_body, retried: false)
    variant = guide_variants
                .where("LOWER(language) = ?", language.to_s.downcase)
                .first || guide_variants.new(
                  language: language,
                  position: (guide_variants.maximum(:position).to_i + 1)
                )
    variant._skip_steps_sync = true
    variant.body = new_body
    variant.save!
  rescue ActiveRecord::RecordNotUnique
    raise if retried
    save_variant_atomically(language, new_body, retried: true)
  end
  private :save_variant_atomically

  # A paste is the source of truth for step COUNT and order: extra parsed
  # sections create new shared steps, missing sections soft-delete them — and
  # that affects every language (the paste modal warns about overwrite).
  def sync_steps_for_language!(language)
    return if language.blank?
    variant = guide_variants.find_by("LOWER(language) = ?", language.to_s.downcase)
    canonical = variant&.language || language.to_s
    parsed = Mission.parse_h2_sections(variant&.body.to_s)
    structure_changed = false

    Mission::Step.transaction do
      shared = steps.where(deleted_at: nil).ordered.to_a
      parsed.each_with_index do |section, idx|
        step = shared[idx]
        title = section[:title].presence || "Untitled step"
        body  = section[:body].presence || ""

        if step
          step.update!(title: title) if step.title != title
        else
          step = steps.create!(title: title, position: idx + 1)
          structure_changed = true
        end
        step.upsert_body_for!(canonical, body)
      end

      extras = shared.drop(parsed.length)
      extras.each do |extra|
        extra.update!(deleted_at: Time.current)
      end
      structure_changed ||= extras.any?
    end

    # Sibling languages' stored bodies are now out of sync with the shared
    # step list — rebuild so other tabs reflect the new structure.
    if structure_changed
      guide_variants.where.not("LOWER(language) = ?", canonical.downcase).each do |sibling|
        regenerate_text_for_language!(sibling.language)
      end
    end
  end

  # submission_guide layout: intro paragraph, dash-bulleted criteria, optional
  # outro. The mission home renders each chunk into its own card.
  def submission_guide_lines
    submission_guide.to_s.split(/\r?\n/)
  end

  def submission_criteria
    submission_guide_lines.filter_map do |line|
      stripped = line.strip
      next unless stripped.start_with?("- ", "* ")
      stripped.sub(/^[\-\*]\s+/, "").presence
    end
  end

  def submission_guide_intro
    return nil if submission_guide.blank?
    lines = submission_guide_lines.take_while { |l| !l.strip.start_with?("- ", "* ") }
    lines.join("\n").strip.presence
  end

  def submission_guide_outro
    return nil if submission_guide.blank?
    lines = submission_guide_lines
    first_bullet = lines.find_index { |l| l.strip.start_with?("- ", "* ") }
    return nil unless first_bullet
    after = lines[first_bullet..].drop_while { |l| l.strip.start_with?("- ", "* ") || l.strip.empty? }
    after.join("\n").strip.presence
  end

  def display_id
    "STR-#{(id.to_i % 1000).to_s.rjust(3, "0")}"
  end

  def estimated_completion_label
    return nil if estimated_completion_minutes.blank?
    mins = estimated_completion_minutes.to_i
    return nil if mins <= 0
    if mins < 60
      "~#{mins} min"
    else
      hours, remainder = mins.divmod(60)
      if remainder.zero?
        "~#{hours} hr"
      else
        "~#{hours} hr #{remainder} min"
      end
    end
  end

  def showcase_projects(limit: 6)
    devlog_likes = Post::Devlog
                     .joins(:post)
                     .group("posts.project_id")
                     .select("posts.project_id, SUM(post_devlogs.likes_count) AS devlog_likes_count")

    Project
      .joins(:mission_attachments)
      .where(project_mission_attachments: { mission_id: id, detached_at: nil }, deleted_at: nil)
      .joins("LEFT JOIN (#{devlog_likes.to_sql}) mission_devlog_likes ON mission_devlog_likes.project_id = projects.id")
      .left_joins(:project_follows)
      .group("projects.id", "mission_devlog_likes.devlog_likes_count")
      .order(Arel.sql(<<~SQL))
        (COALESCE(mission_devlog_likes.devlog_likes_count, 0)
          + COUNT(DISTINCT project_follows.id)) DESC,
        projects.id DESC
      SQL
      .limit(limit)
      .includes(:users)
      .with_attached_banner
      .to_a
  end

  def approved_submission_project_ids
    submissions
      .where(status: "approved")
      .joins(ship_event: :post)
      .distinct
      .pluck("posts.project_id")
  end
end
