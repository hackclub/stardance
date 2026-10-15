require "test_helper"

class Privacy::EraserTest < ActiveSupport::TestCase
  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    @user = create_user(slack_id: "U_ERASE_ME", display_name: "erase-me", verified: true)
    @user.update!(hcb_email: "Grants@Example.test", first_name: "Era", last_name: "Sure", bio: "hi", internal_notes: "note", has_gotten_free_stickers: true)
    @other = create_user(slack_id: "U_ERASE_KEEP", display_name: "keep-me", verified: true)

    @solo = create_project("Solo rover", @user)
    @solo_devlog = create_devlog(@solo, @user)
    @shared = create_project("Shared rover", @user, @other)
    @their_shared_devlog = create_devlog(@shared, @user)
    @others_devlog = create_devlog(@shared, @other)
    Like.create!(user: @user, likeable: @others_devlog)
    Comment.create!(user: @user, commentable: @others_devlog, body: "nice")
    Comment.create!(user: @other, commentable: @solo_devlog, body: "cool")
    Follow.create!(follower: @other, followed: @user)
    @quote = Post::Repost.create!(user: @other, original_post: @solo_devlog.post, body: "look at this")
    Post::Repost.create!(user: @user, original_post: @others_devlog.post)

    @user.banner.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "banner.png", content_type: "image/png")
    @banner_key = @user.banner.blob.key

    @user.ledger_entries.create!(ledgerable: @user, amount: 50, reason: "Grant", created_by: "Erase Me (#{@user.id})")
    item = build_item
    @open_order = @user.shop_orders.create!(shop_item: item, quantity: 1, frozen_address: { "country" => "US" })
    @fulfilled_order = @user.shop_orders.create!(shop_item: item, quantity: 1, frozen_address: { "country" => "US" })
    @fulfilled_order.update_columns(aasm_state: "fulfilled")
  end

  test "finds people by any email, Slack ID or Hack Club identity, and nobody else" do
    assert_equal [ @user.id ], eraser(emails: [ "grants@example.test" ]).user_ids
    assert_equal [ @user.id ], eraser(slack_id: "U_ERASE_ME").user_ids
    assert_equal [ @user.id ], eraser(identity_id: "hca-U_ERASE_ME").user_ids
    assert_empty eraser(emails: [ "nobody@example.test" ]).user_ids
  end

  test "erases personal data and keeps what other people depend on" do
    result = eraser(emails: [ "erase-me@example.test" ]).call(dry_run: false, request_id: "req-1")

    assert result.found
    @user.reload
    assert_nil @user.email
    assert_nil @user.hcb_email
    assert_nil @user.slack_id
    assert_nil @user.first_name
    assert_nil @user.internal_notes
    assert_equal "deleted-user-#{@user.id}", @user.display_name
    assert_empty @user.identities
    assert_not @user.banner.attached?
    assert_not ActiveStorage::Blob.service.exist?(@banner_key)

    # the solo project stays as a hidden placeholder
    solo = Project.unscoped.find(@solo.id)
    assert_equal "Deleted project", solo.title
    assert_not_nil solo.deleted_at
    assert_not Post::Devlog.unscoped.exists?(@solo_devlog.id)

    # the shared project loses only their membership and their posts, and is recounted
    @shared.reload
    assert_equal [ @other.id ], @shared.memberships.pluck(:user_id)
    assert_equal 1, @shared.memberships_count
    assert_equal 1, @shared.devlogs_count
    assert_not Post::Devlog.unscoped.exists?(@their_shared_devlog.id)
    @others_devlog.reload
    assert_equal 0, @others_devlog.likes_count
    assert_equal 0, @others_devlog.comments_count
    assert_not Follow.exists?(followed_id: @user.id)
    assert_not Post::Repost.unscoped.exists?(@quote.id)
    assert_equal 0, @others_devlog.post.reload.reposts_count

    # money stays, open work is closed
    assert_equal 1, LedgerEntry.where(user_id: @user.id).count
    assert_equal "Deleted user (#{@user.id})", LedgerEntry.find_by(user_id: @user.id).created_by
    assert_equal "rejected", @open_order.reload.aasm_state
    assert_equal "fulfilled", @fulfilled_order.reload.aasm_state

    # history that copied their data goes; the ledger's audit trail and the erasure record stay
    assert_equal %w[balance_adjustment privacy_erasure], PaperTrail::Version.where(item_type: "User", item_id: @user.id.to_s).order(:created_at).pluck(:event)

    assert_equal 1, result.deleted["user_identities"]
    assert_equal 2, result.deleted["post_devlogs"]
    assert_equal 1, result.deleted["active_storage_blobs"]
    retained = result.retained.index_by { |entry| entry[:type] }
    assert_equal 2, retained["shop orders"][:count]
    assert_equal 1, retained["cancelled shop orders"][:count]
    assert_equal 1, retained["projects"][:count]
  end

  test "a dry run reports exactly what the real run removes, and changes nothing" do
    before = database_fingerprint
    dry = eraser(slack_id: "U_ERASE_ME").call(dry_run: true, request_id: "req-dry")

    assert_equal before, database_fingerprint
    assert ActiveStorage::Blob.service.exist?(@banner_key)

    real = eraser(slack_id: "U_ERASE_ME").call(dry_run: false, request_id: "req-real")

    assert_equal dry.deleted, real.deleted
    assert_equal dry.retained, real.retained
  end

  test "once erased the person is no longer found" do
    eraser(slack_id: "U_ERASE_ME").call(dry_run: false, request_id: "req-1")

    assert_not eraser(emails: [ "erase-me@example.test" ], slack_id: "U_ERASE_ME", identity_id: "hca-U_ERASE_ME").call(dry_run: true, request_id: "req-2").found
  end

  test "a storage failure rolls everything back so the hub can retry" do
    failing = ->(*) { raise Errno::ECONNRESET }

    ActiveStorage::Blob.service.stub(:delete, failing) do
      assert_raises(Privacy::Eraser::DependencyUnavailable) do
        eraser(slack_id: "U_ERASE_ME").call(dry_run: false, request_id: "req-1")
      end
    end

    assert_equal "U_ERASE_ME", @user.reload.slack_id
    assert @user.banner.attached?
    assert ActiveStorage::Blob.service.exist?(@banner_key)
  end

  test "staff and sellers need a human" do
    assert_not eraser(slack_id: "U_ERASE_ME").manual_review_required?

    @user.grant_role!(:admin)

    assert eraser(slack_id: "U_ERASE_ME").manual_review_required?
  end

  [ :configuration, :feature_flag ].each do |disabled_by|
    test "skips configured Gorse when disabled by #{disabled_by}" do
      config = ActiveSupport::OrderedOptions.new
      config.endpoint = "https://gorse.example.test"
      config.enabled = disabled_by != :configuration
      Flipper.enable(:gorse_recommendations) if disabled_by == :configuration
      Flipper.disable(:gorse_recommendations) if disabled_by == :feature_flag

      Gorse.stub(:config, -> { config }) do
        Gorse::Client.stub(:new, ->(*) { flunk "Disabled Gorse must not be contacted" }) do
          result = eraser(slack_id: "U_ERASE_ME").call(dry_run: false, request_id: "req-disabled-gorse")

          assert result.found
          assert_nil @user.reload.slack_id
          assert_empty @user.identities
        end
      end
    end
  end

  private

  def eraser(emails: [], slack_id: nil, identity_id: nil)
    Privacy::Eraser.new(Privacy::Token::Subject.new(emails:, slack_id:, identity_id:))
  end

  def create_project(title, *members)
    project = Project.create!(title:)
    members.each { |member| project.memberships.create!(user: member, role: :owner) }
    project
  end

  def create_devlog(project, user)
    devlog = Post::Devlog.new(body: "log by #{user.display_name}", duration_seconds: 3600)
    devlog.uploading_attachments = true
    devlog.save!
    Post.create!(project:, user:, postable: devlog)
    devlog
  end

  def build_item
    item = ShopItem.new(name: "Patch #{SecureRandom.hex(4)}", description: "A patch", ticket_cost: 0, usd_cost: 7,
                        type: "ShopItem::ThirdPartyPhysical", enabled: true)
    item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
    item.save!
    item
  end

  # every row of every table, so a dry run can prove it left the database exactly as it was
  def database_fingerprint
    connection = ActiveRecord::Base.connection
    connection.tables.grep_v(/\A(schema_migrations|ar_internal_metadata|solid_)/).sort.index_with do |table|
      connection.select_value("SELECT md5(coalesce(string_agg(t::text, ',' ORDER BY t::text), '')) FROM #{connection.quote_table_name(table)} t")
    end
  end
end
