module RaffleEndedHelpers
  # Temporarily flip Raffle::ENDED, the switch that hides GPU raffle promotion.
  def with_raffle_ended(value)
    original = Raffle::ENDED
    Raffle.send(:remove_const, :ENDED)
    Raffle.const_set(:ENDED, value)
    yield
  ensure
    Raffle.send(:remove_const, :ENDED)
    Raffle.const_set(:ENDED, original)
  end
end
