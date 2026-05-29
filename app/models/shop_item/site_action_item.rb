class ShopItem::SiteActionItem < ShopItem
  enum :site_action, {
    audio_play: 0,
    italics: 1
  }
  has_one_attached :audio_file, dependent: :destroy, optional: true

  def fulfill!(shop_order)
    case site_action
    when "audio_play"
      ActionCable.server.broadcast("site_actions", { type: "audio_play", file: audio_file.blob&.service_url })
    when "italics"
      shop_order.user.shenanigans_state[:italics] = true
      shop_order.user.save!
    else 
      raise "Unknown site action #{site_action}"
    end
    shop_order.mark_fulfilled!("Site Action: #{site_action}", nil, "System")
  end
end
