defmodule App.Tasks.ScheduleScannerWorker do
  use Oban.Worker, queue: :scheduled_tasks, max_attempts: 1

  alias App.Tasks

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Tasks.dispatch_due_tasks()
    :ok
  end
end
