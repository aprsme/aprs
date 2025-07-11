defmodule Aprs.MicELongitudeTest do
  use ExUnit.Case, async: true

  describe "MicE longitude decoding" do
    test "K5EEN-14 packet decodes to correct longitude" do
      # This packet should decode to 33°07.05' N 96°40.47' W
      packet = "K5EEN-14>S3PW0U,WIDE1-1,WIDE2-1,qAO,K5IDL-10:`|DKo\"G>/`\"6+}_%"

      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :mic_e_old
      assert parsed.sender == "K5EEN-14"
      assert parsed.destination == "S3PW0U"

      # Verify the coordinates are correct
      # 33°07.05' N = 33 + 7.05/60 = 33.1175°
      # 96°40.47' W = 96 + 40.47/60 = 96.6745°
      assert_in_delta Decimal.to_float(parsed.data_extended.latitude), 33.1175, 0.0001
      assert_in_delta Decimal.to_float(parsed.data_extended.longitude), -96.6745, 0.0001
    end

    test "MicE parser fails when backtick is included in data" do
      destination = "S3PW0U"
      data_with_backtick = "`|DKo\"G>/`\"6+}_%"
      data_without_backtick = "|DKo\"G>/`\"6+}_%"

      # Parse with backtick included (wrong)
      result_with_backtick = Aprs.MicE.parse(data_with_backtick, destination)

      # Parse without backtick (correct)
      result_without_backtick = Aprs.MicE.parse(data_without_backtick, destination)

      # The longitude should be different
      lon_with = Decimal.to_float(result_with_backtick.longitude)
      lon_without = Decimal.to_float(result_without_backtick.longitude)

      assert lon_with != lon_without
      # Correct value
      assert_in_delta lon_without, -96.6745, 0.0001
      # Incorrect value
      assert_in_delta lon_with, -68.6067, 0.0001
    end
  end
end
