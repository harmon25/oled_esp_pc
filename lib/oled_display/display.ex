defmodule OledDisplay.Display do
  @compile {:no_warn_undefined, [I2C, AVMPort, :avm_pubsub]}

  @i2c_sda 3
  @i2c_scl 4
  @display_width 128
  @display_height 64
  @screens [OledDisplay.Screens.SystemStats, OledDisplay.Screens.Weather]

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

    # Register all custom fonts found in assets/fonts/
    Enum.each(OledDisplay.Fonts.all(), fn {name, bin} ->
      AVMPort.call(display, {:register_font, name, bin})
    end)

    :avm_scene.start_link(__MODULE__, opts ++ [display: display], display_server: {:port, display})
  end

  def init(opts) do
    :avm_pubsub.sub(:pubsub, [:wifi_status], self())
    :avm_pubsub.sub(:pubsub, [:screen_request], self())
    :avm_pubsub.sub(:pubsub, [:next_screen], self())

    # Start with Splash screen
    {screen_state, tick_ms} = OledDisplay.Screens.Splash.init([])
    tick_ref = schedule_tick(tick_ms)

    state = %{
      screen: OledDisplay.Screens.Splash,
      screen_state: screen_state,
      tick_ms: tick_ms,
      tick_ref: tick_ref,
      display: opts[:display]
    }

    {:ok, state}
  end

  # ── Event handlers ───────────────────────────────────────────────

  # Tick handler: the ONLY place that reschedules the next tick (besides
  # switch_screen which sets up the first tick for a new screen).
  # Handling it separately prevents non-tick messages from piling up extra timers.
  def handle_info(:tick, state) do
    result = state.screen.handle_info(:tick, state.screen_state)

    case result do
      {:switch, module, args} ->
        do_switch(state, module, args)

      {:noreply, new_screen_state} ->
        tick_ref = schedule_tick(state.tick_ms)
        {:noreply, %{state | screen_state: new_screen_state, tick_ref: tick_ref}}

      {:noreply, new_screen_state, [{:push, items}]} ->
        tick_ref = schedule_tick(state.tick_ms)
        {:noreply, %{state | screen_state: new_screen_state, tick_ref: tick_ref}, [{:push, items}]}
    end
  end

  def handle_info({:pub, [:wifi_status], _from, status}, state) do
    result = state.screen.handle_info({:wifi_status, status}, state.screen_state)
    handle_screen_result(result, state)
  end

  def handle_info({:pub, [:screen_request], _from, {:switch, module, args}}, state) do
    do_switch(state, module, args)
  end

  def handle_info({:pub, [:next_screen], _from, :boot_button_pressed}, state) do
    next = cycle_screen(state.screen)
    do_switch(state, next, [])
  end

  def handle_info(msg, state) do
    result = state.screen.handle_info(msg, state.screen_state)
    handle_screen_result(result, state)
  end

  # ── Screen result helpers (non-tick messages — no tick rescheduling) ──

  defp handle_screen_result({:noreply, new_screen_state}, state) do
    {:noreply, %{state | screen_state: new_screen_state}}
  end

  defp handle_screen_result({:noreply, new_screen_state, [{:push, items}]}, state) do
    {:noreply, %{state | screen_state: new_screen_state}, [{:push, items}]}
  end

  defp handle_screen_result({:switch, module, args}, state) do
    do_switch(state, module, args)
  end

  # ── Screen switching ───────────────────────────────────────────

  # Central switch entry point: cancel the outgoing screen's timer, init the
  # new screen, schedule its first tick, render an immediate first frame.
  defp do_switch(state, module, args) do
    new_state = switch_screen(state, module, args)
    items = module.render(new_state.screen_state)
    {:noreply, new_state, [{:push, items}]}
  end

  defp switch_screen(state, module, args) do
    # Cancel any pending tick from the outgoing screen. If the timer already
    # fired, cancel_timer returns false — harmless.
    cancel_tick(state[:tick_ref])

    {screen_state, tick_ms} = module.init(args)
    tick_ref = schedule_tick(tick_ms)

    %{state | screen: module, screen_state: screen_state, tick_ms: tick_ms, tick_ref: tick_ref}
  end

  defp cancel_tick(nil), do: :ok
  defp cancel_tick(ref), do: Process.cancel_timer(ref)

  defp schedule_tick(tick_ms) when tick_ms > 0 do
    Process.send_after(self(), :tick, tick_ms)
  end

  defp schedule_tick(_tick_ms) do
    nil
  end

  defp cycle_screen(current) do
    case Enum.find_index(@screens, &(&1 == current)) do
      nil -> hd(@screens)
      idx -> Enum.at(@screens, rem(idx + 1, length(@screens)))
    end
  end

  defp static_splash_items do
    [{:rect, 0, 0, @display_width, @display_height, 0x000000}]
  end
end
