defmodule OledDisplay.Screens.SystemStats do
  @moduledoc """
  System statistics screen (cozette font, 13px line height).

  y=0  [wifi][up_arrow]              00:00:00   16px icons, uptime right-aligned
  y=18 128k free  45k min                       free + min heap
  y=30 Procs: 14                                process count
  y=42 192.168.25.198                           IP / wifi status
  """

  @behaviour OledDisplay.Screen

  alias OledDisplay.IconData

  @bg 0x000000
  @fg 0xFFFFFF

  @font :cozette
  # Cozette 6×13 → advance_x=6px per char
  @char_w 6

  @tick_ms 1000

  # ── Screen behaviour ───────────────────────────────────────────

  @impl true
  def init(_args) do
    state = %{
      wifi_connected: false,
      wifi_ip: nil,
      uptime_sec: 0,
      heap_kb: fetch_heap(),
      min_heap_kb: fetch_min_heap(),
      procs: fetch_procs()
    }

    {state, @tick_ms}
  end

  @impl true
  def render(state) do
    wifi_icon =
      if state.wifi_connected,
        do: IconData.get(:wifi1),
        else: IconData.get(:wifi_off)

    uptime   = format_uptime(state.uptime_sec)
    heap     = format_heap(state.heap_kb)
    min_heap = format_min_heap(state.min_heap_kb)
    procs    = format_procs(state.procs)
    ip_line  = format_ip(state.wifi_connected, state.wifi_ip)

    # right-align uptime: "HH:MM:SS" is always 8 chars
    uptime_x = 128 - 8 * @char_w

    [
      # Row 0: wifi icon left, up-arrow + uptime right-aligned
      {:image, 0,           0, @bg, wifi_icon},
      {:image, uptime_x - 16, 0, @bg, IconData.get(:up_arrow)},
      {:text,  uptime_x,    2, @font, @fg, :transparent, uptime},
      # Row 1: free heap + min heap
      {:text,  0, 18, @font, @fg, :transparent, heap},
      {:text, 64, 18, @font, @fg, :transparent, min_heap},
      # Row 2: process count
      {:text, 0, 30, @font, @fg, :transparent, procs},
      # Row 3: IP / status
      {:text, 0, 42, @font, @fg, :transparent, ip_line},
      # Background (rendered last in list = drawn first by AtomGL)
      {:rect, 0, 0, 128, 64, @bg}
    ]
  end

  @impl true
  def handle_info(:tick, state) do
    {wifi_connected, wifi_ip} = OledDisplay.WiFi.status()

    new_state = %{
      state
      | uptime_sec: state.uptime_sec + 1,
        heap_kb: fetch_heap(),
        min_heap_kb: fetch_min_heap(),
        procs: fetch_procs(),
        wifi_connected: wifi_connected,
        wifi_ip: wifi_ip
    }

    {:noreply, new_state, [{:push, render(new_state)}]}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp fetch_heap do
    try do
      div(:erlang.system_info(:esp32_free_heap_size), 1024)
    catch
      _, _ -> nil
    end
  end

  defp fetch_min_heap do
    try do
      div(:erlang.system_info(:esp32_minimum_free_size), 1024)
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

  defp format_heap(nil), do: "free:N/A"
  defp format_heap(kb),  do: "#{kb}k free"

  defp format_min_heap(nil), do: "min:N/A"
  defp format_min_heap(kb),  do: "#{kb}k min"

  defp format_procs(nil), do: "Procs: N/A"
  defp format_procs(n),   do: "Procs: #{n}"

  defp format_ip(false, _),         do: "No WiFi"
  defp format_ip(true, nil),        do: "..."
  defp format_ip(true, {a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
end
