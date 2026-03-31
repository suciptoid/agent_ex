defmodule App.Repo.Migrations.CreateTools do
  use Ecto.Migration

  def change do
    create table(:tools, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string, null: false
      add :kind, :string, null: false, default: "http"
      add :endpoint, :string, null: false
      add :http_method, :string, null: false, default: "get"
      add :parameter_definitions, :map, null: false, default: %{}
      add :static_headers, :binary
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:tools, [:user_id])
    create unique_index(:tools, [:user_id, :name], name: :tools_user_id_name_index)
  end
end
