namespace :usernames do
  desc "Rebuild the Redis bloom filter for username availability checks"
  task rebuild_bloom: :environment do
    User::UsernameBloomFilter.rebuild!
    puts "Username bloom filter rebuilt with #{User.where.not(display_name: [ nil, '' ]).count} entries."
  end
end
