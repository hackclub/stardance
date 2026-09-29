namespace :seed do
  desc "Add fictional local feed data without removing existing records or creating shipped hours"
  task demo_feed: :environment do
    require_relative "../../db/development_seed/demo_feed"
    puts DevelopmentSeed::DemoFeed.call.to_json
  end

  desc "Seed the database with a realistic community for development"
  task community: :environment do
    require_relative "../../db/development_seed/runner"
    DevelopmentSeed::Runner.call
  end
end
