class ApplicationMailbox < ActionMailbox::Base
  routing(/^tracking@/i => :tracking)
  routing(/^hcb@/i => :hcb)
  routing(/^rsvp@stardance\.hackclub\.com\z/i => :"rsvp/reply")
  routing(/^stardance@hackclub\.com\z/i => :"rsvp/reply")
  routing(/^stardance-inbound@stardance\.hackclub\.com\z/i => :"rsvp/reply")
  routing all: :incinerate
end
