defmodule Aprs.CompressedSymbolTableTest do
  use ExUnit.Case, async: true

  describe "compressed position with leading symbol table" do
    test "HB9ZF-12 packet with symbol table 'L' before compressed position" do
      packet = "HB9ZF-12>APLRG1,HB9ELV-13*,qAO,HB9AK-10:!L6VeIPd9U& ik��6��Ye JN47kg"
      
      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.sender == "HB9ZF-12"
      assert parsed.data_type == :position
      
      # Check the position data
      data = parsed.data_extended
      assert data.compressed? == true
      assert data.symbol_table_id == "L"
      assert data.symbol_code == "&"
      
      # Verify coordinates are correct
      assert_in_delta data.latitude, 47.288, 0.001
      assert_in_delta data.longitude, 8.881, 0.001
      
      # The comment should preserve the binary data
      assert data.comment =~ "JN47kg"
    end
    
    test "correctly distinguishes between compressed formats" do
      # Standard compressed with "/" prefix
      packet1 = "TEST>APRS:!/5L!!<*e7> sT"
      {:ok, parsed1} = Aprs.parse(packet1)
      assert parsed1.data_extended.symbol_table_id == "/"
      assert parsed1.data_extended.compressed? == true
      
      # Compressed with alternate symbol table
      packet2 = "TEST>APRS:!\\5L!!<*e7& sT"
      {:ok, parsed2} = Aprs.parse(packet2)
      assert parsed2.data_extended.symbol_table_id == "\\"
      assert parsed2.data_extended.symbol_code == "&"
      assert parsed2.data_extended.compressed? == true
    end
  end
end