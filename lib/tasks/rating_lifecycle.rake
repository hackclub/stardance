namespace :rating_lifecycle do
  desc "Report or backfill rating lifecycle timestamps (set APPLY=1 to persist)"
  task backfill: :environment do
    apply = ENV["APPLY"] == "1"
    result = RatingLifecycle::Backfill.new(apply: apply).call

    puts "Rating lifecycle #{apply ? 'backfill' : 'dry run'} complete"
    puts "Scanned: #{result.scanned}"
    puts "#{apply ? 'Changed' : 'Would change'}: #{result.changed}"
    puts "Exact: #{result.exact}"
    puts "Estimated: #{result.estimated}"
    puts "Unresolved: #{result.unresolved}"
  end
end
