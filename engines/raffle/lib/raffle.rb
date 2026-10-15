require "raffle/engine"

module Raffle
  # The AMD GPU raffle has ended. While true, every GPU raffle promotion is
  # hidden: on the raffle site (entry, referral and leaderboard UI, prize copy,
  # FAQ) and in the main app (landing copy and prize, age gate, project pages,
  # referral banner). Set back to false to bring all of it back unchanged.
  ENDED = true

  def self.ended? = ENDED
end
