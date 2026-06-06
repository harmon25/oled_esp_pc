defmodule OledDisplay.Screens.Splash do
  @moduledoc """
  Pure renderer for the boot-phase splash screen.

  Not a normal Screen — it has no init/1, handle_info/2, or autonomous
  switching logic. Display drives the boot phase and calls render/1
  directly with the current boot state.
  """

  @bg 0x000000
  @fg 0xFFFFFF
  @track 0x333333

  @doc """
  Render splash given boot state.

  Expected keys in `state`:
    - `:tick_count` — current tick counter for progress bar
    - `:boot_min_ticks` — total ticks for a full bar
    - `:wifi_status` — `:connecting`, `:connected`, `:ap_mode`, or `nil`
    - `:wifi_ip` — tuple like `{192,168,1,5}` or `nil`
    - `:wifi_ap_ssid` — string or `nil`
    - `:weather_ready?` — boolean
    - `:locations_empty?` — boolean
  """
  def render(state) do
    text_items(state) ++ loading_bar(state) ++ [{:rect, 0, 0, 128, 64, @bg}]
  end

  # ── Private ──────────────────────────────────────────────────────

  defp text_items(state) do
    # Build a list of {y, text} rows for any non-nil status lines, then
    # turn them into AtomGL text items. This keeps the layout flat and
    # makes adding a new boot-status line a one-liner.
    rows =
      [
        {12, "AtomVM | Elixir"},
        {24, wifi_text(state)},
        {34, weather_text(state)}
      ]
      |> Enum.reject(fn {_y, text} -> is_nil(text) end)

    Enum.map(rows, fn {y, text} ->
      {:text, 4, y, :spleen5x8, @fg, :transparent, text}
    end)
  end

  defp wifi_text(%{wifi_status: :connecting}), do: "WiFi..."

  defp wifi_text(%{wifi_status: :connected, wifi_ip: {a, b, c, d}}) do
    "IP: #{a}.#{b}.#{c}.#{d}"
  end

  defp wifi_text(%{wifi_status: :ap_mode, wifi_ap_ssid: ssid}) when is_binary(ssid) do
    "AP: #{ssid}"
  end

  defp wifi_text(_), do: nil

  defp weather_text(%{locations_empty?: true}), do: nil
  defp weather_text(%{weather_ready?: true}), do: "Weather OK"
  defp weather_text(%{wifi_status: :connected}), do: "Fetching weather..."
  defp weather_text(_), do: nil

  defp loading_bar(state) do
    track = {:rect, 14, 56, 100, 3, @track}

    max_w = 100
    total = state.boot_min_ticks
    current = min(state.tick_count, total)
    fill_w = div(current * max_w, total)
    fill_w = min(fill_w, max_w)

    fill =
      if fill_w > 0 do
        [{:rect, 14, 56, fill_w, 3, @fg}]
      else
        []
      end

    fill ++ [track]
  end
end
