# == Schema Information
#
# Table name: posts
#
#  id            :bigint           not null, primary key
#  postable_type :string
#  reposts_count :integer          default(0), not null
#  views_count   :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  postable_id   :bigint
#  project_id    :bigint
#  user_id       :bigint
#
# Indexes
#
#  index_posts_on_postable_type_and_postable_id  (postable_type,postable_id) UNIQUE
#  index_posts_on_project_id                     (project_id)
#  index_posts_on_user_id                        (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (user_id => users.id)
#
class Post < ApplicationRecord
    include Gorse::SyncablePost

    has_paper_trail

    # Eager load all Post::* classes so Postable.types is populated
    Dir[Rails.root.join("app/models/post/*.rb")].each { |f| require_dependency f }

    belongs_to :project, optional: true, touch: true
    # optional because it can be a system post – achievements, milestones, well-done/magic happening, etc –
    # integeration – git remotes – or a user post
    belongs_to :user, optional: true

    delegated_type :postable, types: Postable.types

    has_many :post_views, dependent: :delete_all

    validates :postable_id, presence: true, if: :postable_type?
    validates :project, presence: true, unless: :repost?

    after_create { postable.capture_hours_at_ship if postable_type == "Post::ShipEvent" }
    after_commit :increment_devlogs_count, on: :create
    after_commit :decrement_devlogs_count, on: :destroy
    after_commit :update_project_duration_seconds, on: [ :create, :destroy ]
    after_commit :enqueue_postable_semantic_search_index, on: %i[create update]
    after_commit :enqueue_postable_semantic_search_delete, on: :destroy

    Postable.types.each do |type_class|
      # These are automatically generated scopes for each postable type:
      # ie. Post.of_devlogs
      # ie. Post.of_devlogs(join: true).where(post_devlogs: { tutorial: false })

      scope_name = "of_#{type_class.demodulize.underscore.pluralize}"
      table_name = type_class.constantize.table_name

      define_singleton_method(scope_name) do |join: false|
        scope = where(postable_type: type_class)
        scope = scope.joins("INNER JOIN #{table_name} ON posts.postable_id = #{table_name}.id") if join
        scope
      end

      # Also define a belongs_to for each type so we can eager load without polymorphic errors.
      # Use: Post.of_devlogs.includes(devlog: { attachments_attachments: :blob })
      belongs_to type_class.demodulize.underscore.to_sym,
                 class_name: type_class,
                 foreign_key: :postable_id,
                 optional: true
    end

    # Restrict to posts whose author has finished identity verification.
    # System posts (user_id IS NULL) are always allowed through — they aren't
    # user-authored. The viewer-aware variant additionally lets a logged-in
    # user see their own posts even before they verify, and short-circuits to
    # `all` for admins (who can see everything).
    scope :authored_by_verified, -> {
      left_outer_joins(:user)
        .where("posts.user_id IS NULL OR users.verification_status = 'verified'")
    }

    def self.visible_to(viewer)
      return all if viewer&.admin?

      scope = left_outer_joins(:user)
      if viewer.present?
        scope.where(
          "posts.user_id IS NULL OR posts.user_id = ? OR users.verification_status = 'verified'",
          viewer.id
        )
      else
        scope.where("posts.user_id IS NULL OR users.verification_status = 'verified'")
      end
    end

    def repost?
      postable_type == "Post::Repost"
    end

    # Reposts surface the original post's content, so a view of the repost
    # also counts as a unique view of the original.
    def view_credited_posts
      [ self, repost? ? postable&.original_post : nil ].compact
    end

    def visible_repost_original_for?(viewer)
      if repost?
        original_post = postable&.original_post

        original_post&.postable_type == "Post::Devlog" &&
          original_post.postable.present? &&
          !original_post.postable.deleted? &&
          Post.visible_to(viewer).where(id: original_post.id).exists?
      else
        false
      end
    end

    private

    def increment_devlogs_count
      return unless postable_type == "Post::Devlog"

      Project.unscoped.where(id: project_id).update_counters(devlogs_count: 1)
    end

    def decrement_devlogs_count
      return unless postable_type == "Post::Devlog"

      Project.unscoped.where(id: project_id).update_counters(devlogs_count: -1)
    end

    def update_project_duration_seconds
      return unless postable_type == "Post::Devlog"

      project&.recalculate_duration_seconds!
    end

    def enqueue_postable_semantic_search_index
      return unless %w[Post::Devlog Post::ShipEvent].include?(postable_type)
      return unless postable_id

      SemanticSearch::IndexRecordJob.perform_later(postable_type, postable_id)
    end

    def enqueue_postable_semantic_search_delete
      type = { "Post::Devlog" => "devlog", "Post::ShipEvent" => "ship" }[postable_type]
      return unless type && postable_id

      SemanticSearch::DeleteRecordJob.perform_later(type, postable_id)
    end
end
