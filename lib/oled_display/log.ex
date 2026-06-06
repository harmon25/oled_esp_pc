defmodule OledDisplay.Log do
  @moduledoc """
  Compile-time switchable logger for AtomVM.

  Controlled by a single config key:

      # config/config.exs
      config :oled_display, :log_enabled, true   # false = zero runtime cost

  When disabled, all macros expand to `:ok` literals. The compiler
  eliminates them entirely — no string interpolation, no format calls,
  no allocations at all.

  Uses `:io.format` directly rather than `IO.puts` for compatibility
  with AtomVM's UART driver.

  ## Usage

      require OledDisplay.Log
      alias OledDisplay.Log

      Log.debug("Weather", "wifi connected")
      Log.debugf("Display", "heap=~p mode=~p", [heap, mode])
  """

  @enabled Application.compile_env(:oled_display, :log_enabled, false)

  @doc """
  Log a plain string message.

      Log.debug("Weather", "wifi connected")
      # → [Weather] wifi connected
  """
  defmacro debug(tag, msg) do
    if @enabled do
      quote do
        :io.format("[~s] ~s~n", [unquote(tag), unquote(msg)])
      end
    else
      quote do: :ok
    end
  end

  @doc """
  Log a formatted message using :io.format-style placeholders.

      Log.debugf("Display", "heap=~p mode=~p", [heap, mode])
      # → [Display] heap=52300 mode=running
  """
  defmacro debugf(tag, fmt, args) do
    if @enabled do
      quote do
        :io.format("[~s] " <> unquote(fmt) <> "~n", [unquote(tag) | unquote(args)])
      end
    else
      quote do: :ok
    end
  end
end
