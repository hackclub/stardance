require "test_helper"

class SidebarLogoTest < ActionDispatch::IntegrationTest
  setup { Flipper.disable(:ddr) }
  teardown { Flipper.disable(:ddr) }

  test "default sidebar keeps the Stardance logo" do
    get home_path
    assert_response :success
    assert_select "img.sidebar__logo-img[alt='Hack Club Stardance Challenge'][src*='stardance-logo']", count: 1
  end

  test "globally enabled DDR logo is visible to guests" do
    Flipper.enable(:ddr)
    get home_path
    assert_response :success
    assert_select "img.sidebar__logo-img[alt='Hack Club Dance Dance Revolution'][src*='ddr']", count: 1
  end

  test "actor restricted DDR logo only appears for the selected user" do
    Flipper.enable_actor(:ddr, users(:one))
    get home_path
    assert_select "img.sidebar__logo-img[src*='stardance-logo']", count: 1

    sign_in users(:two)
    get home_path
    assert_select "img.sidebar__logo-img[src*='stardance-logo']", count: 1

    sign_in users(:one)
    get home_path
    assert_select "img.sidebar__logo-img[src*='ddr']", count: 1

    Flipper.disable(:ddr)
    get home_path
    assert_select "img.sidebar__logo-img[src*='stardance-logo']", count: 1
  end
end
