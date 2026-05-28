defmodule OledDisplay.Screen do
  @moduledoc """
  Behaviour for a display screen.

  Each screen module implements this behaviour. The Display GenServer
  routes ticks and pubsub messages to the active screen and handles
  screen-switching via the return values.
  """

  @doc """
  Initialize screen state.

  Returns `{state, tick_ms}` where `tick_ms` controls the tick interval
  while this screen is active (0 disables ticks).
  """
  @callback init(args :: term()) :: {state :: term(), tick_ms :: non_neg_integer()}

  @doc """
  Build the full display-item list for the current state.
  Items are returned in draw order (first = topmost, last = background).
  The caller appends the full-screen rect as the last item.
  """
  @callback render(state :: term()) :: list()

  @doc """
  Handle incoming messages (tick, pubsub, etc.).

  Return values:
  - `{:noreply, state}` — state updated, no display push
  - `{:noreply, state, [{:push, items}]}` — push new display list
  - `{:switch, module, args}` — request Display to switch to another screen
  """
  @callback handle_info(msg :: term(), state :: term()) ::
              {:noreply, state :: term()}
              | {:noreply, state :: term(), [{:push, items :: list()}]}
              | {:switch, module :: atom(), args :: term()}
end
