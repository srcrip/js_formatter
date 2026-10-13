defmodule JsFormatter.Error do
  @moduledoc """
  Raised when a configured JavaScript formatter or linter cannot process a
  colocated script.
  """

  defexception [:message]
end
