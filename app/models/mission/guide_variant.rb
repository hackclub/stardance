# == Schema Information
#
# Table name: mission_guide_variants
#
#  id              :bigint           not null, primary key
#  body            :text             not null
#  body_updated_at :datetime
#  language        :string           not null
#  position        :integer          default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  mission_id      :bigint           not null
#
# Indexes
#
#  index_mission_guide_variants_on_mission_id    (mission_id)
#  index_mission_guide_variants_unique_language  (mission_id,language) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (mission_id => missions.id)
#
class Mission::GuideVariant < ApplicationRecord
  self.table_name = "mission_guide_variants"

  has_paper_trail

  belongs_to :mission, inverse_of: :guide_variants

  validates :language, presence: true, length: { maximum: 64 },
                       uniqueness: { scope: :mission_id, case_sensitive: false }
  # Empty bodies are intentional: when a mission's last step is removed (or
  # before any steps exist) the regenerated body is an empty string and we
  # don't want save! to raise mid-controller.
  validates :body, length: { maximum: 200_000 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_save :stamp_body_updated_at, if: :body_changed?

  # Two-way sync with Mission::Step rows for this variant's language. The
  # flag is flipped by Mission#regenerate_text_for_language! when the body
  # change came FROM the steps editor (so we don't bounce back).
  attr_accessor :_skip_steps_sync
  after_save :sync_steps,
             if: -> { saved_change_to_body? && !_skip_steps_sync }

  def sections
    MarkdownRenderer.render_guide(body).outline
  end

  private

  def stamp_body_updated_at
    self.body_updated_at = Time.current
  end

  def sync_steps
    mission.sync_steps_for_language!(language)
  end
end
