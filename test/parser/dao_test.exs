defmodule Aprs.DAOTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.DAO

  # One thousandth and one hundredth of a minute, in degrees.
  @thousandth 0.001 / 60
  @hundredth 0.01 / 60

  describe "parse/1" do
    test "reads the human-readable form and reports the datum upper-cased" do
      assert {dao, "Test"} = DAO.parse("Test!W52!")

      assert dao.datum == "W"
      assert_in_delta dao.lat_offset, 5 * @thousandth, 1.0e-12
      assert_in_delta dao.lon_offset, 2 * @thousandth, 1.0e-12
    end

    test "reads the base-91 form" do
      assert {dao, "Test"} = DAO.parse("Test!w52!")

      assert dao.datum == "W"
      assert_in_delta dao.lat_offset, (?5 - 33) / 91 * @hundredth, 1.0e-12
      assert_in_delta dao.lon_offset, (?2 - 33) / 91 * @hundredth, 1.0e-12
    end

    test "accepts a datum with no additional precision" do
      assert {dao, "Test"} = DAO.parse("Test!W  !")

      assert dao.datum == "W"
      assert dao.lat_offset == 0.0
      assert dao.lon_offset == 0.0
    end

    test "finds a DAO extension in the middle of a comment" do
      # Only the extension itself is cut out; the surrounding spacing is the
      # station's own text.
      assert {dao, "before  after"} = DAO.parse("before !W52! after")
      assert dao.datum == "W"
    end

    test "leaves a comment with no DAO extension alone" do
      assert {nil, "no dao here"} = DAO.parse("no dao here")
    end

    test "skips a bracketed run that is not a DAO extension" do
      assert {nil, "!12! and !W5!"} = DAO.parse("!12! and !W5!")
    end

    test "keeps scanning past a malformed candidate" do
      assert {dao, "!!5! keep"} = DAO.parse("!!5! keep!W52!")
      assert dao.datum == "W"
    end

    test "returns non-binary input unchanged" do
      assert {nil, nil} = DAO.parse(nil)
    end
  end

  describe "apply_precision/4" do
    test "moves a northern, eastern position away from the origin" do
      {dao, _} = DAO.parse("!W52!")
      {lat, lon} = DAO.apply_precision(49.0, 72.0, dao, 0)

      assert_in_delta lat, 49.0 + 5 * @thousandth, 1.0e-12
      assert_in_delta lon, 72.0 + 2 * @thousandth, 1.0e-12
    end

    test "moves a southern, western position away from the origin" do
      {dao, _} = DAO.parse("!W52!")
      {lat, lon} = DAO.apply_precision(-49.0, -72.0, dao, 0)

      assert_in_delta lat, -49.0 - 5 * @thousandth, 1.0e-12
      assert_in_delta lon, -72.0 - 2 * @thousandth, 1.0e-12
    end

    test "leaves an ambiguous position alone" do
      {dao, _} = DAO.parse("!W52!")
      assert {49.0, 72.0} = DAO.apply_precision(49.0, 72.0, dao, 1)
    end

    test "leaves coordinates alone when there is no DAO extension" do
      assert {49.0, 72.0} = DAO.apply_precision(49.0, 72.0, nil, 0)
    end

    test "passes nil coordinates through" do
      {dao, _} = DAO.parse("!W52!")
      assert {nil, nil} = DAO.apply_precision(nil, nil, dao, 0)
    end

    property "the offset never exceeds a hundredth of a minute" do
      check all datum <- StreamData.member_of(["W", "G", "w", "g"]),
                a <- StreamData.integer(33..123),
                o <- StreamData.integer(33..123) do
        case DAO.parse("!" <> datum <> <<a, o>> <> "!") do
          {nil, _} ->
            :ok

          {dao, _} ->
            assert dao.lat_offset >= 0.0 and dao.lat_offset <= @hundredth
            assert dao.lon_offset >= 0.0 and dao.lon_offset <= @hundredth
        end
      end
    end
  end
end
