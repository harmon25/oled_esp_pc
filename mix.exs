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
      {:exatomvm, git: "https://github.com/atomvm/ExAtomVM.git", runtime: false}
    ]
  end
end
