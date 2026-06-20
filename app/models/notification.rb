# == Schema Information
#
# Table name: notifications
#
#  id                 :bigint           not null, primary key
#  email_delivered_at :datetime
#  group_count        :integer          default(1), not null
#  group_key          :string
#  params             :jsonb            not null
#  priority           :integer          default(NULL), not null
#  read_at            :datetime
#  record_type        :string
#  seen_at            :datetime
#  slack_enqueued_at  :datetime
#  type               :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  actor_id           :bigint
#  recipient_id       :bigint           not null
#  record_id          :bigint
#
# Indexes
#
#  index_notifications_on_actor_id                                (actor_id)
#  index_notifications_on_recipient_id                            (recipient_id)
#  index_notifications_on_recipient_id_and_created_at             (recipient_id,created_at)
#  index_notifications_on_recipient_id_and_group_key_and_read_at  (recipient_id,group_key,read_at) WHERE (group_key IS NOT NULL)
#  index_notifications_on_recipient_id_and_seen_at                (recipient_id,seen_at)
#  index_notifications_on_record_type_and_record_id               (record_type,record_id)
#  index_notifications_on_type_and_created_at                     (type,created_at)
#  index_notifications_unique_unread_aggregate                    (recipient_id,type,group_key) UNIQUE WHERE ((read_at IS NULL) AND (group_key IS NOT NULL))
#
# Foreign Keys
#
#  fk_rails_...  (actor_id => users.id) ON DELETE => nullify
#  fk_rails_...  (recipient_id => users.id) ON DELETE => cascade
#
class Notification < ApplicationRecord
  PRIORITY_CHANNEL_DEFAULTS = {
    "low"      => { slack: false, email: false },
    "medium"   => { slack: false, email: false },
    "high"     => { slack: true,  email: true  },
    "critical" => { slack: true,  email: true  }
  }.freeze

  # Strips Slack broadcast/group mentions so user-authored content can't ping
  # @channel/@here when re-rendered into a Slack DM.
  SLACK_MENTION_PATTERN = /<!(?:here|channel|everyone|subteam\^[A-Z0-9]+)(?:\|[^>]+)?>|@(?:here|channel|everyone)/i

  class_attribute :default_priority,     default: :low
  class_attribute :slack_template_path,  default: nil
  class_attribute :aggregatable,         default: false
  class_attribute :allow_self_notify,    default: false
  class_attribute :category_key,         default: nil
  class_attribute :category_label,       default: nil
  class_attribute :category_description, default: nil
  class_attribute :category_group,       default: "General"
  class_attribute :inbox_record_preloads, default: nil
  # Delay for slack/email delivery so aggregated rows fire one DM/email with
  # the final group_count instead of one per event. nil = immediate.
  class_attribute :digest_delay,         default: nil

  enum :priority, { low: 0, medium: 1, high: 2, critical: 3 }, validate: true
  # Override the column default of 0 (=low) so apply_default_priority's `||=`
  # can actually assign each subclass's declared default. Without this, new
  # records arrive at the callback already set to "low" and never upgrade.
  attribute :priority, default: nil

  belongs_to :recipient, class_name: "User"
  belongs_to :actor,     class_name: "User", optional: true
  belongs_to :record,    polymorphic: true,  optional: true

  after_initialize :apply_default_priority, if: :new_record?

  scope :unseen, -> { where(seen_at: nil) }
  scope :unread, -> { where(read_at: nil) }

  # The whole notifications feature (in-app, Slack, email) is behind the
  # week_2_release flag, gated per recipient.
  def self.enabled_for?(user)
    user.present? && Flipper.enabled?(:week_2_release, user)
  end

  def self.notify(recipient:, actor: nil, record: nil, params: {}, priority: nil)
    return nil if recipient.nil?
    return nil unless enabled_for?(recipient)
    # Graceful no-op when the notifications table hasn't been migrated in yet
    # (e.g. a teammate still on an older schema, or a shared dev DB mid-rollout).
    # Lets callers fire notifications without crashing on un-migrated databases;
    # table_exists? is answered from the cached schema, so this is cheap.
    return nil unless table_exists?
    return nil if actor && actor.id == recipient.id && !allow_self_notify

    notification = nil
    attempts = 0

    begin
      attempts += 1
      transaction do
        notification = aggregate_or_build(recipient: recipient, actor: actor, record: record, params: params)
        notification.priority = priority if priority
        notification.save!
      end
    rescue ActiveRecord::RecordNotUnique
      # Race: another notify call inserted the aggregate row between our
      # lookup and insert. Retry once — the second pass finds the row that
      # the racing call created and merges into it instead.
      retry if attempts < 2
      raise
    end

    enqueue_deliveries(notification)
    # previously_new_record? is false when aggregate_or_build merged into an
    # existing row (no new INSERT); true when this notify spawned a fresh row.
    BroadcastNotificationJob.perform_later(notification.id, aggregated: !notification.previously_new_record?)
    notification
  end

  def self.aggregate_or_build(recipient:, actor:, record:, params:)
    if aggregatable
      existing = recipient.notifications
        .where(type: name, group_key: build_group_key(recipient: recipient, actor: actor, record: record, params: params), read_at: nil)
        .order(created_at: :desc)
        .lock
        .first

      if existing
        existing.merge_aggregated_actor!(actor)
        return existing
      end
    end

    seeded_params = actor && aggregatable ? (params || {}).merge("actor_ids" => [ actor.id ]) : params

    new(
      recipient: recipient,
      actor: actor,
      record: record,
      params: seeded_params,
      group_key: aggregatable ? build_group_key(recipient: recipient, actor: actor, record: record, params: params) : nil
    )
  end

  def self.build_group_key(recipient:, actor:, record:, params:)
    nil
  end

  def self.enqueue_deliveries(notification)
    notification.effective_channels.each do |channel|
      if digest_delay
        NotificationDeliveryJob.set(wait: digest_delay).perform_later(notification.id, channel.to_s)
      else
        NotificationDeliveryJob.perform_later(notification.id, channel.to_s)
      end
    end
  end

  def self.inbox_for(user)
    scope = user.notifications.order(created_at: :desc)
    hidden = in_app_disabled_types_for(user)
    hidden.any? ? scope.where.not(type: hidden) : scope
  end

  # Unread count for the sidebar badge. Seen and read are one state — a row is
  # unread until the user opens the inbox (or reads it) — so the badge shows
  # how many notifications are still new. Respects the in-app ("Notification
  # tab") preference so the badge and the inbox agree. Single source of truth
  # shared by the component and the realtime broadcasts.
  def self.unread_count_for(user)
    scope = user.notifications.unread
    hidden = in_app_disabled_types_for(user)
    scope = scope.where.not(type: hidden) if hidden.any?
    scope.count
  end

  # Notification type names the user has switched OFF for the in-app inbox.
  # Critical types are never hideable; a nil/true preference stays visible.
  def self.in_app_disabled_types_for(user)
    return [] unless User::NotificationPreference.column_names.include?("in_app_enabled")

    prefs = user.notification_preferences.index_by(&:category)
    Notifications::Registry.all.select do |klass|
      next false if klass.default_priority.to_s == "critical"

      pref = prefs[klass.category_key.to_s]
      pref && pref.in_app_enabled == false
    end.map(&:name)
  end

  # Conditionally preload polymorphic records + their chains per notification
  # type so we don't pay for `:record` loads on types that don't use them,
  # and so types that need a deeper chain (e.g. Devlog#post#project) don't N+1.
  #
  # inbox_record_preloads contract per subclass:
  #   nil   - skip record load entirely (record_id is nil or partial doesn't use it)
  #   []    - load :record only
  #   spec  - load :record plus this chain (symbol, array, or hash) on the record
  def self.preload_inbox_records!(notifications)
    notifications.group_by(&:class).each do |klass, group|
      spec = klass.inbox_record_preloads
      next if spec.nil?
      next if group.empty?

      associations = spec.is_a?(Array) && spec.empty? ? :record : { record: spec }

      ActiveRecord::Associations::Preloader.new(
        records: group,
        associations: associations
      ).call
    end
  end

  def effective_channels
    defaults = PRIORITY_CHANNEL_DEFAULTS.fetch(priority.to_s)
    pref = preference_row

    slack_on = critical? || channel_enabled?(:slack, pref, defaults)
    email_on = critical? || channel_enabled?(:email, pref, defaults)

    channels = []
    channels << :slack if slack_on
    channels << :email if email_on
    channels
  end

  def merge_aggregated_actor!(actor)
    self.group_count = (group_count || 1) + 1
    if actor
      self.actor = actor
      # Remember every distinct actor (capped) so the inbox can expand the
      # "and N others" line into who exactly is behind the aggregate.
      self.params = params.merge("actor_ids" => (aggregated_actor_ids + [ actor.id ]).uniq.last(50))
    end
    self.updated_at = Time.current
    # Resurface as fully unseen/unread — a new actor means there's something
    # new to look at, even if the user had already read the previous version.
    self.seen_at = nil
    self.read_at = nil
    save!
  end

  def aggregated_actor_ids
    Array(params["actor_ids"]).map(&:to_i)
  end

  # Distinct actors behind an aggregated notification, most recent first, for
  # the inbox "and N others" expander. Falls back to the single stored actor
  # when no list was recorded (older rows / non-aggregated types).
  def aggregated_actors
    ids = aggregated_actor_ids
    return [ actor ].compact if ids.empty?

    by_id = User.where(id: ids).index_by(&:id)
    ids.reverse.filter_map { |id| by_id[id] }
  end

  def orphaned?
    record_type.present? && record_id.present? && record.nil?
  end

  def template_key
    self.class.name.demodulize.underscore
  end

  def inbox_partial
    "notifications/inbox/#{template_key}"
  end

  def preview_text
    nil
  end

  # Deep link for the preview text, when the preview itself is a jump target
  # (e.g. a comment body that links to that comment in the devlog). nil = the
  # preview is plain, non-clickable text.
  def preview_path
    nil
  end

  def slack_payload
    {
      message: slack_message,
      blocks_path: self.class.slack_template_path,
      locals: slack_locals
    }
  end

  def slack_message
    nil
  end

  def slack_locals
    {}
  end

  def email_subject
    "Stardance notification"
  end

  def sanitize_slack_mentions(text)
    text.to_s.gsub(SLACK_MENTION_PATTERN, "")
  end

  private

  def preference_row
    key = self.class.category_key
    return nil if key.nil? || recipient.nil?

    recipient.notification_preferences.find_by(category: key.to_s)
  end

  def channel_enabled?(channel, pref, defaults)
    column = "#{channel}_enabled"
    if pref && !pref[column].nil?
      pref[column]
    else
      defaults[channel]
    end
  end

  def apply_default_priority
    self.priority ||= self.class.default_priority
  end
end
