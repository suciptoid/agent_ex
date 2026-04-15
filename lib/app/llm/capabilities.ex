defmodule App.LLM.Capabilities do
  @moduledoc false

  def reasoning_supported?(provider, model) do
    model_name = normalize_model(model)

    from_provider_model(provider, model_name) || from_model_name(model_name)
  end

  def tool_use_supported?(provider, model) do
    model_name = normalize_model(model)
    from_provider_model_tool_use(provider, model_name)
  end

  defp from_provider_model(%{provider_models: provider_models}, model_name)
       when is_list(provider_models) and is_binary(model_name) do
    provider_models
    |> Enum.find(&(model_id(&1) == model_name))
    |> case do
      nil -> nil
      model -> Map.get(model, :supports_reasoning) || Map.get(model, "supports_reasoning")
    end
  end

  defp from_provider_model(_provider, _model_name), do: nil

  defp from_provider_model_tool_use(%{provider_models: provider_models}, model_name)
       when is_list(provider_models) and is_binary(model_name) do
    provider_models
    |> Enum.find(&(model_id(&1) == model_name))
    |> case do
      nil -> true
      provider_model -> infer_tool_use_support(provider_model)
    end
  end

  defp from_provider_model_tool_use(_provider, _model_name), do: true

  defp from_model_name(model_name) when is_binary(model_name) do
    cond do
      String.starts_with?(model_name, "gemini-2.5") -> true
      String.starts_with?(model_name, "gemini-3") -> true
      String.contains?(model_name, "reasoning") -> true
      true -> false
    end
  end

  defp from_model_name(_model_name), do: false

  defp normalize_model(model) when is_binary(model) do
    case String.split(model, ":", parts: 2) do
      [_provider_prefix, raw_model] -> raw_model
      [raw_model] -> raw_model
      _other -> model
    end
  end

  defp normalize_model(_model), do: nil

  defp infer_tool_use_support(provider_model) when is_map(provider_model) do
    cond do
      is_boolean(map_get(provider_model, :supports_tools)) ->
        map_get(provider_model, :supports_tools)

      is_boolean(map_get(provider_model, :tool_use_supported)) ->
        map_get(provider_model, :tool_use_supported)

      true ->
        provider_model
        |> model_raw()
        |> supported_parameters()
        |> case do
          [] -> true
          params -> Enum.any?(params, &tool_parameter_name?/1)
        end
    end
  end

  defp infer_tool_use_support(_provider_model), do: true

  defp model_raw(provider_model) do
    case map_get(provider_model, :raw) do
      raw when is_map(raw) -> raw
      _other -> %{}
    end
  end

  defp supported_parameters(raw) when is_map(raw) do
    params = map_get(raw, :supported_parameters, [])

    case params do
      value when is_list(value) ->
        Enum.map(value, &to_string/1)

      _other ->
        []
    end
  end

  defp supported_parameters(_raw), do: []

  defp tool_parameter_name?(param_name) when is_binary(param_name) do
    param_name in ["tools", "tool_choice", "function_call", "functions"]
  end

  defp tool_parameter_name?(_param_name), do: false

  defp model_id(%{model_id: model_id}), do: model_id
  defp model_id(%{"model_id" => model_id}), do: model_id
  defp model_id(_model), do: nil

  defp map_get(map, key, default \\ nil)

  defp map_get(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp map_get(_map, _key, default), do: default
end
