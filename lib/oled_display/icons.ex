defmodule OledDisplay.Icons do
  @moduledoc """
  Text symbols for inline use with registered fonts.

  All registered fonts (Spleen small/medium/large) include ASCII (U+0020-007E)
  plus the degree sign (U+00B0). Weather and system icons are rendered as
  16×16 RGBA images via the IconData module — not as font glyphs.
  """

  # Unicode symbols included in all Spleen font variants
  @degree "°"  # U+00B0 - included in all registered fonts

  @doc """
  Get the degree symbol for temperature formatting.
  
  Example:
      "22" <> Icons.get(:degree) <> "C"  # => "22°C"
  """
  def get(:degree), do: @degree
end
