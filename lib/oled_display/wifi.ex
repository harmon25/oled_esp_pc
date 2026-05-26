defmodule OledDisplay.WiFi do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    :avm_pubsub.pub(:pubsub, :wifi_status, :initializing)

    wifi_pid = self()

    spawn_link(fn ->
      :avm_pubsub.pub(:pubsub, :wifi_status, :connecting)
      send(wifi_pid, {:wifi_event, :connecting})

      WifiWiz.start(
        ap: [
          ssid: "AtomVM AP",
          psk: "atomvm123",
          ap_started: fn -> send(wifi_pid, {:wifi_event, :ap_mode}) end
        ]
      )

      send(wifi_pid, {:wifi_event, :connected})
    end)

    {:ok, %{status: :initializing}}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_info({:wifi_event, status}, state) do
    :avm_pubsub.pub(:pubsub, :wifi_status, status)
    {:noreply, %{state | status: status}}
  end
end
