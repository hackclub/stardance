#!/usr/bin/env ruby
# frozen_string_literal: true

# Find verified users who turned 19 after Stardance launched (Dec 15, 2025)
# and restore their YSWS eligibility by setting manual_ysws_override = true.
#
# Filters:
#  a) identity verified
#  b) NOT currently YSWS eligible
#  c) not explicitly denied by admin (manual_ysws_override != false)
#  d) turned 19 on or after Dec 15, 2025
#  e) not banned
#
# Usage:
#   bin/rails runner script/find_banned_19_year_olds.rb              (dry-run: lists affected users)
#   bin/rails runner script/find_banned_19_year_olds.rb --execute    (sets manual_ysws_override for affected users)

require_relative "../config/environment"
require "csv"

execute = ARGV.include?("--execute")
cutoff_date = Date.new(2025, 12, 15)
candidate_rows = []
updated_count = 0

User.where(verification_status: "verified").find_each do |user|
  next if user.ysws_eligible?
  next if user.manual_ysws_override == false
  next if user.birthday.nil?

  turned_19_on = user.birthday.advance(years: 19)
  next unless turned_19_on >= cutoff_date

  candidate_rows << [ user.id, turned_19_on.iso8601, user.created_at&.iso8601 ]

  if execute && !user.banned? && user.manual_ysws_override != true
    puts "user #{user.id}: setting manual_ysws_override = true"
    old_override = user.manual_ysws_override
    PaperTrail.request(whodunnit: "script/find_banned_19_year_olds.rb") do
      user.update!(manual_ysws_override: true)

      PaperTrail::Version.create!(
        item_type: "User",
        item_id: user.id,
        event: "manual_ysws_override_set",
        whodunnit: "script/find_banned_19_year_olds.rb",
        object_changes: { manual_ysws_override: [ old_override, true ] }.to_json
      )

      Shop::ProcessVerifiedOrdersJob.perform_later(user.id) if user.eligible_for_shop?

      puts "user #{user.id}: manual_ysws_override set"
      updated_count += 1
    end
  end
end

puts "#{candidate_rows.size} users found"
puts "#{updated_count} users changed" if execute

puts CSV.generate_line([ "id", "turned_19_on", "created_at" ])
candidate_rows.each { |row| puts CSV.generate_line(row) }
