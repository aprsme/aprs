defmodule Aprs.PacketEdgesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  @max_packet_size 8192

  describe "packet size limit" do
    test "a packet at the size limit still parses" do
      packet = "N0CALL>APRS:>" <> String.duplicate("x", @max_packet_size - 13)

      assert byte_size(packet) == @max_packet_size
      assert {:ok, %{data_type: :status}} = Aprs.parse(packet)
    end

    test "a packet over the size limit is rejected without parsing" do
      assert Aprs.parse(String.duplicate("a", @max_packet_size + 1)) == {:error, :packet_too_large}
    end
  end

  describe "unexpected internal failures" do
    test "parse/1 reports an exception as an error tuple instead of raising" do
      # Aprs.Clock caches the current second in the process dictionary; a
      # poisoned cache entry makes the clock read blow up inside parse/1.
      assert {:error, "Parse exception: " <> message} = parse_with_broken_clock("N0CALL>APRS:>hi")
      assert message =~ "map"
    end
  end

  describe "digipeater paths" do
    test "a lone used marker leaves an empty digipeater callsign" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS,*:>hi")
      assert packet.digipeaters == [%{call: "", wasdigied: 1}]
    end

    test "an empty trailing path element is not a legal path" do
      assert Aprs.parse("N0CALL>APRS,WIDE1-1,:>hi") == {:error, :invalid_packet}
    end

    test "an empty leading path element is not a legal path" do
      assert Aprs.parse("N0CALL>APRS,,WIDE1-1:>hi") == {:error, :invalid_packet}
    end
  end

  describe "maidenhead grid beacons" do
    test "a six-character locator reports the centre of the subsquare" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:[IO91sx]Hello")

      assert packet.data_type == :maidenhead_grid
      assert packet.grid_locator == "IO91sx"
      assert_in_delta packet.latitude, 51.979167, 0.000001
      assert_in_delta packet.longitude, -0.458333, 0.000001
      assert packet.comment == "Hello"
      assert packet.has_position
      assert packet.format == :maidenhead
    end

    test "a four-character locator reports the centre of the square" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:[IO91]")

      assert packet.grid_locator == "IO91"
      assert packet.latitude == 51.5
      assert packet.longitude == -1.0
      assert packet.comment == ""
    end

    test "an uppercase subsquare is not a subsquare, so the square is reported" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:[IO91SX]Hello")

      assert packet.grid_locator == "IO91"
      assert packet.comment == "SX]Hello"
    end

    test "the closing bracket is optional" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:[JJ00aa")

      assert packet.grid_locator == "JJ00aa"
      assert packet.comment == ""
    end

    test "an unparseable locator carries no position" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:[9999")

      assert packet.data_type == :maidenhead_grid
      assert packet.raw_data == "9999"
      refute packet.has_position
    end

    property "a six-character locator resolves inside its own subsquare" do
      check all field_lon <- integer(?A..?R),
                field_lat <- integer(?A..?R),
                square_lon <- integer(?0..?9),
                square_lat <- integer(?0..?9),
                sub_lon <- integer(?a..?x),
                sub_lat <- integer(?a..?x) do
        locator = <<field_lon, field_lat, square_lon, square_lat, sub_lon, sub_lat>>

        assert {:ok, packet} = Aprs.parse("N0CALL>APRS:[" <> locator <> "]")
        assert packet.grid_locator == locator
        assert packet.has_position

        west = (field_lon - ?A) * 20 + (square_lon - ?0) * 2 + (sub_lon - ?a) * 2 / 24 - 180
        south = (field_lat - ?A) * 10 + (square_lat - ?0) + (sub_lat - ?a) / 24 - 90

        assert packet.longitude >= west and packet.longitude <= west + 2 / 24
        assert packet.latitude >= south and packet.latitude <= south + 1 / 24
      end
    end
  end

  describe "messages" do
    test "an information field that is not a message is reported as unparseable" do
      assert Aprs.parse_data(:message, "APRS", "missing colon") == %{
               data_type: :message,
               addressee: nil,
               message: nil,
               error: "Failed to parse message format"
             }
    end

    test "ack without a message number is ordinary message text" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS::TARGET   :ack")

      assert packet.data_type == :message
      assert packet.message_text == "ack"
      refute Map.has_key?(packet.data_extended, :messageack)
    end

    test "rej without a message number is ordinary message text" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS::TARGET   :rej")

      assert packet.data_type == :message
      assert packet.message_text == "rej"
      refute Map.has_key?(packet.data_extended, :messagerej)
    end

    test "ack with a message number is an acknowledgement" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS::TARGET   :ack42")

      assert packet.data_type == :message_ack
      assert packet.message_number == "42"
      assert packet.messageack == "42"
    end

    test "a trailing brace with no id stays in the message text" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS::TARGET   :hello{")

      assert packet.message_text == "hello{"
      refute Map.has_key?(packet, :message_number)
    end

    test "more than five id characters is not a message id" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS::TARGET   :hello{123456")

      assert packet.message_text == "hello{123456"
      refute Map.has_key?(packet, :message_number)
    end

    test "a reply-ack with no ack characters is not a message id" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS::TARGET   :hello{12}")

      assert packet.message_text == "hello{12}"
      refute Map.has_key?(packet, :message_number)
    end

    test "a reply-ack with trailing text is not a message id" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS::TARGET   :hello{12}345678")

      assert packet.message_text == "hello{12}345678"
      refute Map.has_key?(packet, :message_number)
    end

    test "a well formed reply-ack carries both numbers" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS::TARGET   :hello{12}34")

      assert packet.message_text == "hello"
      assert packet.message_number == "12"
      assert packet.message_ack == "34"
    end
  end

  describe "queries" do
    test "a query with no type carries no query type" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:?")

      assert packet.data_type == :query
      assert packet.query_type == nil
      assert packet.query_data == ""
    end
  end

  describe "ultimeter packets" do
    test "a complete Ultimeter payload decodes as weather rather than NMEA" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:$ULTW0000000002100000000027760129000A00000000")

      assert packet.data_type == :raw_gps_ultimeter
      assert packet.nmea_type == :ultimeter
      assert is_map(packet.weather)
      refute packet.has_position
    end
  end

  defp parse_with_broken_clock(packet) do
    key = {Aprs.Clock, :second}

    result =
      Enum.reduce_while(1..5, nil, fn _attempt, _acc ->
        :erlang.put(key, {div(:os.system_time(:microsecond), 1_000_000), :not_a_datetime})

        case Aprs.parse(packet) do
          {:error, "Parse exception: " <> _} = error -> {:halt, error}
          other -> {:cont, other}
        end
      end)

    :erlang.erase(key)
    result
  end
end
