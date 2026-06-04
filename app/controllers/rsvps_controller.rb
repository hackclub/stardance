class RsvpsController < ApplicationController
  def create
    was_new = false
    rsvp = Rsvp.find_or_create_by!(email: params[:rsvp][:email].to_s.downcase.strip) do |r|
      r.ref        = params[:ref].presence || cookies[:referral_code]
      r.user_agent = request.user_agent
      r.ip_address = client_ip_address
      was_new = true
    end
    if was_new && rsvp.user_ref.blank?
      flash[:user_ref_token] = rsvp.signed_id(purpose: :user_ref, expires_in: 1.hour)
    end
    redirect_to root_path, notice: "Thanks! We'll email you when we're ready for liftoff"
  rescue ActiveRecord::RecordInvalid
    redirect_to root_path, alert: "Please enter a valid email address."
  end

  def user_ref
    rsvp = Rsvp.find_signed!(params[:token], purpose: :user_ref)
    if rsvp.user_ref.present?
      redirect_to root_path, notice: "Already recorded — thanks!"
      return
    end
    value = params[:user_ref].to_s.strip
    value = params[:user_ref_other].to_s.strip.first(100) if value == "Other"
    rsvp.update(user_ref: value.presence)
    redirect_to root_path, notice: "Thanks for letting us know!"
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "That referral link expired."
  end

  def confirm
    Rsvp.find_by(confirmation_token: params[:token])&.confirm_click!
    redirect_to root_path, notice: "You're in! Reply to the email so we don't end up in spam <3"
  end

  def tic_tac
    render plain: <<~TXT, content_type: "text/plain"

      you are X. the bot is O. board cells are numbered 1-9:

       1 | 2 | 3
      -----------
       4 | 5 | 6
      -----------
       7 | 8 | 9

      to play: reply to the rsvp stardance email with a single number 1-9.
      that cell becomes your X. the bot picks an empty cell as O and
      replies back with the new board.

      first to three in a row wins. all nine filled with no winner = draw.

      reply STOP at any time to end the game.
    TXT
  end
end
