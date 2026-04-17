defmodule App.Repo.Migrations.AddProviderFieldsForAlloy do
  use Ecto.Migration

  def change do
    alter table(:providers) do
      add :base_url, :string
      add :provider_type, :string
    end

    # Backfill provider_type from existing provider field
    flush()

    execute """
            UPDATE providers SET provider_type = CASE
              WHEN provider IN ('anthropic') THEN 'anthropic'
              WHEN provider IN ('openai') THEN 'openai'
              ELSE 'openai_compat'
            END
            WHERE provider_type IS NULL
            """,
            "SELECT 1"

    # Strip the "provider:" prefix from agent model field
    execute """
            UPDATE agents SET model = SUBSTRING(model FROM POSITION(':' IN model) + 1)
            WHERE model LIKE '%:%'
            """,
            "SELECT 1"
  end
end
