class DeleteShipDecisionPosts < ActiveRecord::Migration[8.1]
  # Shipwright verdicts used to be mirrored into the posts table as
  # "Post::ShipDecision" rows. Verdict cards now render straight from
  # certification_ship_reviews, so those rows are dead data.
  def up
    safety_assured do
      execute <<~SQL
        DELETE FROM posts WHERE postable_type = 'Post::ShipDecision'
      SQL
    end
  end

  def down
    # The deleted rows were derived from certification_ship_reviews and
    # carry no information of their own; nothing to restore.
  end
end
