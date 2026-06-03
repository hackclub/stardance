# == Schema Information
#
# Table name: devlog_lookout_sessions
#
#  id                 :bigint           not null, primary key
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  devlog_id          :bigint           not null
#  lookout_session_id :bigint           not null
#
# Indexes
#
#  idx_devlog_lookout_sessions_unique                   (devlog_id,lookout_session_id) UNIQUE
#  index_devlog_lookout_sessions_on_devlog_id           (devlog_id)
#  index_devlog_lookout_sessions_on_lookout_session_id  (lookout_session_id)
#
# Foreign Keys
#
#  fk_rails_...  (devlog_id => post_devlogs.id)
#  fk_rails_...  (lookout_session_id => lookout_sessions.id)
#
# Join row linking a devlog to a Lookout recording session used as provenance
# for that devlog (which screen recordings back it). Time still comes from
# Hackatime — this is not used for duration.
class DevlogLookoutSession < ApplicationRecord
  belongs_to :devlog, class_name: "Post::Devlog"
  belongs_to :lookout_session

  validates :lookout_session_id, uniqueness: { scope: :devlog_id }
end
