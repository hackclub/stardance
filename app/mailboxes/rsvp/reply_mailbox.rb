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
      reply.body_text   = extract_text_body
      reply.body_html   = mail.html_part&.body&.decoded
      reply.received_at = mail.date || Time.current
    end
  end

  def advance_game(rsvp)
    game = Rsvp::Game.current_for(rsvp) || Rsvp::Game.start_for(rsvp)
    cell = parse_cell(extract_text_body)

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
    unquoted_body.match?(STOP_REGEX)
  end

  def parse_cell(_body)
    digit = unquoted_body.scan(/[1-9]/).first
    digit && (digit.to_i - 1)
  end

  # strip attribution header
  def unquoted_body
    body = (extract_text_body || "").dup
    body = body.split(/^On .+? wrote:/m, 2).first || body
    body.lines.reject { |l| l.start_with?(">") }.join
  end

  def extract_text_body
    return mail.text_part.body.decoded if mail.text_part
    return nil if mail.multipart?

    mail.body.decoded
  end
end
