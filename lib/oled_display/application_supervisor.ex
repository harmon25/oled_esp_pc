defmodule OledDisplay.ApplicationSupervisor do
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    :avm_pubsub.start(:pubsub)

    children = [
      {OledDisplay.WiFi, []},
      {OledDisplay.Display, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
