require "test_helper"

class Airtable::WorkshopRsvpSyncJobTest < ActiveJob::TestCase
  FakeRecord = Struct.new(:fields, :patches) do
    def [](field)
      fields[field]
    end

    def patch(attributes)
      patches << attributes
      fields.merge!(attributes)
    end
  end

  FakeTable = Struct.new(:records, :created, :filters) do
    def all(filter:)
      filters << filter
      records
    end

    def create(attributes)
      created << attributes
    end
  end

  setup do
    @user = users(:one)
    @workshop = workshops(:upcoming)
    @job = Airtable::WorkshopRsvpSyncJob.new
  end

  test "appends the dated workshop name to an existing email record" do
    record = FakeRecord.new(
      {
        "Email" => @user.email,
        "Loops List - stardanceWorkshops" => "generated-value",
        "Loops - stardanceWorkshopSignUpNames" => "Soldering basics 2026-07-20"
      },
      []
    )
    table = FakeTable.new([ record ], [], [])

    @job.stub(:table, table) do
      @job.perform(@user.id, @workshop.id)
    end

    expected_signup = "#{@workshop.title} #{@workshop.starts_at.in_time_zone(Workshop::TIME_ZONE).to_date.iso8601}"
    assert_equal(
      [ { "Loops - stardanceWorkshopSignUpNames" => "Soldering basics 2026-07-20, #{expected_signup}" } ],
      record.patches
    )
    assert_equal "generated-value", record["Loops List - stardanceWorkshops"]
    assert_empty table.created
  end

  test "does not add a workshop more than once" do
    signup = "#{@workshop.title} #{@workshop.starts_at.in_time_zone(Workshop::TIME_ZONE).to_date.iso8601}"
    record = FakeRecord.new(
      { "Loops - stardanceWorkshopSignUpNames" => "#{signup}, #{signup.downcase}" },
      []
    )
    table = FakeTable.new([ record ], [], [])

    @job.stub(:table, table) do
      @job.perform(@user.id, @workshop.id)
    end

    assert_equal [ { "Loops - stardanceWorkshopSignUpNames" => signup } ], record.patches
  end

  test "does not patch Airtable when the workshop is already present once" do
    signup = "#{@workshop.title} #{@workshop.starts_at.in_time_zone(Workshop::TIME_ZONE).to_date.iso8601}"
    record = FakeRecord.new({ "Loops - stardanceWorkshopSignUpNames" => signup }, [])
    table = FakeTable.new([ record ], [], [])

    @job.stub(:table, table) do
      @job.perform(@user.id, @workshop.id)
    end

    assert_empty record.patches
    assert_empty table.created
  end

  test "creates an email record without writing the generated Loops list field" do
    table = FakeTable.new([], [], [])

    @job.stub(:table, table) do
      @job.perform(@user.id, @workshop.id)
    end

    signup = "#{@workshop.title} #{@workshop.starts_at.in_time_zone(Workshop::TIME_ZONE).to_date.iso8601}"
    assert_equal(
      [
        {
          "Email" => @user.email.downcase.strip,
          "Loops - stardanceWorkshopSignUpNames" => signup
        }
      ],
      table.created
    )
  end

  test "escapes the normalized email in the Airtable lookup formula" do
    @user.update!(email: "STAR'GAZER@EXAMPLE.COM")
    table = FakeTable.new([], [], [])

    @job.stub(:table, table) do
      @job.perform(@user.id, @workshop.id)
    end

    assert_equal "LOWER({Email}) = 'star\\'gazer@example.com'", table.filters.first
  end
end
