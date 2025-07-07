# Test device identification for Mic-E packet
packet = %{
  data_type: :mic_e,
  destination: "T5TYR2"
}

device_id = Aprs.DeviceParser.extract_device_identifier(packet)
IO.puts("Device ID: #{device_id}")

# Test the raw decoding function
tocall = Aprs.DeviceParser.decode_mic_e_tocall("T5TYR2")
IO.puts("TOCALL: #{tocall}")

# Test with T5TYR4 which should give APK004
tocall2 = Aprs.DeviceParser.decode_mic_e_tocall("T5TYR4")
IO.puts("T5TYR4 -> TOCALL: #{tocall2}")
