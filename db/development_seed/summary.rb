module DevelopmentSeed
  class Summary
    include Helpers

    def self.call
      new.call
    end

    def call
      puts "\n" + ("=" * 40)
      log "DEVELOPMENT COMMUNITY SUMMARY"
      puts ("=" * 40)

      log "Users:          #{User.count}"
      log "Projects:       #{Project.count}"
      log "Memberships:    #{Project::Membership.count}"

      log "Devlogs:        #{Post::Devlog.count}"
      log "Comments:       #{Comment.count}"
      log "Likes:          #{Like.count}"
      log "Reposts:        #{Post::Repost.count}"

      log "Ledger Entries: #{LedgerEntry.count}"
      log "Total Stardust: #{LedgerEntry.sum(:amount)}"

      puts ("=" * 40) + "\n"
    end
  end
end
