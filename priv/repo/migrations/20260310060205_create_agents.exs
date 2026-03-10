defmodule App.Repo.Migrations.CreateAgents do
  use Ecto.Migration

  def change do
    create table(:agents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :system_prompt, :text
      add :model, :string, null: false

      add :provider_id, references(:providers, type: :binary_id, on_delete: :restrict),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :extra_params, :map, default: %{}, null: false
      add :tools, {:array, :string}, default: [], null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:agents, [:user_id])
    create index(:agents, [:provider_id])
  end
end
