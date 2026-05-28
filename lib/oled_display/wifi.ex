defmodule OledDisplay.WiFi do
  @compile {:no_warn_undefined, [:avm_pubsub, :esp]}

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Returns {connected :: boolean, ip :: tuple | nil}
  def status() do
    GenServer.call(__MODULE__, :status)
  end

  def init(_opts) do
    IO.puts("WiFi: initializing")
    self_pid = self()
    :avm_pubsub.pub(:pubsub, [:wifi_status], :connecting)
    :avm_pubsub.sub(:pubsub, [:clear_wifi_creds], self())

    spawn_link(fn ->
      result =
        WifiWiz.start(
          ap: [
            ssid: "AtomVM AP",
            psk: "atomvm123"
            # ap_started: fn -> 
            #   IO.puts("Setting TX power to low for AP mode")
            #  :network.set_tx_power(:low)
            # end
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
          :avm_pubsub.pub(:pubsub, [:wifi_status], :connected)

        {:error, :sta_exhausted} ->
          IO.puts("WiFi: STA exhausted, starting AP mode")
          send(self_pid, {:wifi_status, :ap_mode})
          :avm_pubsub.pub(:pubsub, [:wifi_status], :ap_mode)

          config =
            WifiWiz.Ap.create_ap_config("AtomVM AP", "atomvm123",
              ap_started: fn -> :ok end
            )

          WifiWiz.Ap.start_ap(config)

        other ->
          :io.format("WiFi: unexpected result ~p~n", [other])
      end
    end)

    {:ok, %{connected: false, ip: nil}}
  end

  def handle_info({:wifi_status, {:connected, ip}}, state) do
    :io.format("WiFi: state -> connected, ip=~p~n", [ip])
    {:noreply, %{state | connected: true, ip: ip}}
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
    {:reply, {state.connected, state.ip}, state}
  end
end
