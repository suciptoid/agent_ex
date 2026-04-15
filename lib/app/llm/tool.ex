defmodule App.LLM.Tool do
  @moduledoc false

  alias App.LLM.ToolName

  @enforce_keys [:name, :description, :input_schema, :callback]
  defstruct [:name, :description, :input_schema, :callback]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          input_schema: map(),
          callback: (map() -> {:ok, term()} | {:error, term()})
        }

  @spec build(keyword()) :: t()
  def build(opts) when is_list(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      description: Keyword.fetch!(opts, :description),
      input_schema: Keyword.fetch!(opts, :input_schema),
      callback: Keyword.fetch!(opts, :callback)
    }
  end

  @spec execute(t(), map()) :: {:ok, term()} | {:error, term()}
  def execute(%__MODULE__{callback: callback}, args)
      when is_function(callback, 1) and is_map(args) do
    callback.(args)
  end

  def execute(%__MODULE__{}, _args), do: {:error, "Invalid tool arguments"}

  @spec valid_name?(term()) :: boolean()
  def valid_name?(value), do: ToolName.valid?(value)
end
