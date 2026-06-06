defmodule OledDisplay.Button do
  @compile {:no_warn_undefined, [:gpio, :avm_pubsub]}

  @gpio_pin 9
  @debounce_ms 50
  @long_press_ms 2000

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
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    gpio = :gpio.start()
    :gpio.set_pin_mode(@gpio_pin, :input)
    :gpio.set_pin_pull(@gpio_pin, :up)
    :gpio.set_int(gpio, @gpio_pin, :both)

    # lp_gen is a generation counter for the long-press timer.
    # :erlang.cancel_timer/1 is a no-op on AtomVM (the ref returned by
    # Process.send_after is disconnected from the actual timer process).
    # Instead, bumping lp_gen invalidates any pending {:long_press_check, old_gen}.
    {:ok, %{gpio: gpio, state: :idle, lp_gen: 0}}
  end

  def handle_info({:gpio_interrupt, @gpio_pin}, %{state: :idle} = state) do
    :erlang.start_timer(@debounce_ms, self(), :debounce)
    {:noreply, %{state | state: :debouncing}}
  end

  def handle_info({:gpio_interrupt, @gpio_pin}, %{state: :pressed} = state) do
    # Short press: bump lp_gen to invalidate the pending long-press timer.
    # The orphaned {:long_press_check, old_gen} will be ignored when it fires.
    IO.puts("Button short press")
    :avm_pubsub.pub(:pubsub, [:next_screen], :boot_button_pressed)
    {:noreply, %{state | state: :idle, lp_gen: state.lp_gen + 1}}
  end

  def handle_info({:gpio_interrupt, @gpio_pin}, %{state: :long_press_done} = state) do
    {:noreply, %{state | state: :idle}}
  end

  def handle_info({:gpio_interrupt, _pin}, state) do
    {:noreply, state}
  end

  def handle_info({:timeout, _ref, :debounce}, %{state: :debouncing} = state) do
    case :gpio.digital_read(@gpio_pin) do
      :low ->
        # Schedule long-press check via start_timer so cancel_timer works.
        gen = state.lp_gen + 1
        :erlang.start_timer(@long_press_ms, self(), {:long_press_check, gen})
        {:noreply, %{state | state: :pressed, lp_gen: gen}}

      :high ->
        {:noreply, %{state | state: :idle}}
    end
  end

  # Long-press check — acts only for the current generation.
  def handle_info({:timeout, _ref, {:long_press_check, gen}}, %{state: :pressed, lp_gen: gen} = state) do
    case :gpio.digital_read(@gpio_pin) do
      :low ->
        IO.puts("Button long press")
        :avm_pubsub.pub(:pubsub, [:clear_wifi_creds], :boot_button_held)
        {:noreply, %{state | state: :long_press_done}}

      :high ->
        {:noreply, %{state | state: :idle}}
    end
  end

  # Stale long-press timer — generation bumped by a short press before this fired.
  def handle_info({:timeout, _ref, {:long_press_check, _}}, state) do
    {:noreply, state}
  end
end
