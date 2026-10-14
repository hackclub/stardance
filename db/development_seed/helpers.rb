module DevelopmentSeed
  module Helpers
    def log(message)
      puts "[Seed] #{message}"
    end

    def progress(message)
      print "[Seed] #{message}..."
    end

    def done
      puts " Done!"
    end

    def random
      @random ||= Random.new(DevelopmentSeed::Config::RANDOM_SEED)
    end
  end
end
