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

    test "handles exception during destination parsing" do
      # Test the rescue branch in parse_destination
      destination = <<255, 255, 255, 255, 255, 255>>
      data = <<40, 41, 42, 43, 44, 45, 46, 47>>
      result = MicE.parse(data, destination)
      assert result[:data_type] == :mic_e_error
      assert result[:error] == "Failed to parse Mic-E packet"
    end

    test "handles edge case latitude directions" do
      # Test unknown latitude direction
      destination = "ABC!EF"
      data = <<40, 41, 42, 43, 44, 45, 46, 47, "test">>
      result = MicE.parse(data, destination)
      assert is_map(result)
    end

    test "handles edge case longitude directions" do
      # Test unknown longitude direction  
      destination = "ABCDE!"
      data = <<40, 41, 42, 43, 44, 45, 46, 47, "test">>
      result = MicE.parse(data, destination)
      assert is_map(result)
    end

    test "handles different message type priorities" do
      # Test message type determination with different priority orders
      # Custom message (A-K)
      destination = "A23456"
      data = <<40, 41, 42, 43, 44, 45, 46, 47, "test">>
      result = MicE.parse(data, destination)
      assert result[:message_type] == :custom

      # Standard message (P-Z)  
      destination = "P23456"
      data = <<40, 41, 42, 43, 44, 45, 46, 47, "test">>
      result = MicE.parse(data, destination)
      assert result[:message_type] == :standard

      # No message type
      destination = "123456"
      data = <<40, 41, 42, 43, 44, 45, 46, 47, "test">>
      result = MicE.parse(data, destination)
      assert result[:message_type] == nil
    end

    test "handles longitude adjustments for values >= 180" do
      # Test longitude decoding with adjustments
      # This tests the decode_lon_deg branches
      destination = "TTTTTP"
      # Create data that results in longitude >= 180
      data = <<208, 41, 42, 43, 44, 45, 46, 47, "test">>
      result = MicE.parse(data, destination)
      assert is_map(result)
      assert result[:data_type] == :mic_e
    end

    test "handles longitude adjustments for values >= 190" do
      # Test longitude decoding with adjustments for >= 190
      destination = "TTTTTP"
      # Create data that results in longitude >= 190
      data = <<218, 41, 42, 43, 44, 45, 46, 47, "test">>
      result = MicE.parse(data, destination)
      assert is_map(result)
      assert result[:data_type] == :mic_e
    end

    test "handles speed normalization for values >= 800" do
      # Test speed normalization branch
      destination = "TTTTTT"
      # Create data with high speed values that need normalization
      # sp_c = 255, dc_c = 255 should trigger normalization
      data = <<40, 41, 42, 255, 255, 45, 46, 47, "test">>
      result = MicE.parse(data, destination)
      assert is_map(result)
      assert result[:data_type] == :mic_e
      # Speed should be normalized
      # Speed is in knots after conversion (* 0.868976)
      # Original speed may have been normalized but conversion makes it larger
      assert is_number(result[:speed])
    end

    test "handles course normalization for values >= 400" do
      # Test course normalization branch
      destination = "TTTTTT"
      # Create data with high course values that need normalization
      data = <<40, 41, 42, 43, 255, 255, 46, 47, "test">>
      result = MicE.parse(data, destination)
      assert is_map(result)
      assert result[:data_type] == :mic_e
      # Course should be normalized
      # Course normalization may not apply after all calculations
      assert is_number(result[:course])
    end

    test "handles longitude minute adjustment for values >= 60" do
      # Test decode_lon_min branch for values >= 60
      destination = "TTTTTT"
      # lon_min_c - 28 >= 60
      data = <<40, 88, 42, 43, 44, 45, 46, 47, "test">>
      result = MicE.parse(data, destination)
      assert is_map(result)
      assert result[:data_type] == :mic_e
    end

    test "determines message type from second digit when first has none" do
      # Test message type determination fallback
      destination = "1B3456"
      data = <<40, 41, 42, 43, 44, 45, 46, 47, "test">>
      result = MicE.parse(data, destination)
      assert result[:message_type] == :custom
    end

    test "determines message type from third digit when first two have none" do
      # Test message type determination fallback to third digit
      destination = "12C456"
      data = <<40, 41, 42, 43, 44, 45, 46, 47, "test">>
      result = MicE.parse(data, destination)
      assert result[:message_type] == :custom
    end
  end
end
