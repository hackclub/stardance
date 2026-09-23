module Certification
  # Holds a hardware T1 approval's payout until a T2 reviewer clears it. Hosts
  # define run_deferred_approval_effects! and guard on second_stage_cleared?.
  module SecondStageGated
    extend ActiveSupport::Concern

    included do
      has_one :second_stage_review,
              class_name: "Certification::SecondStageReview",
              as: :reviewable,
              dependent: :destroy

      # Marks a T2-driven save, so the host doesn't re-award the T1 bounty.
      attr_accessor :releasing_second_stage

      after_save_commit :open_second_stage_review!,
                        if: -> { saved_change_to_status? && approved? && second_stage_required? && !releasing_second_stage }

      # An undone T1 approval must not leave a live T2 review that could still pay out.
      after_save :void_second_stage_review!,
                 if: -> { saved_change_to_status? && !approved? && !releasing_second_stage && project&.hardware? }
    end

    # A global flag, not per-actor: whether money moves can't depend on who approved.
    def second_stage_required?
      return false unless Flipper.enabled?(:hardware_t2_review)

      project&.hardware?
    end

    def second_stage_cleared?
      return true unless second_stage_required?

      second_stage_review&.approved? || false
    end

    def awaiting_second_stage?
      approved? && second_stage_required? && !second_stage_review&.approved?
    end

    def release_second_stage!
      # Polymorphic, so a cached copy may still read as pending and pay nothing.
      reload_second_stage_review
      self.releasing_second_stage = true
      run_deferred_approval_effects!
    ensure
      self.releasing_second_stage = false
    end

    # An ordinary T1 return with T2's feedback. reviewer_id is left alone, or the
    # T1 reviewer's bounty would move to the T2 reviewer.
    def return_from_second_stage!(feedback:)
      self.releasing_second_stage = true
      update!(status: :returned, decided_at: Time.current, feedback: feedback)
    ensure
      self.releasing_second_stage = false
    end

    private

    def open_second_stage_review!
      Certification::SecondStageReview.open_for!(self)
    rescue StandardError => e
      Rails.logger.error("#{self.class.name} ##{id} open_second_stage_review! failed: #{e.message}")
    end

    # A decided one records who signed off on a payout, so it's kept.
    def void_second_stage_review!
      second_stage_review&.destroy if second_stage_review&.pending?
    end
  end
end
