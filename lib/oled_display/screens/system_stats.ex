defmodule OledDisplay.Screens.SystemStats do
  @moduledoc """
  System statistics screen (spleen5x8 font, 8px line height).

  y=0  [wifi][up_arrow]            0d 00:00   16px icons, uptime right-aligned
  y=18 128k free  45k min                     free + min heap
  y=30 Procs: 14                              process count
  y=42 IP / AP name / WiFi status             IP or AP SSID
  """

  @behaviour OledDisplay.Screen

  alias OledDisplay.DisplayState
  alias OledDisplay.IconData

  @bg 0x000000
  @fg 0xFFFFFF

  @font :spleen5x8
  # Spleen 5×8 → advance_x=5px per char
  @char_w 5

  @tick_ms 60_000

  # ── Screen behaviour ───────────────────────────────────────────

  @impl true
  def available?(_args), do: true

  @impl true
  def init(_args) do
    {wifi_connected, wifi_ip, wifi_ap_ssid} = OledDisplay.WiFi.status()

    # Seed the monotonic boot reference on first activation.
    # Uptime is computed fresh on every render as:
    #   div(monotonic_now - boot_ms, 60_000)
    # This is immune to SNTP clock jumps and works correctly even when
    # the screen is off-rotation (the tick may not fire every 60 s).
    boot_ms =
      case DisplayState.get(:sysstats, :boot_monotonic_ms) do
        nil ->
          t = :erlang.monotonic_time(:millisecond)
          DisplayState.put(:sysstats, :boot_monotonic_ms, t)
          t

        t ->
          t
      end

    state = %{
      wifi_connected: wifi_connected,
      wifi_ip: wifi_ip,
      wifi_ap_ssid: wifi_ap_ssid,
      boot_ms: boot_ms,
      heap_kb: DisplayState.get(:sysstats, :heap_kb) || fetch_heap(),
      min_heap_kb: DisplayState.get(:sysstats, :min_heap_kb) || fetch_min_heap(),
      procs: DisplayState.get(:sysstats, :procs) || fetch_procs()
    }

    {state, @tick_ms}
  end

  @impl true
  def render(state) do
    wifi_icon =
      if state.wifi_connected,
        do: IconData.get(:wifi1),
        else: IconData.get(:wifi_off)

    uptime = format_uptime(div(:erlang.monotonic_time(:millisecond) - state.boot_ms, 60_000))
    heap = format_heap(state.heap_kb)
    min_heap = format_min_heap(state.min_heap_kb)
    procs = format_procs(state.procs)
    ip_line = format_ip(state.wifi_connected, state.wifi_ip, state.wifi_ap_ssid)

    # right-align uptime: "Xd HH:MM" is always 9 chars
    uptime_x = 128 - 9 * @char_w

    [
      # Row 0: wifi icon left, up-arrow + uptime right-aligned
      {:image, 0, 0, @bg, wifi_icon},
      {:image, uptime_x - 16, 0, @bg, IconData.get(:up_arrow)},
      {:text, uptime_x, 2, @font, @fg, :transparent, uptime},
      # Row 1: free heap + min heap
      {:text, 0, 18, @font, @fg, :transparent, heap},
      {:text, 64, 18, @font, @fg, :transparent, min_heap},
      # Row 2: process count
      {:text, 0, 30, @font, @fg, :transparent, procs},
      # Row 3: IP / AP / status
      {:text, 0, 42, @font, @fg, :transparent, ip_line},
      # Background (rendered last in list = drawn first by AtomGL)
      {:rect, 0, 0, 128, 64, @bg}
    ]
  end

  @impl true
  def handle_info(:tick, state) do
    {wifi_connected, wifi_ip, wifi_ap_ssid} = OledDisplay.WiFi.status()

    new_state = %{
      state
      | heap_kb: fetch_heap(),
        min_heap_kb: fetch_min_heap(),
        procs: fetch_procs(),
        wifi_connected: wifi_connected,
        wifi_ip: wifi_ip,
        wifi_ap_ssid: wifi_ap_ssid
    }

    # Persist heap/proc counters to ETS so they can seed a fresh init
    DisplayState.put(:sysstats, :heap_kb, new_state.heap_kb)
    DisplayState.put(:sysstats, :min_heap_kb, new_state.min_heap_kb)
    DisplayState.put(:sysstats, :procs, new_state.procs)

    {:noreply, new_state, [{:push, render(new_state)}]}
  end

  def handle_info({:wifi_status, {:connected, ip}}, state) do
    # Clear any stale AP SSID — the device is connected to STA, not AP mode.
    new_state = %{state | wifi_connected: true, wifi_ip: ip, wifi_ap_ssid: nil}
    {:noreply, new_state, [{:push, render(new_state)}]}
  end

  def handle_info({:wifi_status, {:ap_mode, ap_ssid}}, state) do
    new_state = %{state | wifi_connected: false, wifi_ip: nil, wifi_ap_ssid: ap_ssid}
    {:noreply, new_state, [{:push, render(new_state)}]}
  end

  def handle_info({:wifi_status, _status}, state) do
    # Disconnected / connecting / retry — clear both IP and AP SSID.
    new_state = %{state | wifi_connected: false, wifi_ip: nil, wifi_ap_ssid: nil}
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

  defp format_uptime(min) do
    days = div(min, 1440)
    hours = div(min, 60) |> rem(24)
    mins = rem(min, 60)
    pad = fn n -> if n < 10, do: "0#{n}", else: Integer.to_string(n) end
    "#{days}d #{pad.(hours)}:#{pad.(mins)}"
  end

  defp format_heap(nil), do: "free:N/A"
  defp format_heap(kb), do: "#{kb}k free"

  defp format_min_heap(nil), do: "min:N/A"
  defp format_min_heap(kb), do: "min:#{kb}k"

  defp format_procs(nil), do: "Procs: N/A"
  defp format_procs(n), do: "Procs: #{n}"

  defp format_ip(true, nil, _), do: "..."
  defp format_ip(true, {a, b, c, d}, _), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip(false, _, nil), do: "Reconnecting..."
  defp format_ip(false, _, ap_ssid) when is_binary(ap_ssid), do: "AP: #{ap_ssid}"
end
