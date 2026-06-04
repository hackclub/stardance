# frozen_string_literal: true

# == Schema Information
#
# Table name: ambassador_cost_stats
#
#  id                                :bigint           not null, primary key
#  admin_cost_cents                  :integer          default(0), not null
#  admin_cost_us_cents               :integer          default(0), not null
#  ambassador_region_breakdown       :jsonb            not null
#  approved_ambassadors_count        :integer          default(0), not null
#  average_cost_per_ambassador_cents :integer          default(0), not null
#  average_cost_us_cents             :integer          default(0), not null
#  office_grant_cost_cents           :integer          default(0), not null
#  office_grant_cost_us_cents        :integer          default(0), not null
#  poster_cost_cents                 :integer          default(0), not null
#  poster_cost_us_cents              :integer          default(0), not null
#  referral_cost_cents               :integer          default(0), not null
#  referral_cost_us_cents            :integer          default(0), not null
#  shirt_cost_cents                  :integer          default(0), not null
#  shirt_cost_us_cents               :integer          default(0), not null
#  synced_at                         :datetime         not null
#  total_cost_cents                  :integer          default(0), not null
#  total_cost_us_cents               :integer          default(0), not null
#  created_at                        :datetime         not null
#  updated_at                        :datetime         not null
#
# Indexes
#
#  index_ambassador_cost_stats_on_synced_at  (synced_at)
#
class AmbassadorCostStat < ApplicationRecord
  scope :latest, -> { order(synced_at: :desc) }
end
