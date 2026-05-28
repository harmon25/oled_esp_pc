defmodule OledDisplay.Button do
  @compile {:no_warn_undefined, [GPIO, :avm_pubsub]}

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

    {:ok, %{gpio: gpio, state: :idle, timer_ref: nil}}
  end

  def handle_info({:gpio_interrupt, @gpio_pin}, %{state: :idle} = state) do
    Process.send_after(self(), :debounce, @debounce_ms)
    {:noreply, %{state | state: :debouncing}}
  end

  def handle_info({:gpio_interrupt, @gpio_pin}, %{state: :pressed} = state) do
    if state.timer_ref do
      :erlang.cancel_timer(state.timer_ref)
    end

    IO.puts("Button short press")
    :avm_pubsub.pub(:pubsub, :next_screen, :boot_button_pressed)
    {:noreply, %{state | state: :idle, timer_ref: nil}}
  end

  def handle_info({:gpio_interrupt, @gpio_pin}, %{state: :long_press_done} = state) do
    {:noreply, %{state | state: :idle}}
  end

  def handle_info({:gpio_interrupt, _pin}, state) do
    {:noreply, state}
  end

  def handle_info(:debounce, %{state: :debouncing} = state) do
    case :gpio.digital_read(@gpio_pin) do
      :low ->
        timer_ref = Process.send_after(self(), :long_press_check, @long_press_ms)
        {:noreply, %{state | state: :pressed, timer_ref: timer_ref}}

      :high ->
        {:noreply, %{state | state: :idle}}
    end
  end

  def handle_info(:long_press_check, %{state: :pressed} = state) do
    case :gpio.digital_read(@gpio_pin) do
      :low ->
        IO.puts("Button long press")
        :avm_pubsub.pub(:pubsub, :clear_wifi_creds, :boot_button_held)
        {:noreply, %{state | state: :long_press_done, timer_ref: nil}}

      :high ->
        {:noreply, %{state | state: :idle, timer_ref: nil}}
    end
  end

  def handle_info(:long_press_check, state) do
    {:noreply, state}
  end
end
