namespace :raffle do
  desc "Enroll all users who aren't already enrolled (everyone gets a referral code)"
  task enroll_existing: :environment do
    enrolled = 0
    skipped = 0

    User.find_each do |user|
      if Raffle::Participant.exists?(user_id: user.id)
        skipped += 1
      else
        Raffle::Participant.find_or_enroll!(user)
        enrolled += 1
      end
    end

    puts "Enrolled #{enrolled} users, skipped #{skipped} already enrolled."
  end
end
