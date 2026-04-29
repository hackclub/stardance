class HCBMailbox < ApplicationMailbox
  def process
    if mail.subject.include?("You've received a donation for Stardance")
      if mail.body.decoded =~ %r{grants/}
        grant_id = mail.body.decoded.split("grants/").last.to_s.split(/[^a-zA-Z0-9]/).first
        shop_card_grant = ShopCardGrant.find_by(hcb_grant_hashid: "cdg_" + grant_id)
        donation_id = mail.body.decoded.split("donations/").last.to_s.split(/[\/\s]/).first.remove('"')

        if shop_card_grant
          begin
            donation_data = Faraday.get("#{HCBService.base_url}/api/v3/donations/don_#{donation_id}")
          rescue StandardError => e
            Rails.logger.error("Error fetching donation details for Donation ID #{donation_id}: #{e.message}")
            return
          end

          if donation_data.success?
            donation_json = JSON.parse(donation_data.body)
            amount_cents = donation_json["amount_cents"].to_i
            Rails.logger.info("Processing donation of #{amount_cents} cents for Grant ID cdg_#{grant_id}")

            if amount_cents
              shop_card_grant.topup!(amount_cents)
            else
              Rails.logger.error("Donation amount not found")
            end
          else
            Rails.logger.error("Failed to fetch donation details for Donation ID #{donation_id}")
          end
        else
          Rails.logger.error("ShopCardGrant not found for Grant ID cdg_#{grant_id}")
        end
      end
    end
  end
end
