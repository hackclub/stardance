module ProjectsHelper
  def recertification_cooldown_message(available_at)
    "Re-certification is on cooldown. You can request again in #{distance_of_time_in_words_to_now(available_at)}."
  end

  def safe(url, text = nil)
    return unless url.present? && url.start_with?("http")
    link_to(text || url, url, target: "_blank")
  end
end
