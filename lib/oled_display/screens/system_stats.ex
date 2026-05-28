defmodule OledDisplay.Screens.SystemStats do
  @moduledoc """
  System statistics screen.

  Shows WiFi status (forced disconnected for now), uptime, heap, and
  process count. Ticks every 800 ms for smooth second updates.
  """

  @behaviour OledDisplay.Screen

  alias OledDisplay.IconData

  @bg 0x000000
  @fg 0xFFFFFF

  @tick_ms 1000

  # ── Screen behaviour ───────────────────────────────────────────

  @impl true
  def init(_args) do
    state = %{
      wifi_status: :disconnected,
      uptime_sec: 0,
      heap: fetch_heap(),
      procs: fetch_procs()
    }

    {state, @tick_ms}
  end

  @impl true
  def render(state) do
    wifi_icon =
      if state.wifi_status == :connected do
        IconData.get(:wifi1)
      else
        IconData.get(:wifi_off)
      end

    uptime = format_uptime(state.uptime_sec)
    heap = format_heap(state.heap)
    procs = format_procs(state.procs)

    items = [
      # Row 1: WiFi icon (left) + up-arrow icon + uptime (right)
      {:text, 66, 2, :default16px, @fg, :transparent, uptime},
      {:image, 48, 2, :transparent, IconData.get(:up_arrow)},
      {:image, 2, 2, :transparent, wifi_icon},
      # Row 2: Heap
      {:text, 2, 22, :default16px, @fg, :transparent, heap},
      # Row 3: Procs
      {:text, 2, 40, :default16px, @fg, :transparent, procs},
      # Background
      {:rect, 0, 0, 128, 64, @bg}
    ]

    items
  end

  @impl true
  def handle_info(:tick, state) do
    new_state = %{
      state
      | uptime_sec: state.uptime_sec + 1,
        heap: fetch_heap(),
        procs: fetch_procs()
    }

    {:noreply, new_state, [{:push, render(new_state)}]}
  end

  def handle_info({:wifi_status, _status}, state) do
    # Ignored for now — always show disconnected.
    # Future: update to %{state | wifi_status: status}
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp fetch_heap do
    # :erlang.memory/0 is not available on AtomVM, so fall back to
    # :erlang.process_info/2 which returns {:total_heap_size, words}.
    try do
      {:total_heap_size, words} = :erlang.process_info(self(), :total_heap_size)
      # Convert words → bytes on 32-bit ESP32-C3, then → kB
      div(words * 4, 1024)
    catch
      _, _ -> nil
    end
  end

  defp fetch_procs do
    try do
      :erlang.system_info(:process_count)
    catch
      _, _ -> nil
    end
  end

  defp format_uptime(sec) do
    h = div(sec, 3600) |> rem(24)
    m = div(sec, 60) |> rem(60)
    s = rem(sec, 60)
    pad = fn n -> if n < 10, do: "0#{n}", else: Integer.to_string(n) end
    "#{pad.(h)}:#{pad.(m)}:#{pad.(s)}"
  end

  defp format_heap(nil), do: "Heap: N/A"
  defp format_heap(kb), do: "Heap: #{kb}k"

  defp format_procs(nil), do: "Procs: N/A"
  defp format_procs(n), do: "Procs: #{n}"
end
