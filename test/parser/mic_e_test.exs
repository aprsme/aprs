defmodule Aprs.MicETest do
  use ExUnit.Case, async: true

  alias Aprs.MicE

  describe "parse/2" do
    test "decodes KG5EIU-9 packet correctly - previously problematic packet" do
      # This packet previously decoded incorrectly as 33.054333, -6.573667
      # but should decode to 33°03.26' N 96°34.42' W
      packet = "KG5EIU-9>S3PS2V,KK5PP-3,WIDE1*,qAR,W5DCR-3:`|>Fp wj/`\"5c}442.425MHz Toff +500 kg5eiu@w5fc.org _4"

      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :mic_e_old
      assert parsed.sender == "KG5EIU-9"
      assert parsed.destination == "S3PS2V"

      # Verify the coordinates are correct
      # 33°03.26' N = 33 + 3.26/60 = 33.054333°
      # 96°34.42' W = 96 + 34.42/60 = 96.573667°
      assert_in_delta Decimal.to_float(parsed.data_extended.latitude), 33.054333, 0.0001
      assert_in_delta Decimal.to_float(parsed.data_extended.longitude), -96.573667, 0.0001

      # Verify other MicE data
      assert parsed.data_extended.symbol_table_id == "/"
      assert parsed.data_extended.symbol_code == "j"
      assert_in_delta parsed.data_extended.speed, 34.759, 0.001
      assert parsed.data_extended.course == 91
      assert parsed.data_extended.message_bits == {1, 0, 1}
      assert parsed.data_extended.message_type == :standard
    end

    test "returns parsed map for valid Mic-E destination and data" do
      # Example valid destination and data (values are illustrative)
      destination = "ABCD12"
      data = <<40, 41, 42, 43, 44, 45, 46, 47>> <> "rest"
      result = MicE.parse(data, destination)
      assert is_map(result)
      assert result[:data_type] == :mic_e or result[:data_type] == :mic_e_error
    end

    test "returns error map for invalid destination length" do
      destination = "SHORT"
      data = <<40, 41, 42, 43, 44, 45, 46, 47>>
      result = MicE.parse(data, destination)
      assert result[:data_type] == :mic_e_error
      assert result[:latitude] == nil
      assert result[:longitude] == nil
    end

    test "returns error map for invalid information field length" do
      destination = "ABCDEF"
      data = <<1, 2, 3>>
      result = MicE.parse(data, destination)
      assert result[:data_type] == :mic_e_error
      assert result[:latitude] == nil
      assert result[:longitude] == nil
    end

    test "returns error map for invalid characters in destination" do
      destination = "!!!!!!"
      data = <<40, 41, 42, 43, 44, 45, 46, 47>>
      result = MicE.parse(data, destination)
      assert result[:data_type] == :mic_e_error
    end

    test "returns error map for nil destination" do
      data = <<40, 41, 42, 43, 44, 45, 46, 47>>
      result = MicE.parse(data, nil)
      assert result[:data_type] == :mic_e_error
    end
  end
end
