# frozen_string_literal: true

require "openssl"

module BukuX3
  # Gives each account a stable, server-side 50/50 role assignment without a
  # migration. HMAC makes the result unpredictable from a public user ID while
  # the one-bit bucket keeps both roles equally likely.
  class Assignment
    SALT = "bukux3-role-v1"

    def self.buku?(user, secret: Rails.application.secret_key_base)
      new(user, secret:).buku?
    end

    # Count saved reveals, not all assigned accounts or development previews.
    # Use the same deterministic assignment as the reveal, without loading PII.
    def self.discovered_counts
      counts = { total: 0, buku: 0, bean: 0 }
      User.where("things_dismissed @> ARRAY[?]::varchar[]", BukuX3RevealComponent::DISMISS_THING)
        .select(:id).find_each do |user|
          counts[buku?(user) ? :buku : :bean] += 1
          counts[:total] += 1
        end
      counts
    end

    def initialize(user, secret:)
      @user = user
      @secret = secret
    end

    def buku?
      digest.getbyte(0) < 128
    end

    private
      attr_reader :user, :secret

      def digest
        OpenSSL::HMAC.digest("SHA256", secret, "#{SALT}:#{user.id}")
      end
  end
end
