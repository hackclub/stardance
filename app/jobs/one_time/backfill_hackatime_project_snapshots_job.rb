# Recovers snapshot metadata only, never durations or payouts. Run the dry run
# first, inspect unresolved devlog IDs, then opt in with dry_run: false.
class OneTime::BackfillHackatimeProjectSnapshotsJob < ApplicationJob
  queue_as :literally_whenever

  def perform(dry_run: true, project_ids: nil)
    devlogs = Post::Devlog.unscoped.where(hackatime_project_names_snapshot: nil)
    devlogs = devlogs.joins(:post).where(posts: { project_id: project_ids }) unless project_ids.nil?
    result = { candidates: [], updated: [], unresolved: [] }

    devlogs.find_each do |devlog|
      devlog.with_lock do
        # A resync or another backfill may have populated it since selection.
        next unless devlog.hackatime_project_names_snapshot.nil?

        names = devlog.hackatime_project_names
        if names.nil?
          result[:unresolved] << devlog.id
          next
        end

        result[:candidates] << devlog.id
        next if dry_run

        # Avoid touch/callbacks: this does not change the credited-time basis.
        devlog.update_columns(hackatime_project_names_snapshot: names)
        PaperTrail::Version.create!(
          item_type: "Post::Devlog", item_id: devlog.id,
          event: "hackatime_snapshot_backfill", whodunnit: self.class.name,
          object_changes: { "hackatime_project_names_snapshot" => [ nil, names ] }.to_yaml
        )
        result[:updated] << devlog.id
      end
    end

    Rails.logger.info "[BackfillHackatimeProjectSnapshots] #{dry_run ? 'DRY RUN' : 'APPLY'} #{result.inspect}"
    result
  end
end
