# Get packet from command line argument
packet =
  List.first(System.argv()) ||
    "DL7AD-3>APECAN,WIDE2-1,qAO,DL4MDW:=/4!#\\Qq%eO¢FVhttp://apecan.net?t=3191888072|4>Nz!)#i0yyr!!|"

IO.puts("[DEBUG] Script loaded and starting execution")
IO.puts("[DEBUG] Packet assignment complete")
IO.puts("[DEBUG] Testing packet: #{packet}\n")

IO.puts("[DEBUG] Calling Aprs.parse...")
result = Aprs.parse(packet)
IO.puts("[DEBUG] Parse result: #{inspect(result)}")

case result do
  {:ok, result} ->
    IO.puts("✅ Packet parsed successfully!")
    IO.inspect(result, label: "Parsed Packet")
    data = result[:data_extended]

    if is_map(data) do
      cond do
        data[:data_type] == :malformed_position ->
          IO.puts("❌ Malformed position data: #{data[:comment]}")

        data[:latitude] == nil or data[:longitude] == nil ->
          IO.puts("❌ Could not extract valid latitude/longitude.")

        data[:data_type] == :timestamped_position_error ->
          IO.puts("❌ Timestamped position error: #{data[:error]}")

        data[:data_type] == :invalid_test_data ->
          IO.puts("❌ Invalid test data: #{data[:comment]}")

        data[:data_type] == :unknown_datatype ->
          IO.puts("❌ Unknown data type.")

        true ->
          IO.puts("✅ Data appears valid.")
      end
    else
      IO.puts("ℹ️  No extended data map returned.")
    end

  {:error, reason} ->
    IO.puts("❌ Packet parsing failed: #{inspect(reason)}")
    IO.puts("❌ (Test will fail once parser is fixed to accept this packet)")
    System.halt(1)
end

IO.puts("[DEBUG] Script finished")
