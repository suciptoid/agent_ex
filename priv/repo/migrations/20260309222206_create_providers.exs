defmodule App.Repo.Migrations.CreateProviders do
  use Ecto.Migration

  def change do
    create table(:providers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :provider, :string, null: false
      add :api_key, :binary, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:providers, [:user_id])
    create index(:providers, [:user_id, :provider])
  end
end
