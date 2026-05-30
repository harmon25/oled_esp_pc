defmodule OledDisplay.WiFi do
  @compile {:no_warn_undefined, [:avm_pubsub, :esp]}

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Returns {connected :: boolean, ip :: tuple | nil, ap_ssid :: String.t()}
  def status() do
    GenServer.call(__MODULE__, :status)
  end

  def init(_opts) do
    IO.puts("WiFi: initializing")
    self_pid = self()

    # Generate AP SSID from STA MAC so multiple devices are distinguishable
    ap_ssid = mac_based_ssid()

    :avm_pubsub.pub(:pubsub, [:wifi_status], :connecting)
    :avm_pubsub.sub(:pubsub, [:clear_wifi_creds], self())

    spawn_link(fn ->
      result =
        WifiWiz.start(
          ap: [
            ssid: ap_ssid,
            psk: "atomvm123"
          ],
          sta_retry: [
            max_duration_ms: 30_000,
            on_exhausted: :return_error
          ]
        )

      case result do
        {:ok, {ip, _, _}} ->
          :io.format("WiFi: connected ~p~n", [ip])
          send(self_pid, {:wifi_status, {:connected, ip}})
          :avm_pubsub.pub(:pubsub, [:wifi_status], {:connected, ip})

        {:error, :sta_exhausted} ->
          IO.puts("WiFi: STA exhausted, starting AP mode")
          send(self_pid, {:wifi_status, {:ap_mode, ap_ssid}})
          :avm_pubsub.pub(:pubsub, [:wifi_status], {:ap_mode, ap_ssid})

          config =
            WifiWiz.Ap.create_ap_config(ap_ssid, "atomvm123", ap_started: fn -> :ok end)

          WifiWiz.Ap.start_ap(config)

        other ->
          :io.format("WiFi: unexpected result ~p~n", [other])
      end
    end)

    {:ok, %{connected: false, ip: nil, ap_ssid: ap_ssid}}
  end

  def handle_info({:wifi_status, {:connected, ip}}, state) do
    :io.format("WiFi: state -> connected, ip=~p~n", [ip])
    {:noreply, %{state | connected: true, ip: ip}}
  end

  def handle_info({:wifi_status, {:ap_mode, ap_ssid}}, state) do
    :io.format("WiFi: state -> ap_mode, ssid=~p~n", [ap_ssid])
    {:noreply, %{state | connected: false, ip: nil, ap_ssid: ap_ssid}}
  end

  def handle_info({:wifi_status, status}, state) do
    :io.format("WiFi: state -> ~p~n", [status])
    {:noreply, %{state | connected: false, ip: nil}}
  end

  def handle_info({:pub, [:clear_wifi_creds], _from, :boot_button_held}, state) do
    IO.puts("WiFi: wiping credentials")
    WifiWiz.Config.reset()
    Process.sleep(500)
    :esp.restart()
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, {state.connected, state.ip, state.ap_ssid}, state}
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp mac_based_ssid do
    mac =
      try do
        :esp.get_mac(:wifi_sta)
      catch
        _, _ -> nil
      end

    if is_binary(mac) and byte_size(mac) == 6 do
      <<_::binary-size(4), a, b>> = mac
      "AtomVM-" <> hex_byte(a) <> hex_byte(b)
    else
      "AtomVM-XXXX"
    end
  end

  defp hex_byte(n) when is_integer(n) and n >= 0 and n <= 255 do
    high = div(n, 16)
    low = rem(n, 16)
    <<nibble_to_hex(high), nibble_to_hex(low)>>
  end

  defp nibble_to_hex(n) when n < 10, do: ?0 + n
  defp nibble_to_hex(n) when n < 16, do: ?a + (n - 10)
end
