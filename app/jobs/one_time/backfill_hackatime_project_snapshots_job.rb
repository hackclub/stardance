# Recovers snapshot metadata only, never durations or payouts.
class OneTime::BackfillHackatimeProjectSnapshotsJob < ApplicationJob
  queue_as :literally_whenever
  self.enqueue_after_transaction_commit = true

  def perform(project_ids: nil)
    devlogs = Post::Devlog.unscoped.where(hackatime_project_names_snapshot: nil)
    devlogs = devlogs.joins(:post).where(posts: { project_id: project_ids }) unless project_ids.nil?
    result = { updated: 0, unresolved: 0 }

    devlogs.find_each do |devlog|
      devlog.with_lock do
        # A resync or another backfill may have populated it since selection.
        next unless devlog.hackatime_project_names_snapshot.nil?

        names = devlog.hackatime_project_names
        if names.nil?
          result[:unresolved] += 1
          Rails.logger.info "[BackfillHackatimeProjectSnapshots] unresolved devlog_id=#{devlog.id}"
          next
        end

        # Avoid touch/callbacks: this does not change the credited-time basis.
        devlog.update_columns(hackatime_project_names_snapshot: names)
        PaperTrail::Version.create!(
          item_type: "Post::Devlog", item_id: devlog.id,
          event: "hackatime_snapshot_backfill", whodunnit: self.class.name,
          object_changes: { "hackatime_project_names_snapshot" => [ nil, names ] }.to_yaml
        )
        result[:updated] += 1
      end
    end

    Rails.logger.info "[BackfillHackatimeProjectSnapshots] #{result.inspect}"
    result
  end
end
