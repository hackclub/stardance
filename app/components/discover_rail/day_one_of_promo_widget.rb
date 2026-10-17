# frozen_string_literal: true

module DiscoverRail
  class DayOneOfPromoWidget < BaseWidget
    register_as :day_one_of_promo

    def render?
      helpers.platform_ads_enabled?(user)
    end

    URL = "https://dayoneof.hackclub.com/?utm_source=stardance&utm_medium=discover_rail"
    IDEAS = [
      "Day one of learning piano from scratch",
      "Day one of learning to solder your first PCB",
      "Day one of learning to draw portraits",
      "Day one of learning to skateboard",
      "Day one of learning to build a game in Godot",
      "Day one of learning to cook",
      "Day one of learning to run a mile",
      "Day one of learning Japanese out loud",
      "Day one of learning video editing one effect at a time",
      "Day one of learning 3D printing by fixing things around the house",
      "Day one of learning to fix every squeaky door in my house",
      "Day one of learning to build a mechanical keyboard from parts",
      "Day one of learning to film cinematic shots on my phone",
      "Day one of learning to code a Discord bot for my friends",
      "Day one of learning latte art with a cheap milk frother",
      "Day one of learning to repair old electronics from the thrift store",
      "Day one of learning to grow vegetables on my windowsill",
      "Day one of learning to solve a Rubik's cube under a minute",
      "Day one of learning to make a soundtrack for an indie game",
      "Day one of learning to bind a notebook by hand"
    ].freeze
  end
end
