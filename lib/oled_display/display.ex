defmodule OledDisplay.Display do
  @compile {:no_warn_undefined, [AVMPort, :avm_pubsub]}

  require OledDisplay.Log
  alias OledDisplay.Log
  alias OledDisplay.DisplayState
  alias OledDisplay.Screens

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
    # The display port was opened in OledDisplay.start/0 and lives for
    # the full device uptime. We receive it here rather than reopening
    # I2C so that supervised restarts never trigger "i2c driver install error".
    display = Keyword.fetch!(opts, :display)

    :avm_scene.start_link(__MODULE__, opts, display_server: {:port, display})
  end

  def init(opts) do
    :avm_pubsub.sub(:pubsub, [:wifi_wiz, :wifi_status])
    :avm_pubsub.sub(:pubsub, [:screen_request])
    :avm_pubsub.sub(:pubsub, [:next_screen])
    :avm_pubsub.sub(:pubsub, [:weather_ready])
    :avm_pubsub.sub(:pubsub, [:weather_data])

    # Generation counters replace timer refs.  Each bump logically
    # "cancels" all previously scheduled timers for that slot: when a
    # stale timer fires it delivers {:tick, old_gen} / {:rotate, old_gen}
    # which no longer matches state.tick_gen / state.rotate_gen, so the
    # handler ignores it and does NOT reschedule.  This bounds the
    # live-timer population regardless of cancel_timer being a no-op on
    # AtomVM's timer_manager implementation.
    state = %{
      mode: :boot,
      tick_count: 0,
      boot_min_ticks: div(@boot_min_ms, @boot_tick_ms),
      boot_timeout_ticks: div(@boot_timeout_ms, @boot_tick_ms),
      wifi_status: nil,
      wifi_ip: nil,
      wifi_ap_ssid: nil,
      weather_ready?: false,
      locations_empty?: locations_empty?(),
      tick_ms: @boot_tick_ms,
      tick_gen: 0,
      rotate_gen: 0,
      display: opts[:display],
      screen: nil,
      screen_state: nil
    }

    state = bump_tick(state)
    {:ok, state}
  end

  # ── Event handlers ───────────────────────────────────────────────

  # Boot-mode tick (matches current generation only)
  def handle_info({:timeout, _ref, {:tick, gen}}, %{mode: :boot, tick_gen: gen} = state) do
    new_tick_count = state.tick_count + 1
    new_state = %{state | tick_count: new_tick_count}

    # Leave the splash when either:
    #   1. the minimum splash time has elapsed AND WiFi has settled
    #      (connected or AP mode) AND we have at least one weather sample
    #      (or no locations were configured), or
    #   2. the absolute boot timeout has been reached.
    min_met = new_tick_count >= state.boot_min_ticks
    wifi_ready = new_state.wifi_status in [:connected, :ap_mode]
    weather_ok = state.weather_ready? or state.locations_empty?
    timed_out = new_tick_count >= state.boot_timeout_ticks

    if (min_met and wifi_ready and weather_ok) or timed_out do
      target = find_first_available_screen([])
      do_switch_to_running(new_state, target, [])
    else
      items = Screens.Splash.render(new_state)
      new_state = bump_tick(new_state)
      {:noreply, new_state, [{:push, items}]}
    end
  end

  # Running-mode tick (matches current generation only)
  def handle_info({:timeout, _ref, {:tick, gen}}, %{mode: :running, tick_gen: gen} = state) do
    result = state.screen.handle_info(:tick, state.screen_state)
    handle_tick_result(result, state)
  end

  # Stale tick — generation mismatch, or fired after cancel arrived too late.
  # Do NOT reschedule; the timer process already exited after delivering this.
  def handle_info({:timeout, _ref, {:tick, _}}, state) do
    {:noreply, state}
  end

  # Boot-mode wifi status
  def handle_info({:pub, [:wifi_wiz, :wifi_status], _from, status}, %{mode: :boot} = state) do
    Log.debugf("Display", "pub wifi_status status=~p mode=boot", [status])
    new_state = update_wifi_status(state, status)
    items = Screens.Splash.render(new_state)
    {:noreply, new_state, [{:push, items}]}
  end

  # Running-mode wifi status — re-render without rescheduling the tick
  def handle_info({:pub, [:wifi_wiz, :wifi_status], _from, status}, %{mode: :running} = state) do
    Log.debugf("Display", "pub wifi_status status=~p mode=running", [status])
    # Normalize the raw WifiWiz payload before forwarding so screens
    # always see {:connected, ip_4tuple} rather than {:connected, {ip, gateway}}.
    normalized = normalize_wifi_status(status)
    result = state.screen.handle_info({:wifi_status, normalized}, state.screen_state)
    handle_event_result(result, state)
  end

  # Weather ready: during boot, unblocks the splash gate. Once running
  # it's a no-op — the active screen reads from ETS on its own tick.
  def handle_info({:pub, [:weather_ready], _from, name}, %{mode: :boot} = state) do
    Log.debugf("Display", "pub weather_ready name=~p boot unblocked", [name])
    new_state = %{state | weather_ready?: true}
    items = Screens.Splash.render(new_state)
    {:noreply, new_state, [{:push, items}]}
  end

  def handle_info({:pub, [:weather_ready], _from, name}, state) do
    Log.debugf("Display", "pub weather_ready name=~p ignored (running)", [name])
    {:noreply, state}
  end

  # Weather data is forwarded to the active screen so it can re-render
  # immediately if the update is relevant to what's on screen.
  # Re-rendered without rescheduling the tick to avoid minting extra timers.
  def handle_info({:pub, [:weather_data], _from, name}, %{mode: :running} = state) do
    Log.debugf("Display", "pub weather_data name=~p", [name])
    result = state.screen.handle_info({:weather_data, name}, state.screen_state)
    handle_event_result(result, state)
  end

  def handle_info({:pub, [:weather_data], _from, name}, state) do
    Log.debugf("Display", "pub weather_data name=~p ignored (boot)", [name])
    {:noreply, state}
  end

  # Screen requests during boot are ignored
  def handle_info(
        {:pub, [:screen_request], _from, {:switch, module, _args}},
        %{mode: :boot} = state
      ) do
    Log.debugf("Display", "pub screen_request module=~p ignored (boot)", [module])
    {:noreply, state}
  end

  def handle_info(
        {:pub, [:screen_request], _from, {:switch, module, args}},
        %{mode: :running} = state
      ) do
    Log.debugf("Display", "pub screen_request module=~p", [module])
    do_switch(state, module, args)
  end

  # Button short press during boot is ignored
  def handle_info({:pub, [:next_screen], _from, :boot_button_pressed}, %{mode: :boot} = state) do
    Log.debug("Display", "pub next_screen ignored (boot)")
    {:noreply, state}
  end

  # Button short press in running mode cycles to the next available screen
  def handle_info({:pub, [:next_screen], _from, :boot_button_pressed}, %{mode: :running} = state) do
    next = cycle_screen(state.screen)
    Log.debugf("Display", "pub next_screen cycling -> ~p", [next])
    do_switch(state, next, [])
  end

  # Auto-rotation timer (matches current generation only)
  def handle_info({:timeout, _ref, {:rotate, gen}}, %{mode: :running, rotate_gen: gen} = state) do
    next = cycle_screen(state.screen)
    Log.debugf("Display", "rotate -> ~p", [next])
    do_switch(state, next, [])
  end

  # Stale rotate — ignore.
  def handle_info({:timeout, _ref, {:rotate, _}}, state) do
    {:noreply, state}
  end

  # Catch-all for running mode — out-of-band messages forwarded to screen
  # without rescheduling the tick.
  def handle_info(msg, %{mode: :running} = state) do
    result = state.screen.handle_info(msg, state.screen_state)
    handle_event_result(result, state)
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Screen result helpers ──────────────────────────────────────

  # handle_tick_result: called only from the `:tick` path.
  # Bumps tick_gen to schedule the next tick at the (possibly new) rate.
  defp handle_tick_result({:noreply, new_screen_state}, state) do
    new_state = bump_tick(%{state | screen_state: new_screen_state})
    {:noreply, new_state}
  end

  defp handle_tick_result({:noreply, new_screen_state, opts}, state) do
    tick_ms = Keyword.get(opts, :tick_ms, state.tick_ms)
    scene_opts = Keyword.delete(opts, :tick_ms)
    new_state = bump_tick(%{state | screen_state: new_screen_state, tick_ms: tick_ms})

    case scene_opts do
      [] -> {:noreply, new_state}
      _ -> {:noreply, new_state, scene_opts}
    end
  end

  defp handle_tick_result({:switch, module, args}, state) do
    do_switch(state, module, args)
  end

  # handle_event_result: called for out-of-band events (wifi_status, weather_data,
  # button, unknown messages).  Updates screen_state and optionally pushes a new
  # frame, but does NOT reschedule the tick — the already-pending {:tick, gen}
  # continues on its current cadence.  This prevents each pubsub event from
  # minting a new orphaned timer process.
  defp handle_event_result({:noreply, new_screen_state}, state) do
    {:noreply, %{state | screen_state: new_screen_state}}
  end

  defp handle_event_result({:noreply, new_screen_state, opts}, state) do
    tick_ms = Keyword.get(opts, :tick_ms, state.tick_ms)
    scene_opts = Keyword.delete(opts, :tick_ms)
    new_state = %{state | screen_state: new_screen_state, tick_ms: tick_ms}

    case scene_opts do
      [] -> {:noreply, new_state}
      _ -> {:noreply, new_state, scene_opts}
    end
  end

  defp handle_event_result({:switch, module, args}, state) do
    do_switch(state, module, args)
  end

  # ── Screen switching ───────────────────────────────────────────

  defp do_switch_to_running(state, module, args) do
    Log.debugf("Display", "boot complete, switching to ~p", [module])

    {screen_state, tick_ms} = module.init(args)
    items = module.render(screen_state)

    new_state =
      %{
        state
        | mode: :running,
          screen: module,
          screen_state: screen_state,
          tick_ms: tick_ms,
          tick_count: 0
      }
      |> bump_tick()
      |> bump_rotate()

    {:noreply, new_state, [{:push, items}]}
  end

  defp do_switch(state, module, args) do
    heap = :erlang.system_info(:esp32_free_heap_size)
    procs = :erlang.system_info(:process_count)
    Log.debugf("Display", "heap=~pB procs=~p screen=~p", [heap, procs, module])

    {screen_state, tick_ms} = module.init(args)
    items = module.render(screen_state)

    new_state =
      %{
        state
        | screen: module,
          screen_state: screen_state,
          tick_ms: tick_ms
      }
      |> bump_tick()
      |> bump_rotate()

    {:noreply, new_state, [{:push, items}]}
  end

  # ── Timer generation helpers ──────────────────────────────────

  # Increments tick_gen and schedules a new {:tick, new_gen} via start_timer.
  #
  # Using erlang:start_timer/3 (not send_after/3) because start_timer registers
  # the ref in timer_manager, so erlang:cancel_timer/1 can actually kill the
  # spawned process immediately.  send_after returns a disconnected make_ref()
  # that cancel_timer cannot find — cancellation is a no-op for send_after.
  #
  # Generation tokens remain as a second layer: if a {:timeout, ref, {:tick, gen}}
  # arrives after a bump (race between fire and cancel), the stale-gen catch-all
  # discards it without rescheduling.
  defp bump_tick(%{tick_ms: tick_ms} = state) when tick_ms > 0 do
    gen = state.tick_gen + 1
    :erlang.start_timer(tick_ms, self(), {:tick, gen})
    %{state | tick_gen: gen}
  end

  defp bump_tick(state), do: state

  # Increments rotate_gen and schedules a new {:rotate, new_gen} via start_timer.
  defp bump_rotate(state) do
    gen = state.rotate_gen + 1
    :erlang.start_timer(@rotate_ms, self(), {:rotate, gen})
    %{state | rotate_gen: gen}
  end

  # ── Screen discovery ──────────────────────────────────────────

  # True when no weather locations are configured (weather screen will
  # be skipped and the boot gate doesn't wait for a fetch).
  defp locations_empty? do
    DisplayState.get(:weather, :locations, []) == []
  end

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

  # Normalize raw WifiWiz payload: {:connected, {ip, gateway}} → {:connected, ip}.
  # Screens and helpers always receive a bare 4-tuple IP, never the {ip, gateway} pair.
  defp normalize_wifi_status({:connected, {ip, _gateway}}), do: {:connected, ip}
  defp normalize_wifi_status(status), do: status

  # WifiWiz publishes {:connected, {ip, gateway}}; strip the gateway so
  # the rest of Display (and the Splash renderer) see a bare 4-tuple IP.
  defp update_wifi_status(state, {:connected, {ip, _gateway}}) do
    %{state | wifi_status: :connected, wifi_ip: ip}
  end

  defp update_wifi_status(state, {:ap_mode, ap_ssid}) do
    %{state | wifi_status: :ap_mode, wifi_ip: nil, wifi_ap_ssid: ap_ssid}
  end

  defp update_wifi_status(state, :connecting) do
    %{state | wifi_status: :connecting}
  end

  defp update_wifi_status(state, _other) do
    # Covers :disconnected (published by WifiWiz), :connecting, and any
    # future unknown status atoms.  Clearing wifi_ip ensures the splash and
    # screens don't keep showing a stale IP after the connection drops.
    %{state | wifi_status: nil, wifi_ip: nil}
  end

  def wipe(display, width \\ 128, height \\ 64) do
    AVMPort.call(display, {:update, [{:rect, 0, 0, width, height, 0x000000}]})
  end
end
