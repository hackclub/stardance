# Public transparency page for the shop order queue: how many orders are
# waiting, how long they have waited, and how long each item usually takes.
class QueueController < ApplicationController
  def index
    @snapshot = Shop::QueueSnapshot.cached
  end
end
