module CertificateFactory
  # Wires the fixture ship event as an approved ship authored by `user`,
  # giving them `hours` of approved ship time.
  def create_approved_ship(user, hours:)
    ship = post_ship_events(:one)
    ship.update_columns(certification_status: "approved", hours_at_ship: hours)
    posts(:one).update_columns(user_id: user.id, postable_type: "Post::ShipEvent", postable_id: ship.id)
  end
end
