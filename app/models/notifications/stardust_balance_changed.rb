module Notifications
  class StardustBalanceChanged < ::Notification
    self.default_priority     = :low
    self.aggregatable         = true
    self.category_key         = :stardust_balance_changed
    self.category_label       = "Stardust balance changes"
    self.category_description = "Your stardust balance went up or down"
    self.category_group       = "Stardust"

    def self.build_group_key(recipient:, **)
      "stardust_balance:#{recipient.id}"
    end

    def slack_message
      params["message"].presence
    end

    def email_subject
      amount = params["amount"].to_i
      if amount.positive?
        "+#{amount} stardust on your balance"
      elsif amount.negative?
        "#{amount} stardust on your balance"
      else
        "Stardust balance updated"
      end
    end
  end
end
