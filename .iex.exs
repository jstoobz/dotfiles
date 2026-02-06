global_settings = "~/.iex.exs"
if File.exists?(global_settings), do: Code.require_file(global_settings)

Application.put_env(:elixir, :ansi_enabled, true)

IEx.configure(
  inspect: [limit: :infinity],
  colors: [
    eval_result: [:cyan, :bright],
    eval_error: [[:red, :bright, "\nbrrp\n"]],
    eval_info: [:yellow, :bright]
  ],
  default_prompt:
    [
      "\e[G",
      :blue,
      "%prefix",
      :yellow,
      "|",
      :blue,
      "%counter",
      " ",
      :yellow,
      "brrp",
      :magenta,
      " >",
      :reset
    ]
    |> IO.ANSI.format()
    |> IO.chardata_to_string()
)
