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
