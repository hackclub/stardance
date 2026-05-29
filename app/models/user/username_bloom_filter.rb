class User::UsernameBloomFilter
  REDIS_KEY = "username_bloom_filter:bitfield".freeze
  BIT_SIZE = 2**20
  HASH_COUNT = 7

  class << self
    def probably_taken?(name)
      if name.blank?
        false
      elsif redis_available?
        all_bits_set?(name.downcase)
      else
        db_exists?(name)
      end
    end

    def add(name)
      return unless redis_available?
      return if name.blank?

      normalized = name.downcase
      bit_positions = hash_positions(normalized)

      redis.then do |conn|
        bit_positions.each { |pos| conn.setbit(REDIS_KEY, pos, 1) }
      end
    end

    def rebuild!
      return unless redis_available?

      redis.then { |conn| conn.del(REDIS_KEY) }

      User.unscoped
          .where.not(display_name: [ nil, "" ])
          .in_batches(of: 1000) do |batch|
        batch.pluck(:display_name).each { |name| add(name) }
      end
    end

    def available?(name)
      !probably_taken?(name)
    end

    private
      def all_bits_set?(normalized)
        bit_positions = hash_positions(normalized)

        redis.then do |conn|
          bit_positions.all? { |pos| conn.getbit(REDIS_KEY, pos) == 1 }
        end
      end

      def hash_positions(normalized)
        HASH_COUNT.times.map do |i|
          Digest::MD5.hexdigest("#{i}:#{normalized}").to_i(16) % BIT_SIZE
        end
      end

      def redis_available?
        Rails.cache.respond_to?(:redis)
      end

      def redis
        Rails.cache.redis
      end

      def db_exists?(name)
        User.unscoped
            .where("LOWER(display_name) = ?", name.downcase)
            .exists?
      end
  end
end
