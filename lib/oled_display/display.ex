defmodule OledDisplay.Display do
  @i2c_sda 3
  @i2c_scl 4
  @display_width 128
  @display_height 64

  # ── Lifecycle ────────────────────────────────────────────────────

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def start_link(opts) do
    i2c = I2C.open(sda: @i2c_sda, scl: @i2c_scl, clock_speed_hz: 400_000)

    display =
      AVMPort.open({:spawn, "display"},
        i2c_host: i2c,
        compatible: "solomon-systech,ssd1306",
        width: @display_width,
        height: @display_height,
        invert: false
      )

    # Push a static splash immediately so the screen isn't blank during startup
    AVMPort.call(display, {:update, static_splash_items()})

    :avm_scene.start_link(__MODULE__, opts ++ [display: display], display_server: {:port, display})
  end

  def init(opts) do
    :avm_pubsub.sub(:pubsub, :wifi_status, self())
    :avm_pubsub.sub(:pubsub, :screen_request, self())

    # Start with Splash screen
    {screen_state, tick_ms} = OledDisplay.Screens.Splash.init([])

    schedule_tick(tick_ms)

    state = %{
      screen: OledDisplay.Screens.Splash,
      screen_state: screen_state,
      tick_ms: tick_ms,
      display: opts[:display]
    }

    {:ok, state}
  end

  # ── Event handlers ───────────────────────────────────────────────

  def handle_info(:tick, state) do
    # Reschedule next tick before processing
    schedule_tick(state.tick_ms)

    # Tick routing — forward to active screen
    result = state.screen.handle_info(:tick, state.screen_state)
    handle_screen_result(result, state)
  end

  def handle_info({:wifi_status, status}, state) do
    result = state.screen.handle_info({:wifi_status, status}, state.screen_state)
    handle_screen_result(result, state)
  end

  def handle_info({:screen_request, {:switch, module, args}}, state) do
    new_state = switch_screen(state, module, args)
    items = module.render(new_state.screen_state)
    {:noreply, new_state, [{:push, items}]}
  end

  def handle_info(msg, state) do
    # Any other pubsub / system messages get routed to the screen
    result = state.screen.handle_info(msg, state.screen_state)
    handle_screen_result(result, state)
  end

  # ── Screen result handling ───────────────────────────────────────

  defp handle_screen_result({:noreply, new_screen_state}, state) do
    {:noreply, %{state | screen_state: new_screen_state}}
  end

  defp handle_screen_result({:noreply, new_screen_state, [{:push, items}]}, state) do
    {:noreply, %{state | screen_state: new_screen_state}, [{:push, items}]}
  end

  defp handle_screen_result({:switch, module, args}, state) do
    new_state = switch_screen(state, module, args)
    items = module.render(new_state.screen_state)
    {:noreply, new_state, [{:push, items}]}
  end

  # ── Screen switching ───────────────────────────────────────────

  defp switch_screen(state, module, args) do
    {screen_state, tick_ms} = module.init(args)

    # Schedule tick for new screen
    schedule_tick(tick_ms)

    %{state | screen: module, screen_state: screen_state, tick_ms: tick_ms}
  end

  defp schedule_tick(tick_ms) when tick_ms > 0 do
    Process.send_after(self(), :tick, tick_ms)
  end

  defp schedule_tick(_tick_ms) do
    :ok
  end

  defp static_splash_items do
    [
      {:text, 24, 8, :default16px, 0xFFFFFF, 0x000000, "AtomVM"},
      {:text, 16, 24, :default16px, 0xFFFFFF, 0x000000, "ESP32-C3"},
      {:text, 12, 40, :default16px, 0xAAAAAA, 0x000000, "Elixir + JIT"},
      {:rect, 0, 0, @display_width, @display_height, 0x000000}
    ]
  end
end
