defmodule Aprs.NMEAHelpersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.NMEAHelpers

  describe "parse_nmea_coordinate/2" do
    test "parses valid latitude coordinates" do
      assert {:ok, 49.035} = NMEAHelpers.parse_nmea_coordinate("4903.50", "N")
      assert {:ok, -49.035} = NMEAHelpers.parse_nmea_coordinate("4903.50", "S")
    end

    test "parses valid longitude coordinates" do
      assert {:ok, 72.0175} = NMEAHelpers.parse_nmea_coordinate("7201.75", "E")
      assert {:ok, -72.0175} = NMEAHelpers.parse_nmea_coordinate("7201.75", "W")
    end

    test "handles various coordinate formats" do
      assert {:ok, 33.393} = NMEAHelpers.parse_nmea_coordinate("3339.3", "N")
      assert {:ok, -33.393} = NMEAHelpers.parse_nmea_coordinate("3339.3", "S")
      assert {:ok, 118.15} = NMEAHelpers.parse_nmea_coordinate("11815.0", "E")
      assert {:ok, -118.15} = NMEAHelpers.parse_nmea_coordinate("11815.0", "W")
    end

    test "handles zero coordinates" do
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("0.0", "N")
      assert result == 0.0
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("0.0", "E")
      assert result == 0.0
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("0.0", "S")
      assert result == 0.0
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("0.0", "W")
      assert result == 0.0
    end

    test "handles coordinate with high precision" do
      assert {:ok, 49.035} = NMEAHelpers.parse_nmea_coordinate("4903.50", "N")
      assert {:ok, 49.0352} = NMEAHelpers.parse_nmea_coordinate("4903.52", "N")
    end

    test "returns error for invalid coordinate values" do
      assert {:error, "Invalid coordinate value"} = NMEAHelpers.parse_nmea_coordinate("invalid", "N")
      assert {:error, "Invalid coordinate value"} = NMEAHelpers.parse_nmea_coordinate("abc.def", "N")
      assert {:error, "Invalid coordinate value"} = NMEAHelpers.parse_nmea_coordinate("", "N")
    end

    test "returns error for invalid directions" do
      assert {:error, "Invalid coordinate direction"} = NMEAHelpers.parse_nmea_coordinate("4903.50", "X")
      assert {:error, "Invalid coordinate direction"} = NMEAHelpers.parse_nmea_coordinate("4903.50", "Z")
      assert {:error, "Invalid coordinate direction"} = NMEAHelpers.parse_nmea_coordinate("4903.50", "")
      assert {:error, "Invalid coordinate direction"} = NMEAHelpers.parse_nmea_coordinate("4903.50", "north")
    end

    test "handles non-binary inputs" do
      assert {:error, "Invalid coordinate format"} = NMEAHelpers.parse_nmea_coordinate(123, "N")
      assert {:error, "Invalid coordinate format"} = NMEAHelpers.parse_nmea_coordinate("4903.50", 123)
      assert {:error, "Invalid coordinate format"} = NMEAHelpers.parse_nmea_coordinate(nil, "N")
      assert {:error, "Invalid coordinate format"} = NMEAHelpers.parse_nmea_coordinate("4903.50", nil)
    end

    test "handles edge case directions" do
      # Test all valid directions
      assert {:ok, coord} = NMEAHelpers.parse_nmea_coordinate("4903.50", "N")
      assert coord > 0

      assert {:ok, coord} = NMEAHelpers.parse_nmea_coordinate("4903.50", "S")
      assert coord < 0

      assert {:ok, coord} = NMEAHelpers.parse_nmea_coordinate("4903.50", "E")
      assert coord > 0

      assert {:ok, coord} = NMEAHelpers.parse_nmea_coordinate("4903.50", "W")
      assert coord < 0
    end

    property "coordinate parsing produces correct signs" do
      check all coord_str <- StreamData.string(:ascii, min_length: 1, max_length: 10),
                direction <- StreamData.member_of(["N", "S", "E", "W"]) do
        # Only test with valid numeric strings
        if String.match?(coord_str, ~r/^\d+\.\d+$/) do
          case NMEAHelpers.parse_nmea_coordinate(coord_str, direction) do
            {:ok, result} ->
              case direction do
                "N" -> assert result >= 0
                "E" -> assert result >= 0
                "S" -> assert result <= 0
                "W" -> assert result <= 0
              end

            {:error, _} ->
              # Invalid coordinates should return errors
              :ok
          end
        end
      end
    end

    property "coordinate parsing is consistent" do
      check all coord_value <- StreamData.float(min: 0.0, max: 18_000.0),
                direction <- StreamData.member_of(["N", "S", "E", "W"]) do
        coord_str = Float.to_string(coord_value)

        case NMEAHelpers.parse_nmea_coordinate(coord_str, direction) do
          {:ok, result} ->
            expected = coord_value / 100.0

            expected =
              case direction do
                "N" -> expected
                "E" -> expected
                "S" -> -expected
                "W" -> -expected
              end

            assert_in_delta result, expected, 0.001

          {:error, _} ->
            # Some coordinate values might be invalid
            :ok
        end
      end
    end
  end

  describe "parse_nmea_sentence/1" do
    test "returns not implemented error for any input" do
      assert {:error, "NMEA parsing not implemented"} =
               NMEAHelpers.parse_nmea_sentence("$GPRMC,123456,A,4903.50,N,07201.75,W*6A")

      assert {:error, "NMEA parsing not implemented"} =
               NMEAHelpers.parse_nmea_sentence("$GPGGA,123456,4903.50,N,07201.75,W,1,04,2.3,545.4,M,46.9,M,,*47")

      assert {:error, "NMEA parsing not implemented"} = NMEAHelpers.parse_nmea_sentence("")
      assert {:error, "NMEA parsing not implemented"} = NMEAHelpers.parse_nmea_sentence(nil)
      assert {:error, "NMEA parsing not implemented"} = NMEAHelpers.parse_nmea_sentence(123)
    end

    property "always returns not implemented error for any input" do
      check all sentence <-
                  StreamData.one_of([
                    StreamData.string(:ascii, min_length: 0, max_length: 100),
                    StreamData.integer(),
                    StreamData.float(),
                    StreamData.constant(nil)
                  ]) do
        assert {:error, "NMEA parsing not implemented"} = NMEAHelpers.parse_nmea_sentence(sentence)
      end
    end
  end

  describe "coordinate conversion edge cases" do
    test "handles very small coordinates" do
      assert {:ok, 0.01} = NMEAHelpers.parse_nmea_coordinate("1.0", "N")
      assert {:ok, -0.01} = NMEAHelpers.parse_nmea_coordinate("1.0", "S")
    end

    test "handles very large coordinates" do
      assert {:ok, 180.0} = NMEAHelpers.parse_nmea_coordinate("18000.0", "N")
      assert {:ok, -180.0} = NMEAHelpers.parse_nmea_coordinate("18000.0", "S")
    end

    test "handles decimal places correctly" do
      # Test that division by 100 works correctly
      assert {:ok, 12.345} = NMEAHelpers.parse_nmea_coordinate("1234.5", "N")
      assert {:ok, 1.23456} = NMEAHelpers.parse_nmea_coordinate("123.456", "N")
    end

    test "handles string coordinates with trailing characters" do
      # Float.parse should handle trailing characters
      assert {:ok, 49.035} = NMEAHelpers.parse_nmea_coordinate("4903.50abc", "N")
      assert {:ok, 49.03} = NMEAHelpers.parse_nmea_coordinate("4903.0xyz", "N")
    end

    test "handles coordinates with no decimal point" do
      assert {:ok, 49.0} = NMEAHelpers.parse_nmea_coordinate("4900", "N")
      assert {:ok, 10.0} = NMEAHelpers.parse_nmea_coordinate("1000", "N")
    end
  end
end
