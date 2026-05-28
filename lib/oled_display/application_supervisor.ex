defmodule OledDisplay.ApplicationSupervisor do
  @compile {:no_warn_undefined, [:avm_pubsub]}

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    :avm_pubsub.start(:pubsub)

    children = [
      {OledDisplay.Display, []},
      {OledDisplay.WiFi, []},
      {OledDisplay.Button, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
