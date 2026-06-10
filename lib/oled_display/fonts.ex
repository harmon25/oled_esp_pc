defmodule OledDisplay.Fonts do
  @moduledoc """
  Compile-time font registry.

  Scans `assets/fonts/*.uff` at compile time, embeds them as module attributes,
  and exposes `all/0` so `Display.start_link/1` can register every custom font
  with the AtomGL port in one loop.

  Atom names are taken from the alias map when a matching stem is found;
  otherwise the filename stem (without `.uff`) is converted to an atom.

  Each `.uff` file is marked as `@external_resource` so Mix recompiles this
  module (and anything that depends on it) whenever a font changes.
  """

  @fonts_dir Path.join(__DIR__, "../../assets/fonts") |> Path.expand()

  # Alias map: filename stem → short atom used in display lists
  @aliases %{
    "spleen_6x12"  => :small,
    "spleen_8x16"  => :medium,
    "spleen_12x24" => :large
  }

  @fonts (for path <- Path.wildcard(Path.join(@fonts_dir, "*.uff")) do
            stem = Path.basename(path, ".uff")
            atom = Map.get(@aliases, stem, String.to_atom(stem))
            @external_resource path
            {atom, File.read!(path)}
          end)

  @doc """
  Returns a list of `{font_atom, binary}` tuples for every `.uff` found in
  `assets/fonts/`.

  Example:

      iex> OledDisplay.Fonts.all()
      [
        {:small, <<...>>},
        {:medium, <<...>>},
        {:large, <<...>>}
      ]
  """
  def all, do: @fonts
end
