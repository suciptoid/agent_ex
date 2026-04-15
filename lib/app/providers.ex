defmodule App.Providers do
  @moduledoc """
  The Providers context for managing user LLM providers.
  """

  import Ecto.Query, warn: false

  alias App.Organizations.Membership
  alias App.Providers.Provider
  alias App.Providers.ProviderModel
  alias App.Repo
  alias App.Users.Scope
  alias App.Users.User
  alias Ecto.Multi

  @provider_templates [
    %{
      id: "openai",
      label: "OpenAI",
      adapter: "openai",
      base_url: "https://api.openai.com",
      models_path: "/v1/models",
      chat_path: nil
    },
    %{
      id: "anthropic",
      label: "Anthropic",
      adapter: "anthropic",
      base_url: "https://api.anthropic.com",
      models_path: "/v1/models",
      chat_path: nil
    },
    %{
      id: "google",
      label: "Google Gemini",
      adapter: "gemini",
      base_url: "https://generativelanguage.googleapis.com",
      models_path: "/v1/models",
      chat_path: nil
    },
    %{
      id: "xai",
      label: "xAI",
      adapter: "openai",
      base_url: "https://api.x.ai",
      models_path: "/v1/models",
      chat_path: nil
    },
    %{
      id: "github_copilot",
      label: "GitHub Copilot",
      adapter: "openai_compat",
      base_url: "https://api.githubcopilot.com",
      models_path: "/v1/models",
      chat_path: "/v1/chat/completions"
    },
    %{
      id: "openai_compat",
      label: "OpenAI Compatible",
      adapter: "openai_compat",
      base_url: "https://openrouter.ai",
      models_path: "/v1/models",
      chat_path: "/v1/chat/completions"
    },
    %{
      id: "custom_openai_compat",
      label: "Custom OpenAI Compatible",
      adapter: "openai_compat",
      base_url: nil,
      models_path: "/v1/models",
      chat_path: "/v1/chat/completions"
    }
  ]

  def list_providers(%Scope{} = scope) do
    Repo.all(
      from provider in Provider,
        where: provider.organization_id == ^Scope.organization_id!(scope),
        order_by: [asc: provider.name, asc: provider.inserted_at],
        preload: [provider_models: ^active_provider_models_query()]
    )
  end

  def count_providers(%Scope{} = scope) do
    Repo.aggregate(
      from(provider in Provider,
        where: provider.organization_id == ^Scope.organization_id!(scope)
      ),
      :count,
      :id
    )
  end

  def get_provider!(%Scope{} = scope, id) do
    Repo.get_by!(Provider, id: id, organization_id: Scope.organization_id!(scope))
    |> Repo.preload(provider_models: active_provider_models_query())
  end

  def get_provider(%Scope{} = scope, id) do
    Repo.get_by(Provider, id: id, organization_id: Scope.organization_id!(scope))
    |> maybe_preload_provider_models()
  end

  def get_provider_for_user(%User{} = user, id) do
    Provider
    |> join(:inner, [provider], membership in Membership,
      on: membership.organization_id == provider.organization_id
    )
    |> where([provider, membership], membership.user_id == ^user.id and provider.id == ^id)
    |> select([provider, _membership], provider)
    |> Repo.one()
    |> maybe_preload_provider_models()
  end

  def create_provider(%Scope{} = scope, attrs) do
    with :ok <- authorize_manager(scope) do
      attrs = apply_provider_defaults(attrs)

      result =
        %Provider{organization_id: Scope.organization_id!(scope)}
        |> Provider.changeset(attrs)
        |> Repo.insert()

      case result do
        {:ok, provider} ->
          {:ok, Repo.preload(provider, provider_models: active_provider_models_query())}

        {:error, _changeset} = error ->
          error
      end
    end
  end

  def update_provider(%Scope{} = scope, provider, attrs) do
    with :ok <- authorize_manager(scope),
         :ok <- ensure_organization_owns_provider(scope, provider) do
      attrs = apply_provider_defaults(attrs)

      provider
      |> Provider.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, updated_provider} ->
          updated_provider =
            Repo.preload(updated_provider, provider_models: active_provider_models_query())

          {:ok, updated_provider}

        {:error, _changeset} = error ->
          error
      end
    end
  end

  def delete_provider(%Scope{} = scope, provider) do
    with :ok <- authorize_manager(scope),
         :ok <- ensure_organization_owns_provider(scope, provider) do
      Repo.delete(provider)
    end
  end

  def change_provider(provider, attrs \\ %{}) do
    attrs = apply_provider_defaults(attrs)
    Provider.changeset(provider, attrs)
  end

  def provider_options do
    provider_name_map = provider_name_map()

    valid_provider_ids()
    |> Enum.sort_by(&provider_label(&1, provider_name_map))
    |> Enum.map(fn provider_id ->
      {provider_id, provider_label(provider_id, provider_name_map)}
    end)
  end

  def provider_templates, do: @provider_templates

  def provider_template(provider_id) when is_binary(provider_id) do
    Enum.find(@provider_templates, &(&1.id == provider_id))
  end

  def provider_template(_provider_id), do: nil

  def valid_provider_ids do
    @provider_templates
    |> Enum.map(& &1.id)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def valid_provider_values do
    valid_provider_ids()
  end

  def list_provider_models(%Provider{id: provider_id}) do
    Repo.all(
      from provider_model in ProviderModel,
        where: provider_model.provider_id == ^provider_id and provider_model.status == "active",
        order_by: [asc: provider_model.name, asc: provider_model.model_id]
    )
  end

  def list_provider_models(provider_id) when is_binary(provider_id) do
    Repo.all(
      from provider_model in ProviderModel,
        where: provider_model.provider_id == ^provider_id and provider_model.status == "active",
        order_by: [asc: provider_model.name, asc: provider_model.model_id]
    )
  end

  def list_provider_model_options(%Provider{} = provider) do
    provider
    |> list_provider_models()
    |> Enum.map(fn provider_model ->
      {provider_model.model_id, provider_model.name || provider_model.model_id}
    end)
  end

  def refresh_provider_models(%Scope{} = scope, provider_id) when is_binary(provider_id) do
    case get_provider(scope, provider_id) do
      nil -> {:error, :not_found}
      provider -> refresh_provider_models(scope, provider)
    end
  end

  def refresh_provider_models(%Scope{} = scope, %Provider{} = provider) do
    with :ok <- authorize_manager(scope),
         :ok <- ensure_organization_owns_provider(scope, provider),
         :ok <- ensure_refreshable_provider(provider),
         {:ok, models} <- fetch_provider_models(provider) do
      persist_provider_models(provider, models)
    else
      {:error, reason} = error ->
        maybe_persist_refresh_error(provider, reason)
        error
    end
  end

  def apply_provider_defaults(attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)
    provider_id = Map.get(attrs, "provider")
    template = provider_template(provider_id) || %{}

    attrs
    |> put_default("adapter", Map.get(template, :adapter))
    |> put_default("base_url", Map.get(template, :base_url))
    |> put_default("models_path", Map.get(template, :models_path, "/v1/models"))
    |> put_default("chat_path", Map.get(template, :chat_path))
  end

  def apply_provider_defaults(attrs), do: attrs

  defp ensure_refreshable_provider(%Provider{} = provider) do
    if provider.models_path in [nil, ""] do
      {:error, "Model refresh is not configured for this provider"}
    else
      :ok
    end
  end

  defp fetch_provider_models(%Provider{} = provider) do
    req_options = [headers: model_refresh_headers(provider)]

    url =
      provider.base_url
      |> to_string()
      |> String.trim_trailing("/")
      |> Kernel.<>(provider.models_path || "/v1/models")

    case Req.get(url, req_options) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        case parse_provider_models(body) do
          [] -> {:error, "No models returned from #{url}"}
          models -> {:ok, models}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "Model refresh failed with HTTP #{status}: #{short_body(body)}"}

      {:error, reason} ->
        {:error, "Model refresh request failed: #{inspect(reason)}"}
    end
  end

  defp parse_provider_models(body) when is_map(body) do
    body
    |> extract_model_items()
    |> Enum.map(&normalize_provider_model_item/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.model_id)
  end

  defp parse_provider_models(body) when is_list(body) do
    body
    |> Enum.map(&normalize_provider_model_item/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.model_id)
  end

  defp parse_provider_models(_body), do: []

  defp extract_model_items(%{"data" => data}) when is_list(data), do: data
  defp extract_model_items(%{data: data}) when is_list(data), do: data
  defp extract_model_items(%{"models" => models}) when is_list(models), do: models
  defp extract_model_items(%{models: models}) when is_list(models), do: models
  defp extract_model_items(%{"items" => items}) when is_list(items), do: items
  defp extract_model_items(%{items: items}) when is_list(items), do: items
  defp extract_model_items(map) when is_map(map), do: [map]
  defp extract_model_items(_body), do: []

  defp normalize_provider_model_item(item) when is_binary(item) do
    %{
      model_id: String.trim(item),
      name: String.trim(item),
      supports_reasoning: supports_reasoning_model?(item),
      context_window: nil,
      raw: %{"id" => item}
    }
  end

  defp normalize_provider_model_item(item) when is_map(item) do
    model_id =
      item
      |> Map.get("id", Map.get(item, :id))
      |> case do
        nil -> Map.get(item, "name", Map.get(item, :name))
        value -> value
      end
      |> to_string()
      |> String.trim()

    if model_id == "" do
      nil
    else
      %{
        model_id: model_id,
        name: Map.get(item, "name", Map.get(item, :name)) || model_id,
        supports_reasoning:
          Map.get(item, "supports_reasoning", Map.get(item, :supports_reasoning)) ||
            supports_reasoning_model?(model_id),
        context_window:
          Map.get(item, "context_window", Map.get(item, :context_window)) ||
            Map.get(item, "context_length", Map.get(item, :context_length)),
        raw: normalize_raw(item)
      }
    end
  end

  defp normalize_provider_model_item(_item), do: nil

  defp persist_provider_models(%Provider{} = provider, models) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    model_ids = Enum.map(models, & &1.model_id)

    Multi.new()
    |> Multi.run(:upserts, fn repo, _changes ->
      Enum.each(models, fn model ->
        attrs = %{
          provider_id: provider.id,
          model_id: model.model_id,
          name: model.name,
          supports_reasoning: model.supports_reasoning,
          context_window: model.context_window,
          raw: model.raw,
          status: "active",
          inserted_at: now,
          updated_at: now
        }

        repo.insert_all(
          ProviderModel,
          [attrs],
          on_conflict: [
            set: [
              name: model.name,
              supports_reasoning: model.supports_reasoning,
              context_window: model.context_window,
              raw: model.raw,
              status: "active",
              updated_at: now
            ]
          ],
          conflict_target: [:provider_id, :model_id]
        )
      end)

      {:ok, length(models)}
    end)
    |> Multi.update_all(
      :mark_inactive,
      from(provider_model in ProviderModel,
        where:
          provider_model.provider_id == ^provider.id and provider_model.model_id not in ^model_ids
      ),
      set: [status: "inactive", updated_at: now]
    )
    |> Multi.update(
      :provider,
      Provider.changeset(provider, %{
        models_last_refreshed_at: now,
        models_last_refresh_error: nil
      })
    )
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        {:ok, Repo.preload(provider, provider_models: active_provider_models_query())}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp maybe_persist_refresh_error(%Provider{} = provider, reason) do
    _ =
      provider
      |> Provider.changeset(%{
        models_last_refresh_error: to_string(reason)
      })
      |> Repo.update()

    :ok
  end

  defp model_refresh_headers(%Provider{} = provider) do
    headers =
      provider.extra_headers
      |> normalize_map()
      |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)

    auth_headers =
      case provider.adapter || provider.provider do
        "anthropic" ->
          [{"x-api-key", provider.api_key}, {"anthropic-version", "2023-06-01"}]

        "google" ->
          [{"x-goog-api-key", provider.api_key}]

        "gemini" ->
          [{"x-goog-api-key", provider.api_key}]

        _other ->
          [{"authorization", "Bearer #{provider.api_key}"}]
      end

    [{"accept", "application/json"} | auth_headers ++ headers]
  end

  defp supports_reasoning_model?(model_id) when is_binary(model_id) do
    String.contains?(model_id, "reasoning") or
      String.starts_with?(model_id, "gemini-2.5") or
      String.starts_with?(model_id, "gemini-3")
  end

  defp supports_reasoning_model?(_model_id), do: false

  defp normalize_raw(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp short_body(body) when is_binary(body), do: String.slice(body, 0, 300)

  defp short_body(body) when is_map(body) or is_list(body),
    do: body |> Jason.encode!() |> String.slice(0, 300)

  defp short_body(body), do: inspect(body)

  defp authorize_manager(%Scope{} = scope) do
    if Scope.manager?(scope), do: :ok, else: {:error, :forbidden}
  end

  defp ensure_organization_owns_provider(%Scope{} = scope, provider) do
    if provider.organization_id == Scope.organization_id!(scope) do
      :ok
    else
      raise Ecto.NoResultsError, query: Provider
    end
  end

  defp provider_name_map do
    Map.new(@provider_templates, fn template -> {template.id, template.label} end)
  end

  defp provider_label(provider_id, provider_name_map) do
    Map.get(provider_name_map, provider_id) || humanize_provider_id(provider_id)
  end

  defp humanize_provider_id(provider_id) do
    provider_id
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp active_provider_models_query do
    from provider_model in ProviderModel,
      where: provider_model.status == "active",
      order_by: [asc: provider_model.name, asc: provider_model.model_id]
  end

  defp maybe_preload_provider_models(nil), do: nil

  defp maybe_preload_provider_models(%Provider{} = provider) do
    Repo.preload(provider, provider_models: active_provider_models_query())
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp stringify_keys(value), do: value

  defp put_default(attrs, _key, nil), do: attrs

  defp put_default(attrs, key, value) do
    case Map.get(attrs, key) do
      nil -> Map.put(attrs, key, value)
      "" -> Map.put(attrs, key, value)
      _other -> attrs
    end
  end

  defp normalize_map(nil), do: %{}

  defp normalize_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_map(_value), do: %{}
end
