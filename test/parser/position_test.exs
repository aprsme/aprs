defmodule Aprs.PositionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.Position

  describe "parse_aprs_position/2" do
    test "parses valid APRS lat/lon strings" do
      result = Position.parse_aprs_position("4903.50N", "07201.75W")
      assert is_float(result.latitude)
      assert is_float(result.longitude)

      assert_in_delta result.latitude, 49.058333, 0.000001
      assert_in_delta result.longitude, -72.029167, 0.000001
    end

    test "returns nils for invalid strings" do
      assert %{latitude: nil, longitude: nil} = Position.parse_aprs_position("bad", "data")
    end

    test "parses southern and eastern hemispheres" do
      result = Position.parse_aprs_position("1234.56S", "04540.70E")
      assert result.latitude < 0
      assert result.longitude > 0
    end

    test "returns nil for malformed but structurally valid input" do
      result = Position.parse_aprs_position("12345678", "123456789")
      assert %{latitude: nil, longitude: nil} = result
    end
  end

  describe "calculate_position_ambiguity/2" do
    test "returns correct ambiguity for no spaces" do
      assert Position.calculate_position_ambiguity("4903.50N", "07201.75W") == 0
    end

    test "returns correct ambiguity for one space in each string" do
      assert Position.calculate_position_ambiguity("49 3.50N", "07201.7 W") == 1
    end

    test "returns correct ambiguity for two spaces in each string" do
      assert Position.calculate_position_ambiguity("4  3.50N", "0720  .7W") == 2
    end
  end

  describe "count_spaces/1" do
    property "counts spaces correctly" do
      check all s <- StreamData.string(:ascii, min_length: 0, max_length: 20) do
        assert Position.count_spaces(s) == s |> String.graphemes() |> Enum.count(&(&1 == " "))
      end
    end
  end

  describe "specific failing packet" do
    test "VE6LY-7 packet with mic_e data type" do
      packet = "VE6LY-7>T5TYR2,F5ZFL-4*,WIDE1,WIDE2-1,qAR,HB9GYR-10:`|apl [/>\":E}432.812MHzAndy S andy@nsnw.ca^"

      # Test the full packet parsing
      result = Aprs.parse(packet)
      assert {:ok, parsed} = result

      # Check if we have extended data
      if parsed[:data_extended] do
        data = parsed[:data_extended]
        # The packet should have location data but it's not being decoded
        # This test will help us understand what's happening
        assert data[:data_type] == :mic_e_old
        # VE6LY-7 is in southern France, so longitude should be positive (east)
        # and in the correct range for France (roughly 0-10 degrees east)
        if data[:longitude] do
          lon = data[:longitude]
          # The longitude should be positive for eastern hemisphere (France)
          assert lon > 0, "Longitude should be positive for eastern hemisphere (France), got #{lon}"
          # Should be in reasonable range for France (roughly 0-10 degrees east)
          assert lon < 10, "Longitude should be in reasonable range for France, got #{lon}"
        end
      end
    end
  end

  describe "from_aprs/2" do
    test "delegates to parse_aprs_position" do
      result = Position.from_aprs("4903.50N", "07201.75W")
      assert result.latitude
      assert result.longitude
      assert_in_delta result.latitude, 49.058333, 0.000001
      assert_in_delta result.longitude, -72.029167, 0.000001
    end
  end

  describe "from_decimal/2" do
    test "creates position from decimal values" do
      result = Position.from_decimal(45.5, -73.6)
      assert_in_delta result.latitude, 45.5, 0.000001
      assert_in_delta result.longitude, -73.6, 0.000001
    end

    test "handles integer input" do
      result = Position.from_decimal(45, -73)
      assert_in_delta result.latitude, 45.0, 0.000001
      assert_in_delta result.longitude, -73.0, 0.000001
    end
  end

  describe "parse_aprs_position/2 with invalid direction" do
    test "returns nil lat when lat fraction has invalid direction char" do
      # "1234.56X" has valid digit prefix but 'X' is not N/S - triggers line 80 _ -> :error
      result = Position.parse_aprs_position("1234.56X", "09876.54W")
      assert result.latitude == nil
    end

    test "returns nil lon when lon fraction has invalid direction char" do
      result = Position.parse_aprs_position("1234.56N", "09876.54X")
      assert result.longitude == nil
    end
  end

  describe "calculate_position_ambiguity/2 edge cases" do
    test "returns 0 for mismatched space counts" do
      # Test the default case in @ambiguity_levels map
      assert Position.calculate_position_ambiguity("49 3.50N", "07201.75W") == 0
      assert Position.calculate_position_ambiguity("4903.50N", "07201.7 W") == 0
    end

    test "returns correct ambiguity for 3 spaces" do
      assert Position.calculate_position_ambiguity("4   .50N", "072   .7W") == 3
    end

    test "returns correct ambiguity for 4 spaces" do
      assert Position.calculate_position_ambiguity("    .50N", "072    .W") == 4
    end
  end

  describe "parse_aprs_position/2 with position ambiguity (spaces in coordinates)" do
    test "ambiguity=2: WINLINK-style with two spaces in fraction digits" do
      # 4113.  N → lat_deg=41, lat_min="13.  " → ambiguity=2
      # FAP: latitude = 41 + (13 + 0.5)/60 = 41.225
      result = Position.parse_aprs_position("4113.  N", "07322.  W")
      assert result.latitude
      assert result.longitude
      assert_in_delta result.latitude, 41.225, 0.001
      assert_in_delta result.longitude, -73.375, 0.001
    end

    test "ambiguity=1: one space in last fraction digit" do
      # 4919.2 N → lat_min="19.2 " → ambiguity=1
      # FAP: latitude = 49 + (19.2 + 0.05)/60 = 49.32083333
      result = Position.parse_aprs_position("4919.2 N", "12304.5 W")
      assert result.latitude
      assert result.longitude
      assert_in_delta result.latitude, 49.3208333, 0.001
      assert_in_delta result.longitude, -123.075833, 0.001
    end

    test "ambiguity=1: position with course/speed comment" do
      # 2543.3 N → ambiguity=1
      # FAP: latitude = 25 + (43.3 + 0.05)/60 = 25.7225
      result = Position.parse_aprs_position("2543.3 N", "10019.5 W")
      assert result.latitude
      assert result.longitude
      assert_in_delta result.latitude, 25.7225, 0.001
      assert_in_delta result.longitude, -100.325833, 0.001
    end

    test "ambiguity=1: European position with non-standard symbol table" do
      # 5125.7 N → ambiguity=1
      # FAP: latitude = 51 + (25.7 + 0.05)/60 = 51.42916667
      result = Position.parse_aprs_position("5125.7 N", "00647.0 E")
      assert result.latitude
      assert result.longitude
      assert_in_delta result.latitude, 51.4291667, 0.001
      assert_in_delta result.longitude, 6.78416667, 0.001
    end
  end

  describe "parse_aprs_position/2 with space digits not masked by ambiguity" do
    # Ambiguity is derived from trailing spaces in the *latitude* minutes only,
    # so a space can land in a minute slot that the ambiguity clause still
    # reads. Those spaces are interpreted as the digit zero.
    test "space in longitude hundredths digit is treated as zero" do
      # Latitude has no trailing spaces → ambiguity 0, so the full-precision
      # clause reads the longitude's hundredths digit, which is a space.
      spaced = Position.parse_aprs_position("4903.50N", "07201.7 W")
      zeroed = Position.parse_aprs_position("4903.50N", "07201.70W")

      assert spaced.ambiguity == 0
      assert spaced.latitude == zeroed.latitude
      assert spaced.longitude == zeroed.longitude
      assert_in_delta spaced.longitude, -72.0283333, 0.0000001
    end

    test "space in latitude minute-tens digit is treated as zero" do
      spaced = Position.parse_aprs_position("49 3.50N", "07201.75W")
      zeroed = Position.parse_aprs_position("4903.50N", "07201.75W")

      assert spaced.ambiguity == 0
      assert spaced.latitude == zeroed.latitude
      assert spaced.longitude == zeroed.longitude
      assert_in_delta spaced.latitude, 49.0583333, 0.0000001
    end
  end

  describe "full packet parsing with position ambiguity" do
    test "WINLINK object with ambiguity=2 spaces" do
      packet =
        "WINLINK>APWL2K,TCPIP*,qAS,WLNK-1:;AC1DQ-10 *180945z4113.  NW07322.  Wa145.050MHz Winlink VARA FM Wide Gateway"

      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :object
      data = parsed.data_extended
      assert_in_delta data.latitude, 41.225, 0.001
      assert_in_delta data.longitude, -73.375, 0.001
      assert data.posambiguity == 2
    end

    test "position with ambiguity=1 and course/speed" do
      packet = "XE2NCH-10>APDR16,TCPIP*,qAO,AE5PL-JF:=2543.3 N/10019.5 Wk000/002/A=001428 https://aprsdroid.org/"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position_with_message
      data = parsed.data_extended
      assert_in_delta data.latitude, 25.7225, 0.001
      assert_in_delta data.longitude, -100.325833, 0.001
      assert data.position_ambiguity == 1
    end

    test "position with ambiguity=1 and non-standard symbol table" do
      packet =
        "DF0UD-10>APPM13,TCPIP*,qAC,T2CZECH:=5125.7 NR00647.0 E&APRS RX only iGate 144.800 MHz, Uni Duisburg - JO31JK"

      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position_with_message
      data = parsed.data_extended
      assert data.symbol_table_id == "R"
      assert data.symbol_code == "&"
      assert_in_delta data.latitude, 51.4291667, 0.001
      assert_in_delta data.longitude, 6.78416667, 0.001
      assert data.position_ambiguity == 1
    end

    test "position with ambiguity=1 (VE7WPG)" do
      packet = "VE7WPG>APX221,WIDE1-1,qAO,VE7UBC:=4919.2 N/12304.5 WL"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position_with_message
      data = parsed.data_extended
      assert data.symbol_table_id == "/"
      assert data.symbol_code == "L"
      assert_in_delta data.latitude, 49.3208333, 0.001
      assert_in_delta data.longitude, -123.075833, 0.001
      assert data.position_ambiguity == 1
    end
  end

  describe "parse_aprs_position/2 properties" do
    # Half-width, in degrees, of the cell that each ambiguity level collapses
    # the minute field down to: 1 masked digit → 0.1', 2 → 1', 3 → 10', 4 → 60'.
    @ambiguity_cell_half_degrees %{1 => 0.05 / 60, 2 => 0.5 / 60, 3 => 5.0 / 60, 4 => 30.0 / 60}

    property "decodes a full-precision coordinate to degrees + minutes/60" do
      check all lat_deg <- StreamData.integer(0..89),
                lat_min <- StreamData.integer(0..59),
                lat_hundredths <- StreamData.integer(0..99),
                lat_dir <- StreamData.member_of(["N", "S"]),
                lon_deg <- StreamData.integer(0..179),
                lon_min <- StreamData.integer(0..59),
                lon_hundredths <- StreamData.integer(0..99),
                lon_dir <- StreamData.member_of(["E", "W"]) do
        lat_str = pad(lat_deg, 2) <> pad(lat_min, 2) <> "." <> pad(lat_hundredths, 2) <> lat_dir
        lon_str = pad(lon_deg, 3) <> pad(lon_min, 2) <> "." <> pad(lon_hundredths, 2) <> lon_dir

        expected_lat = sign(lat_dir) * (lat_deg + (lat_min + lat_hundredths / 100) / 60)
        expected_lon = sign(lon_dir) * (lon_deg + (lon_min + lon_hundredths / 100) / 60)

        result = Position.parse_aprs_position(lat_str, lon_str)

        assert result.ambiguity == 0
        assert_in_delta result.latitude, expected_lat, 1.0e-9
        assert_in_delta result.longitude, expected_lon, 1.0e-9
      end
    end

    property "masking the last N minute digits yields ambiguity N and stays within that cell" do
      check all lat_deg <- StreamData.integer(0..89),
                lat_min <- StreamData.integer(0..59),
                lat_hundredths <- StreamData.integer(0..99),
                lon_deg <- StreamData.integer(0..179),
                lon_min <- StreamData.integer(0..59),
                lon_hundredths <- StreamData.integer(0..99),
                masked <- StreamData.integer(1..4) do
        lat_digits = pad(lat_min, 2) <> pad(lat_hundredths, 2)
        lon_digits = pad(lon_min, 2) <> pad(lon_hundredths, 2)

        precise_lat = pad(lat_deg, 2) <> insert_point(lat_digits) <> "N"
        precise_lon = pad(lon_deg, 3) <> insert_point(lon_digits) <> "W"

        ambiguous_lat = pad(lat_deg, 2) <> insert_point(mask_trailing(lat_digits, masked)) <> "N"
        ambiguous_lon = pad(lon_deg, 3) <> insert_point(mask_trailing(lon_digits, masked)) <> "W"

        precise = Position.parse_aprs_position(precise_lat, precise_lon)
        result = Position.parse_aprs_position(ambiguous_lat, ambiguous_lon)

        # Ambiguity is derived from trailing spaces in the latitude minutes.
        assert result.ambiguity == masked

        # A truncated coordinate can sit exactly on the cell edge, so allow a
        # small epsilon for float rounding at that boundary.
        tolerance = @ambiguity_cell_half_degrees[masked] + 1.0e-9
        assert abs(result.latitude - precise.latitude) <= tolerance
        assert abs(result.longitude - precise.longitude) <= tolerance
      end
    end

    property "always returns the three position keys and never raises on arbitrary binaries" do
      check all lat <- StreamData.binary(max_length: 12),
                lon <- StreamData.binary(max_length: 12) do
        result = Position.parse_aprs_position(lat, lon)

        assert result |> Map.keys() |> Enum.sort() == [:ambiguity, :latitude, :longitude]
        assert result.ambiguity in 0..4
        assert is_nil(result.latitude) or is_float(result.latitude)
        assert is_nil(result.longitude) or is_float(result.longitude)
      end
    end

    property "latitude and longitude are either both parsed or both nil" do
      check all lat <- StreamData.string([?0..?9, ?\s, ?., ?N, ?S], max_length: 10),
                lon <- StreamData.string([?0..?9, ?\s, ?., ?E, ?W], max_length: 11) do
        result = Position.parse_aprs_position(lat, lon)
        assert is_nil(result.latitude) == is_nil(result.longitude)
      end
    end

    property "from_aprs/2 delegates to parse_aprs_position/2" do
      check all lat <- StreamData.string([?0..?9, ?\s, ?., ?N, ?S], max_length: 10),
                lon <- StreamData.string([?0..?9, ?\s, ?., ?E, ?W], max_length: 11) do
        assert Position.from_aprs(lat, lon) == Position.parse_aprs_position(lat, lon)
      end
    end
  end

  describe "calculate_position_ambiguity/2 properties" do
    property "always returns a level between 0 and 4" do
      check all lat <- StreamData.string([?0..?9, ?\s, ?., ?N, ?S], max_length: 12),
                lon <- StreamData.string([?0..?9, ?\s, ?., ?E, ?W], max_length: 12) do
        assert Position.calculate_position_ambiguity(lat, lon) in 0..4
      end
    end

    property "returns the shared space count when both coordinates agree, else 0" do
      check all spaces <- StreamData.integer(0..6),
                other <- StreamData.integer(0..6) do
        lat = String.duplicate(" ", spaces)
        lon = String.duplicate(" ", other)

        expected = if spaces == other and spaces <= 4, do: spaces, else: 0
        assert Position.calculate_position_ambiguity(lat, lon) == expected
      end
    end
  end

  describe "from_decimal/2 properties" do
    property "returns the given coordinates as floats" do
      check all lat <- StreamData.one_of([StreamData.integer(-90..90), StreamData.float(min: -90.0, max: 90.0)]),
                lon <- StreamData.one_of([StreamData.integer(-180..180), StreamData.float(min: -180.0, max: 180.0)]) do
        result = Position.from_decimal(lat, lon)

        assert is_float(result.latitude)
        assert is_float(result.longitude)
        assert result.latitude == lat / 1
        assert result.longitude == lon / 1
      end
    end
  end

  defp pad(value, width), do: String.pad_leading(to_string(value), width, "0")

  defp sign(dir) when dir in ["S", "W"], do: -1
  defp sign(_), do: 1

  # "2763" -> "27.63"
  defp insert_point(<<m1, m2, f1, f2>>), do: <<m1, m2, ?., f1, f2>>

  defp mask_trailing(digits, count) do
    keep = 4 - count
    String.slice(digits, 0, keep) <> String.duplicate(" ", count)
  end
end
