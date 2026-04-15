defmodule App.Repo.Migrations.AddAlloyProviderFieldsAndModels do
  use Ecto.Migration

  def up do
    alter table(:providers) do
      add :adapter, :string
      add :base_url, :string
      add :models_path, :string
      add :chat_path, :string
      add :extra_headers, :binary
      add :models_last_refreshed_at, :utc_datetime_usec
      add :models_last_refresh_error, :string
    end

    flush()

    execute("""
    UPDATE providers
    SET adapter = CASE provider
      WHEN 'openai' THEN 'openai'
      WHEN 'anthropic' THEN 'anthropic'
      WHEN 'google' THEN 'gemini'
      WHEN 'xai' THEN 'openai'
      WHEN 'github_copilot' THEN 'openai_compat'
      ELSE COALESCE(NULLIF(provider, ''), 'openai_compat')
    END
    """)

    execute("""
    UPDATE providers
    SET base_url = CASE provider
      WHEN 'openai' THEN 'https://api.openai.com'
      WHEN 'anthropic' THEN 'https://api.anthropic.com'
      WHEN 'google' THEN 'https://generativelanguage.googleapis.com'
      WHEN 'xai' THEN 'https://api.x.ai'
      WHEN 'github_copilot' THEN 'https://api.githubcopilot.com'
      ELSE base_url
    END
    WHERE base_url IS NULL
    """)

    execute("""
    UPDATE providers
    SET models_path = '/v1/models'
    WHERE models_path IS NULL
    """)

    execute("""
    UPDATE providers
    SET chat_path = '/v1/chat/completions'
    WHERE chat_path IS NULL AND adapter IN ('openai_compat')
    """)

    create table(:provider_models, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :provider_id, references(:providers, type: :binary_id, on_delete: :delete_all),
        null: false

      add :model_id, :string, null: false
      add :name, :string
      add :supports_reasoning, :boolean, null: false, default: false
      add :context_window, :integer
      add :raw, :map, null: false, default: %{}
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:provider_models, [:provider_id])
    create index(:provider_models, [:provider_id, :status])

    create unique_index(:provider_models, [:provider_id, :model_id],
             name: :provider_models_provider_id_model_id_index
           )
  end

  def down do
    drop index(:provider_models, [:provider_id, :status])
    drop index(:provider_models, [:provider_id])

    drop index(:provider_models, [:provider_id, :model_id],
           name: :provider_models_provider_id_model_id_index
         )

    drop table(:provider_models)

    alter table(:providers) do
      remove :adapter
      remove :base_url
      remove :models_path
      remove :chat_path
      remove :extra_headers
      remove :models_last_refreshed_at
      remove :models_last_refresh_error
    end
  end
end
