defmodule OledDisplay.Screens.Splash do
  @moduledoc """
  Splash screen with a fake loading bar.

  Configurable duration via `@splash_duration_ms`. Renders at 200 ms
  tick intervals for smooth bar animation, then switches to
  `OledDisplay.Screens.SystemStats`.
  """

  @behaviour OledDisplay.Screen

  @splash_duration_ms 2000
  @tick_ms 200

  @bg 0x000000
  @fg 0xFFFFFF
  @track 0x333333

  # ── Screen behaviour ───────────────────────────────────────────

  @impl true
  def init(_args) do
    duration_ticks = div(@splash_duration_ms, @tick_ms)
    state = %{tick_count: 0, duration_ticks: duration_ticks, tick_ms: @tick_ms}
    {state, @tick_ms}
  end

  @impl true
  def render(state) do
    text_items() ++ loading_bar(state) ++ [{:rect, 0, 0, 128, 64, @bg}]
  end

  @impl true
  def handle_info(:tick, state) do
    next_count = state.tick_count + 1

    if next_count >= state.duration_ticks do
      {:switch, OledDisplay.Screens.SystemStats, []}
    else
      new_state = %{state | tick_count: next_count}
      {:noreply, new_state, [{:push, render(new_state)}]}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Private ──────────────────────────────────────────────────────

  defp text_items do
    [
      {:text, 4, 16, :default16px, @fg, :transparent, "AtomVM | Elixir"}    ]
  end

  defp loading_bar(state) do
    track = {:rect, 14, 58, 100, 3, @track}

    max_w = 100
    fill_w = div(state.tick_count * max_w, state.duration_ticks)
    fill_w = min(fill_w, max_w)

    fill =
      if fill_w > 0 do
        [{:rect, 14, 58, fill_w, 3, @fg}]
      else
        []
      end

    fill ++ [track]
  end
end
