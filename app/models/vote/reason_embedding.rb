# == Schema Information
#
# Table name: vote_reason_embeddings
# Database name: primary
#
#  id            :bigint           not null, primary key
#  embedding     :vector(1536)     not null
#  model_version :string           default("text-embedding-3-small"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  vote_id       :bigint           not null
#
# Indexes
#
#  index_vote_reason_embeddings_on_vote_id  (vote_id) UNIQUE
#
class Vote::ReasonEmbedding < EmbeddingsRecord
  self.table_name = "vote_reason_embeddings"

  has_neighbors :embedding, dimensions: 1536

  EMBED_MODEL = "text-embedding-3-small"
  EMBED_DIM = 1536
end
