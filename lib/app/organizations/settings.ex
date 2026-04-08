defmodule App.Organizations.Settings do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :default_agent_id, :binary_id
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:default_agent_id])
  end
end
