require "test_helper"

class Rsvp::ReplyMailboxTest < ActionMailbox::TestCase
  include ActionMailer::TestHelper

  self.fixture_table_names = []
  self.fixture_sets = {}
  test "reply from a known RSVP stamps reply_confirmed_at" do
    rsvp = Rsvp.create!(email: "fan@example.com")
    rsvp.update_column(:reply_confirmed_at, nil)

    receive_inbound_email_from_mail \
      to: "rsvp@stardance.hackclub.com",
      from: "fan@example.com",
      subject: "Re: welcome",
      body: "Hey Stardance"

    assert_not_nil rsvp.reload.reply_confirmed_at
  end

  test "reply with mixed-case sender still matches" do
    rsvp = Rsvp.create!(email: "loud@example.com")
    rsvp.update_column(:reply_confirmed_at, nil)

    receive_inbound_email_from_mail \
      to: "rsvp@stardance.hackclub.com",
      from: "LOUD@Example.com",
      subject: "Re: welcome",
      body: "hi"

    assert_not_nil rsvp.reload.reply_confirmed_at
  end

  test "reply from an unknown sender is a no-op" do
    assert_no_difference -> { Rsvp::Reply.count } do
      assert_nothing_raised do
        receive_inbound_email_from_mail \
          to: "rsvp@stardance.hackclub.com",
          from: "stranger@example.com",
          subject: "Re: welcome",
          body: "who?"
      end
    end

    assert_nil Rsvp.find_by(email: "stranger@example.com")
  end

  test "reply from a known RSVP persists the reply contents" do
    rsvp = Rsvp.create!(email: "writer@example.com")

    assert_difference -> { rsvp.replies.count }, 1 do
      receive_inbound_email_from_mail \
        to: "rsvp@stardance.hackclub.com",
        from: "writer@example.com",
        subject: "Re: welcome",
        body: "Excited for liftoff!"
    end

    reply = rsvp.replies.last
    assert_equal "Re: welcome", reply.subject
    assert_equal "Excited for liftoff!", reply.body_text
    assert_not_nil reply.received_at
  end

  test "duplicate Message-ID does not create a second reply" do
    rsvp = Rsvp.create!(email: "dupes@example.com")
    message_id = "<unique-message-id@example.com>"

    2.times do |i|
      receive_inbound_email_from_mail \
        to: "rsvp@stardance.hackclub.com",
        from: "dupes@example.com",
        subject: "Re: welcome",
        body: "take #{i}",
        message_id: message_id
    end

    assert_equal 1, rsvp.replies.count
  end

  test "first reply starts a tic-tac-toe game with no moves and emails the board" do
    rsvp = Rsvp.create!(email: "player@example.com")

    assert_enqueued_emails 1 do
      receive_inbound_email_from_mail \
        to: "rsvp@stardance.hackclub.com",
        from: "player@example.com",
        subject: "Re: welcome",
        body: "let's play"
    end

    game = Rsvp::Game.current_for(rsvp)
    assert_not_nil game
    assert_equal 0, game.move_count
  end

  test "subsequent reply with a digit plays the user move and a bot move" do
    rsvp = Rsvp.create!(email: "mover@example.com")
    Rsvp::Game.start_for(rsvp).update!(move_count: 1, board: "----X----")

    receive_inbound_email_from_mail \
      to: "rsvp@stardance.hackclub.com",
      from: "mover@example.com",
      subject: "Re: tic tac toe",
      body: "I pick 1\n> quoted board"

    game = Rsvp::Game.current_for(rsvp) || rsvp.games.order(:created_at).last
    assert_equal "X", game.board[0]
    assert game.move_count >= 2
  end

  test "quoted STOP in the previous email body does not end the game" do
    rsvp = Rsvp.create!(email: "quoter@example.com")
    Rsvp::Game.start_for(rsvp).update!(move_count: 4, board: "-OXX--O--")

    receive_inbound_email_from_mail \
      to: "rsvp@stardance.hackclub.com",
      from: "quoter@example.com",
      subject: "Re: tic tac toe",
      body: <<~BODY
        5

        On Mon, Apr 20, 2026 at 5:50 AM Stardance <stardance@hackclub.com> wrote:
        > Your move.
        > Reply with a number 1-9 for your next cell. Reply STOP to end the game.
      BODY

    stop_jobs = ActionMailer::Base.deliveries + enqueued_jobs.select do |j|
      j[:args]&.first == "Rsvp::Mailer" && j[:args]&.second == "tic_tac_toe_stop"
    end
    assert_empty stop_jobs
  end

  test "STOP keyword sends the stop email and skips the game" do
    rsvp = Rsvp.create!(email: "quitter@example.com")

    assert_enqueued_email_with Rsvp::Mailer, :tic_tac_toe_stop, args: [ rsvp ] do
      receive_inbound_email_from_mail \
        to: "rsvp@stardance.hackclub.com",
        from: "quitter@example.com",
        subject: "Re: welcome",
        body: "STOP"
    end

    assert_not_nil rsvp.reload.reply_confirmed_at
    assert_nil Rsvp::Game.current_for(rsvp)
  end

  test "STOP mid-game destroys the in-progress game so the next reply starts fresh" do
    rsvp = Rsvp.create!(email: "midstop@example.com")
    Rsvp::Game.start_for(rsvp).update!(move_count: 3, board: "X-O-X----")

    receive_inbound_email_from_mail \
      to: "rsvp@stardance.hackclub.com",
      from: "midstop@example.com",
      subject: "Re: ttt",
      body: "STOP"

    assert_nil Rsvp::Game.current_for(rsvp)
  end

  test "digit reply on an already-occupied cell does not enqueue a board email" do
    rsvp = Rsvp.create!(email: "occupied@example.com")
    Rsvp::Game.start_for(rsvp).update!(move_count: 2, board: "X-O------")

    assert_no_enqueued_emails do
      receive_inbound_email_from_mail \
        to: "rsvp@stardance.hackclub.com",
        from: "occupied@example.com",
        subject: "Re: ttt",
        body: "1"
    end
  end

  test "digit reply on a freshly-started game plays the move instead of resending start" do
    rsvp = Rsvp.create!(email: "eager@example.com")
    Rsvp::Game.start_for(rsvp)

    receive_inbound_email_from_mail \
      to: "rsvp@stardance.hackclub.com",
      from: "eager@example.com",
      subject: "Re: tic tac toe",
      body: "3"

    game = Rsvp::Game.current_for(rsvp) || rsvp.games.order(:created_at).last
    assert_equal "X", game.board[2]
    assert game.move_count >= 2
    assert_enqueued_email_with Rsvp::Mailer, :tic_tac_toe_move, args: [ game ]
  end

  test "first reply enqueues tic_tac_toe_start" do
    rsvp = Rsvp.create!(email: "starter@example.com")

    receive_inbound_email_from_mail \
      to: "rsvp@stardance.hackclub.com",
      from: "starter@example.com",
      subject: "Re: welcome",
      body: "let's play"

    game = Rsvp::Game.current_for(rsvp)
    assert_enqueued_email_with Rsvp::Mailer, :tic_tac_toe_start, args: [ game ]
  end

  test "winning move enqueues tic_tac_toe_over" do
    rsvp = Rsvp.create!(email: "winner@example.com")
    game = Rsvp::Game.start_for(rsvp)
    game.update!(board: "XX-OO----", move_count: 4)

    receive_inbound_email_from_mail \
      to: "rsvp@stardance.hackclub.com",
      from: "winner@example.com",
      subject: "Re: ttt",
      body: "3"

    assert_enqueued_email_with Rsvp::Mailer, :tic_tac_toe_over, args: [ game ]
    assert_predicate game.reload, :user_won?
  end
end
