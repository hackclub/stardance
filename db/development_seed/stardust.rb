module DevelopmentSeed
  class Stardust
    include Helpers

    def self.call(users)
      new(users).call
    end

    def initialize(users)
      @users = users
    end

    def call
      progress "Generating stardust history (earnings and spendings)"

      count = 0
      @users.each do |user|
        create_grant(user, 100, "Free Stickers Welcome Grant")
        count += 1

        num_entries = random.rand(1..Config::STARDUST_TRANSACTIONS_PER_USER)
        num_entries.times do
          if create_reward(user)
            count += 1
          end
        end

        if random.rand < 0.4
          num_spends = random.rand(1..3)
          num_spends.times do
            if create_spending(user)
              count += 1
            end
          end
        end
      end

      done
      count
    end

    private

    def create_grant(user, amount, reason)
      LedgerEntry.create!(
        user: user,
        ledgerable: user,
        amount: amount,
        reason: reason,
        created_by: "Seed System"
      )
    end

    def create_reward(user)
      project = user.projects.sample(random: random)
      return false unless project

      amount = [ 50, 100, 150, 200, 500 ].sample(random: random)
      reason = [
        "Project Payout: #{project.title}",
        "Ship Bonus: #{project.title}",
        "Community Contribution Reward",
        "Achievement Unlocked: Project Starter"
      ].sample(random: random)

      LedgerEntry.create!(
        user: user,
        ledgerable: project,
        amount: amount,
        reason: reason,
        created_by: "Seed System"
      )
      true
    end

    def create_spending(user)
      return false if user.balance < 50

      amount = -[ 50, 100, 200 ].sample(random: random)

      LedgerEntry.create!(
        user: user,
        ledgerable: user,
        amount: amount,
        reason: [ "Shop Purchase: Sticker Pack", "Shop Purchase: Hardware Grant", "Shop Purchase: Digital Asset" ].sample(random: random),
        created_by: "Seed System"
      )
      true
    end
  end
end
