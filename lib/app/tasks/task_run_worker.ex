defmodule App.Tasks.TaskRunWorker do
  use Oban.Worker, queue: :scheduled_tasks, max_attempts: 5

  alias App.Tasks

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task_id" => task_id} = args}) do
    case Tasks.run_task(task_id, Map.get(args, "scheduled_for")) do
      :ok -> :ok
      {:discard, reason} -> {:discard, reason}
      {:error, reason} -> {:error, reason}
    end
  end
end
