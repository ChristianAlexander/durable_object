defmodule DurableObject.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    scheduler = Application.get_env(:durable_object, :scheduler, DurableObject.Scheduler.Polling)
    scheduler_opts = Application.get_env(:durable_object, :scheduler_opts, [])
    repo = Application.get_env(:durable_object, :repo)

    base_children = [
      {Registry, keys: :unique, name: DurableObject.Registry},
      DurableObject.ObjectSupervisor
    ]

    # Add scheduler children (poller for polling backend, nothing for others)
    scheduler_children = scheduler.child_spec(Keyword.put(scheduler_opts, :repo, repo))
    children = base_children ++ scheduler_children

    opts = [strategy: :one_for_one, name: DurableObject.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
