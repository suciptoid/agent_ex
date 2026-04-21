defmodule App.Repo.Migrations.AddProviderFieldsForAlloy do
  use Ecto.Migration

  def change do
    alter table(:providers) do
      add :base_url, :string
    end

    # Strip the "provider:" prefix from agent model field
    execute """
            UPDATE agents SET model = SUBSTRING(model FROM POSITION(':' IN model) + 1)
            WHERE model LIKE '%:%'
            """,
            "SELECT 1"
  end
end
