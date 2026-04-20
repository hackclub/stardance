class Rsvp::ReplyMailbox < ApplicationMailbox
  STOP_REGEX = /\bstop\b/i

  def process
    sender = mail.from.first.to_s.downcase.strip
    rsvp = Rsvp.find_by(email: sender)
    return unless rsvp

    rsvp.confirm_reply!
    persist_reply(rsvp)

    if stop_requested?
      Rsvp::Game.current_for(rsvp)&.destroy
      Rsvp::Mailer.tic_tac_toe_stop(rsvp).deliver_later
    else
      advance_game(rsvp)
    end
  end

  private

  def persist_reply(rsvp)
    rsvp.replies.find_or_create_by!(message_id: mail.message_id) do |reply|
      reply.subject     = mail.subject
      reply.body_text   = plain_body
      reply.body_html   = mail.html_part&.body&.decoded
      reply.received_at = mail.date || Time.current
    end
  end

  def advance_game(rsvp)
    game = Rsvp::Game.current_for(rsvp) || Rsvp::Game.start_for(rsvp)
    cell = parse_cell

    if cell.nil? && game.move_count.zero?
      Rsvp::Mailer.tic_tac_toe_start(game).deliver_later
      return
    end

    result = cell ? game.play_user_move(cell) : nil
    return if result == :invalid

    mailer_action = game.in_progress? ? :tic_tac_toe_move : :tic_tac_toe_over
    Rsvp::Mailer.public_send(mailer_action, game).deliver_later
  end

  def stop_requested?
    visible_reply.match?(STOP_REGEX)
  end

  def parse_cell
    digit = visible_reply.scan(/[1-9]/).first
    digit && (digit.to_i - 1)
  end

  def visible_reply
    EmailReplyParser.parse_reply(plain_body.to_s).to_s.strip
  end

  def plain_body
    return mail.text_part.body.decoded if mail.text_part
    return sanitize_html(mail.html_part.body.decoded) if mail.html_part
    return sanitize_html(mail.body.decoded) if mail.content_type.to_s.include?("text/html")

    mail.body.decoded
  end

  def sanitize_html(html)
    doc = Nokogiri::HTML.fragment(html.to_s)
    doc.css("blockquote, .gmail_quote, .gmail_attr").each(&:remove)
    doc.css("br").each { |n| n.replace(Nokogiri::XML::Text.new("\n", doc.document)) }
    doc.css("div, p, tr, li, h1, h2, h3, h4, h5, h6").each do |node|
      node.add_next_sibling(Nokogiri::XML::Text.new("\n", doc.document))
    end
    doc.text
  end
end
