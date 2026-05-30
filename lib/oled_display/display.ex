defmodule OledDisplay.Display do
  @compile {:no_warn_undefined, [I2C, AVMPort, :avm_pubsub]}
  alias OledDisplay.Fonts
  alias OledDisplay.Screens

  @i2c_sda 3
  @i2c_scl 4
  @display_width 128
  @display_height 64
  @screens [Screens.SystemStats, Screens.Weather]

  @boot_tick_ms 200
  @boot_min_ms 2000
  @boot_timeout_ms 10000
  @rotate_ms 10_000

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

    # Register all custom fonts found in assets/fonts/
    for {name, bin} <- Fonts.all() do
      AVMPort.call(display, {:register_font, name, bin})
    end

    # Push initial boot splash immediately so the screen isn't blank during startup
    initial_boot_state = %{
      tick_count: 0,
      boot_min_ticks: div(@boot_min_ms, @boot_tick_ms),
      wifi_status: nil,
      wifi_ip: nil,
      wifi_ap_ssid: nil
    }

    AVMPort.call(display, {:update, Screens.Splash.render(initial_boot_state)})

    :avm_scene.start_link(__MODULE__, opts ++ [display: display],
      display_server: {:port, display}
    )
  end

  def init(opts) do
    :avm_pubsub.sub(:pubsub, [:wifi_status], self())
    :avm_pubsub.sub(:pubsub, [:screen_request], self())
    :avm_pubsub.sub(:pubsub, [:next_screen], self())

    tick_ref = schedule_tick(@boot_tick_ms)

    state = %{
      mode: :boot,
      tick_count: 0,
      boot_min_ticks: div(@boot_min_ms, @boot_tick_ms),
      boot_timeout_ticks: div(@boot_timeout_ms, @boot_tick_ms),
      wifi_status: nil,
      wifi_ip: nil,
      wifi_ap_ssid: nil,
      tick_ms: @boot_tick_ms,
      tick_ref: tick_ref,
      display: opts[:display],
      screen: nil,
      screen_state: nil,
      rotate_ref: nil
    }

    {:ok, state}
  end

  # ── Event handlers ───────────────────────────────────────────────

  # Boot-mode tick
  def handle_info(:tick, %{mode: :boot} = state) do
    new_tick_count = state.tick_count + 1
    new_state = %{state | tick_count: new_tick_count}

    min_met = new_tick_count >= state.boot_min_ticks
    wifi_ready = new_state.wifi_status in [:connected, :ap_mode]
    timed_out = new_tick_count >= state.boot_timeout_ticks

    if (min_met and wifi_ready) or timed_out do
      target = find_first_available_screen([])
      do_switch_to_running(new_state, target, [])
    else
      items = Screens.Splash.render(new_state)
      tick_ref = schedule_tick(state.tick_ms)
      {:noreply, %{new_state | tick_ref: tick_ref}, [{:push, items}]}
    end
  end

  # Running-mode tick
  def handle_info(:tick, %{mode: :running} = state) do
    result = state.screen.handle_info(:tick, state.screen_state)
    handle_screen_result(result, state)
  end

  # Boot-mode wifi status
  def handle_info({:pub, [:wifi_status], _from, status}, %{mode: :boot} = state) do
    new_state = update_wifi_status(state, status)
    items = Screens.Splash.render(new_state)
    {:noreply, new_state, [{:push, items}]}
  end

  # Running-mode wifi status
  def handle_info({:pub, [:wifi_status], _from, status}, %{mode: :running} = state) do
    result = state.screen.handle_info({:wifi_status, status}, state.screen_state)
    handle_screen_result(result, state)
  end

  # Screen requests during boot are ignored
  def handle_info(
        {:pub, [:screen_request], _from, {:switch, _module, _args}},
        %{mode: :boot} = state
      ) do
    {:noreply, state}
  end

  def handle_info(
        {:pub, [:screen_request], _from, {:switch, module, args}},
        %{mode: :running} = state
      ) do
    do_switch(state, module, args)
  end

  # Button short press during boot is ignored
  def handle_info({:pub, [:next_screen], _from, :boot_button_pressed}, %{mode: :boot} = state) do
    {:noreply, state}
  end

  # Button short press during running cycles screens
  def handle_info({:pub, [:next_screen], _from, :boot_button_pressed}, %{mode: :running} = state) do
    next = cycle_screen(state.screen)
    do_switch(state, next, [])
  end

  # Auto-rotation timer
  def handle_info(:rotate, %{mode: :running} = state) do
    next = cycle_screen(state.screen)
    do_switch(state, next, [])
  end

  def handle_info(:rotate, state) do
    {:noreply, state}
  end

  # Catch-all for running mode
  def handle_info(msg, %{mode: :running} = state) do
    result = state.screen.handle_info(msg, state.screen_state)
    handle_screen_result(result, state)
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Screen result helpers ──────────────────────────────────────

  defp handle_screen_result({:noreply, new_screen_state}, state) do
    tick_ms = state.tick_ms
    tick_ref = schedule_tick(tick_ms)
    {:noreply, %{state | screen_state: new_screen_state, tick_ref: tick_ref}}
  end

  defp handle_screen_result({:noreply, new_screen_state, opts}, state) do
    tick_ms = Keyword.get(opts, :tick_ms, state.tick_ms)
    tick_ref = schedule_tick(tick_ms)
    scene_opts = Keyword.delete(opts, :tick_ms)
    new_state = %{state | screen_state: new_screen_state, tick_ref: tick_ref}

    case scene_opts do
      [] -> {:noreply, new_state}
      _ -> {:noreply, new_state, scene_opts}
    end
  end

  defp handle_screen_result({:switch, module, args}, state) do
    do_switch(state, module, args)
  end

  # ── Screen switching ───────────────────────────────────────────

  defp do_switch_to_running(state, module, args) do
    cancel_tick(state.tick_ref)

    {screen_state, tick_ms} = module.init(args)
    tick_ref = schedule_tick(tick_ms)
    rotate_ref = schedule_rotate(@rotate_ms)

    items = module.render(screen_state)

    new_state = %{
      state
      | mode: :running,
        screen: module,
        screen_state: screen_state,
        tick_ms: tick_ms,
        tick_ref: tick_ref,
        rotate_ref: rotate_ref,
        tick_count: 0
    }

    {:noreply, new_state, [{:push, items}]}
  end

  defp do_switch(state, module, args) do
    cancel_tick(state.tick_ref)
    cancel_rotate(state.rotate_ref)

    {screen_state, tick_ms} = module.init(args)
    tick_ref = schedule_tick(tick_ms)
    rotate_ref = schedule_rotate(@rotate_ms)

    items = module.render(screen_state)

    new_state = %{
      state
      | screen: module,
        screen_state: screen_state,
        tick_ms: tick_ms,
        tick_ref: tick_ref,
        rotate_ref: rotate_ref
    }

    {:noreply, new_state, [{:push, items}]}
  end

  defp cancel_tick(nil), do: :ok
  defp cancel_tick(ref), do: Process.cancel_timer(ref)

  defp cancel_rotate(nil), do: :ok
  defp cancel_rotate(ref), do: Process.cancel_timer(ref)

  defp schedule_tick(tick_ms) when tick_ms > 0 do
    Process.send_after(self(), :tick, tick_ms)
  end

  defp schedule_tick(_tick_ms), do: nil

  defp schedule_rotate(ms) when ms > 0 do
    Process.send_after(self(), :rotate, ms)
  end

  defp schedule_rotate(_ms), do: nil

  defp cycle_screen(current) do
    case Enum.find_index(@screens, &(&1 == current)) do
      nil ->
        find_first_available_screen([])

      idx ->
        next_idx = rem(idx + 1, length(@screens))
        find_next_available(next_idx, length(@screens))
    end
  end

  defp find_first_available_screen(args) do
    Enum.find(@screens, fn module -> module.available?(args) end) || hd(@screens)
  end

  defp find_next_available(start_idx, total) do
    indices = for i <- 0..(total - 1), do: rem(start_idx + i, total)

    Enum.find_value(indices, fn idx ->
      module = Enum.at(@screens, idx)
      if module.available?([]), do: module, else: nil
    end) || hd(@screens)
  end

  defp update_wifi_status(state, {:connected, ip}) do
    %{state | wifi_status: :connected, wifi_ip: ip}
  end

  defp update_wifi_status(state, {:ap_mode, ap_ssid}) do
    %{state | wifi_status: :ap_mode, wifi_ip: nil, wifi_ap_ssid: ap_ssid}
  end

  defp update_wifi_status(state, :connecting) do
    %{state | wifi_status: :connecting}
  end

  defp update_wifi_status(state, _other) do
    state
  end
end
