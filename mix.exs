defmodule OledDisplay.MixProject do
  use Mix.Project

  def project do
    [
      app: :oled_display,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      atomvm: [
        start: OledDisplay,
        flash_offset: 0x250000
      ]
    ]
  end

  def application do
    [
      extra_applications: []
    ]
  end

  defp deps do
    [
      {:exatomvm, github: "atomvm/ExAtomVM", runtime: false},
      {:wifi_wiz, github: "harmon25/wifi_wiz", branch: "scan"}
    ]
  end
end
