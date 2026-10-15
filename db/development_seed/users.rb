module DevelopmentSeed
  class Users
    include Helpers

    def self.call
      new.call
    end

    def call
      progress "Generating #{Config::USER_COUNT} users"

      users = []
      Config::USER_COUNT.times do |i|
        users << create_user(i)
      end

      done
      users
    end

    private

    def create_user(index)
      # deterministic names based on index and random seed
      first_name = first_names[random.rand(first_names.size)]
      last_name = last_names[random.rand(last_names.size)]
      display_name = "#{first_name.downcase}_#{last_name.downcase}_#{index}"
      email = "#{display_name}@example.com"

      user = User.new(
        first_name: first_name,
        last_name: last_name,
        display_name: display_name,
        email: email,
        # verified status is required for posts to be visible to others
        verification_status: "verified",
        onboarded_at: Time.current - (random.rand(1..30)).days
      )

      # set synced_at to prevent trying to sync with Hackatime immediately
      user.synced_at = Time.current

      user.save!

      # opt-in to leaderboard by default (preference is auto-created by User model callback)
      user.preference.update!(leaderboard_optin: true)

      user.identities.create!(
        provider: "hack_club",
        uid: "seed_#{index}",
        access_token: "seed_token_#{index}"
      )

      user
    end

    def first_names
      %w[Alice Bob Charlie David Eve Frank Grace Heidi Ivan Judy Kevin Laura Mike Nancy Oscar Peggy Quinn Rose Steve Trudy Victor Wendy Xander Yvonne Zelda]
    end

    def last_names
      %w[Smith Johnson Williams Brown Jones Garcia Miller Davis Rodriguez Martinez Hernandez Lopez Gonzalez Wilson Anderson Thomas Taylor Moore Jackson Martin Lee Perez Thompson White Harris]
    end
  end
end
