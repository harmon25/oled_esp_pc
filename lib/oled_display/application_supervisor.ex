defmodule OledDisplay.ApplicationSupervisor do
  use Supervisor
  require OledDisplay.Log
  alias OledDisplay.Log

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    Log.debug("ApplicationSupervisor", "Starting application supervisor")
    # The display port handle was opened once in OledDisplay.start/0 and
    # lives for the full device uptime. We thread it into Display here so
    # that supervised restarts of Display never attempt to re-open I2C.
    display = Keyword.fetch!(opts, :display)

    children = [
      # DisplayState (ETS owner) must start first. :rest_for_one means
      # that if it crashes everything below it restarts too, keeping the
      # ETS contract consistent.
      OledDisplay.DisplayState,
      {OledDisplay.WiFi, []},
      {OledDisplay.Weather, []},
      {OledDisplay.Display, [display: display]},
      {OledDisplay.Button, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
