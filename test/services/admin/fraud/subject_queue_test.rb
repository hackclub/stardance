require "test_helper"

# The order a fraud reviewer works people in. Flags outrank shop orders outrank
# integrity checks, because the first two hold up something the person can see
# happening to them and the third does not.
class Admin::Fraud::SubjectQueueTest < ActiveSupport::TestCase
  include UserFactory

  PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=".freeze

  setup do
    @reporter = create_user(slack_id: "u-reporter", display_name: "reporter")
  end

  test "a fresher flag outranks an older integrity check" do
    flagged = user_with_flag(age: 10.days.ago)
    checked = user_with_integrity(age: 25.days.ago)

    assert_equal [ flagged.id, checked.id ], ranked_ids
  end

  test "a shop order outranks an integrity check of the same age" do
    ordered = user_with_order(age: 5.days.ago)
    checked = user_with_integrity(age: 5.days.ago)

    assert_equal [ ordered.id, checked.id ], ranked_ids
  end

  test "priority is the single highest scoring item, not the sum" do
    one_old_flag = user_with_flag(age: 20.days.ago)
    many_fresh_checks = create_user(slack_id: "u-many", display_name: "many")
    5.times { pending_integrity_for(many_fresh_checks, age: 1.day.ago) }

    assert_equal [ one_old_flag.id, many_fresh_checks.id ], ranked_ids
  end

  test "counts each source separately for one person" do
    user = user_with_flag(age: 3.days.ago)
    user.update!(has_gotten_free_stickers: true) # clears the shop-tutorial gate
    order_for(user, age: 2.days.ago)
    pending_integrity_for(user, age: 1.day.ago)

    subject = subjects.sole

    assert_equal user.id, subject.user_id
    assert_equal [ 1, 1, 1 ], [ subject.flag_count, subject.order_count, subject.integrity_count ]
    assert_equal 3, subject.item_count
  end

  test "leaves out quality reports, buyer-side orders, decided checks and banned people" do
    user_with_flag(age: 1.day.ago, reason: "low_effort")
    user_with_order(age: 1.day.ago, state: "awaiting_verification")
    user_with_integrity(age: 1.day.ago, status: :auto_passed)
    user_with_flag(age: 1.day.ago, display_name: "gone").update!(banned: true)

    assert_empty subjects
  end

  test "a flag on a team project surfaces every member" do
    owner = create_user(slack_id: "u-owner", display_name: "owner")
    teammate = create_user(slack_id: "u-mate", display_name: "mate")
    project = Project.create!(title: "Team #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: owner, role: :owner)
    Project::Membership.create!(project: project, user: teammate, role: :contributor)
    flag_for(project, age: 1.day.ago)

    assert_equal [ owner.id, teammate.id ].sort, ranked_ids.sort
  end

  test "a person another reviewer is holding drops off the queue" do
    held = user_with_flag(age: 10.days.ago, display_name: "held")
    open = user_with_flag(age: 5.days.ago, display_name: "open")
    holder = create_user(slack_id: "u-holder", display_name: "holder")
    looker = create_user(slack_id: "u-looker", display_name: "looker")
    FraudSubjectClaim.claim(held, holder)

    assert_equal [ open.id ], ranked_ids_for(looker)
    assert_equal [ held.id, open.id ], ranked_ids, "the unfiltered queue still has both"
  end

  test "a reviewer still sees the person they are holding themselves" do
    mine = user_with_flag(age: 10.days.ago, display_name: "mine")
    reviewer = create_user(slack_id: "u-mine", display_name: "minereviewer")
    FraudSubjectClaim.claim(mine, reviewer)

    assert_equal [ mine.id ], ranked_ids_for(reviewer)
  end

  test "a lapsed claim puts the person back on the queue" do
    lapsed = user_with_flag(age: 10.days.ago, display_name: "lapsed")
    holder = create_user(slack_id: "u-lapsed-holder", display_name: "lapsedholder")
    looker = create_user(slack_id: "u-lapsed-looker", display_name: "lapsedlooker")
    claim = FraudSubjectClaim.claim(lapsed, holder)
    claim.update_columns(claimed_at: (FraudSubjectClaim::CLAIM_TTL + 1.minute).ago)

    assert_equal [ lapsed.id ], ranked_ids_for(looker)
  end

  test "the next person skips both the one just finished and anyone held" do
    finished = user_with_flag(age: 30.days.ago, display_name: "finished")
    held = user_with_flag(age: 20.days.ago, display_name: "nextheld")
    up_next = user_with_flag(age: 10.days.ago, display_name: "upnext")
    reviewer = create_user(slack_id: "u-next", display_name: "nextreviewer")
    holder = create_user(slack_id: "u-next-holder", display_name: "nextholder")
    FraudSubjectClaim.claim(held, holder)

    assert_equal up_next.id,
                 Admin::Fraud::SubjectQueue.next_subject_id(reviewer: reviewer, after: finished)
  end

  private

  def subjects = Admin::Fraud::SubjectQueue.subjects

  def ranked_ids_for(reviewer) = Admin::Fraud::SubjectQueue.subjects_for(reviewer).map(&:user_id)

  def ranked_ids = subjects.map(&:user_id)

  def user_with_flag(age:, reason: "fraud", display_name: "flagged")
    user = create_user(slack_id: "u-#{SecureRandom.hex(3)}", display_name: display_name)
    project = Project.create!(title: "Flagged #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: user, role: :owner)
    flag_for(project, age: age, reason: reason)
    user
  end

  def flag_for(project, age:, reason: "fraud")
    report = Project::Report.create!(project: project, reporter: @reporter, reason: reason,
                                     details: "Detailed enough to pass validation", status: :pending)
    report.update_column(:created_at, age)
    report
  end

  def user_with_order(age:, state: "pending")
    user = create_user(slack_id: "u-#{SecureRandom.hex(3)}", display_name: "buyer")
    user.update!(has_gotten_free_stickers: true) # clears the shop-tutorial gate
    order_for(user, age: age, state: state)
    user
  end

  def order_for(user, age:, state: "pending")
    order = user.shop_orders.create!(shop_item: shop_item, quantity: 1, frozen_address: { "country" => "US" })
    order.update_columns(aasm_state: state, created_at: age)
    order
  end

  def user_with_integrity(age:, status: :pending)
    user = create_user(slack_id: "u-#{SecureRandom.hex(3)}", display_name: "shipper")
    pending_integrity_for(user, age: age, status: status)
    user
  end

  def pending_integrity_for(user, age:, status: :pending)
    project = Project.create!(title: "Shipped #{SecureRandom.hex(4)}")
    Project::Membership.create!(project: project, user: user, role: :owner)
    ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true)
    Post.create!(project: project, user: user, postable: ship_event)
    check = Certification::Integrity.create!(ship_event: ship_event, status: status)
    check.update_column(:created_at, age)
    check
  end

  def shop_item
    @shop_item ||= begin
      item = ShopItem.new(name: "Patch #{SecureRandom.hex(4)}", description: "A cheap physical item",
                          ticket_cost: 0, usd_cost: 7, type: "ShopItem::ThirdPartyPhysical", enabled: true)
      item.image.attach(io: StringIO.new(Base64.decode64(PIXEL)), filename: "px.png", content_type: "image/png")
      item.save!
      item
    end
  end
end
