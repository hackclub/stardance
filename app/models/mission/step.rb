# == Schema Information
#
# Table name: mission_steps
#
#  id         :bigint           not null, primary key
#  deleted_at :datetime
#  position   :integer          not null
#  title      :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  mission_id :bigint           not null
#
# Indexes
#
#  index_mission_steps_on_deleted_at               (deleted_at)
#  index_mission_steps_on_mission_id               (mission_id)
#  index_mission_steps_on_mission_id_and_position  (mission_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (mission_id => missions.id)
#
class Mission::Step < ApplicationRecord
  self.table_name = "mission_steps"

  include SoftDeletable

  has_paper_trail

  belongs_to :mission, inverse_of: :steps, counter_cache: true

  # counter_cache only fires on create/destroy — soft-deletes need a manual bump.
  after_update :adjust_steps_counter_on_soft_delete, if: :saved_change_to_deleted_at?

  # ON DELETE CASCADE / dependent: :destroy don't fire on soft-delete — without
  # this, completion rows would resurrect if a step is ever un-soft-deleted.
  after_update :cleanup_section_completions_on_soft_delete, if: :saved_change_to_deleted_at?

  private

  def adjust_steps_counter_on_soft_delete
    before, after = saved_change_to_deleted_at
    if before.nil? && after.present?
      Mission.where(id: mission_id).update_counters(steps_count: -1)
    elsif before.present? && after.nil?
      Mission.where(id: mission_id).update_counters(steps_count: 1)
    end
  end

  def cleanup_section_completions_on_soft_delete
    before, after = saved_change_to_deleted_at
    return unless before.nil? && after.present?
    Mission::SectionCompletion.where(mission_step_id: id).delete_all
  end

  public

  has_many :bodies, class_name: "Mission::StepBody",
                    foreign_key: :mission_step_id,
                    dependent: :destroy,
                    inverse_of: :step

  has_many :section_completions, class_name: "Mission::SectionCompletion",
                                 foreign_key: :mission_step_id,
                                 dependent: :destroy

  validates :title, presence: true
  validates :position, presence: true, numericality: { only_integer: true }

  scope :ordered, -> { order(:position, :id) }

  # .detect (not find_by) so includes(:bodies) hits the preloaded cache.
  def body_record_for(language)
    return nil if language.blank?
    target = language.to_s.downcase
    bodies.detect { |b| b.language.to_s.downcase == target }
  end

  def body_for(language) = body_record_for(language)&.body

  def upsert_body_for!(language, body)
    return if language.blank?
    existing = body_record_for(language)
    body_str = body.to_s
    if existing
      existing.update!(body: body_str) if existing.body != body_str
    else
      bodies.create!(language: language.to_s.strip, body: body_str)
    end
  end
end
