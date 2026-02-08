defmodule Jido.Tools.Github.Issues do
  @moduledoc """
  Tools for interacting with GitHub Issues API.

  Provides actions for creating, listing, filtering, finding, and updating GitHub issues.
  """

  alias Jido.Action.Error
  alias Jido.Tools.Util

  @doc false
  @spec get_client(map(), map()) :: any()
  def get_client(params, context) do
    Util.get_from(params, context, [:client], [[:client], [:tool_context, :client]])
  end

  @doc false
  @spec success_payload(any()) :: {:ok, map()}
  def success_payload(data) do
    {:ok,
     %{
       status: "success",
       data: data,
       raw: data
     }}
  end

  @doc false
  @spec issues_request(String.t(), map(), (-> any())) :: {:ok, any()} | {:error, Error.t()}
  def issues_request(operation, metadata, request_fun)
      when is_binary(operation) and is_map(metadata) and is_function(request_fun, 0) do
    request_fun.()
    |> normalize_tentacat_response(operation, metadata)
  rescue
    e ->
      {:error,
       Error.execution_error(
         "GitHub issues #{operation} failed: #{Exception.message(e)}",
         Map.put(metadata, :exception, e)
       )}
  catch
    kind, reason ->
      {:error,
       Error.execution_error(
         "GitHub issues #{operation} failed",
         Map.merge(metadata, %{kind: kind, reason: reason})
       )}
  end

  defp normalize_tentacat_response({:ok, data}, _operation, _metadata), do: {:ok, data}

  defp normalize_tentacat_response({:error, reason}, operation, metadata)
       when is_binary(reason) do
    {:error, Error.execution_error("GitHub issues #{operation} failed: #{reason}", metadata)}
  end

  defp normalize_tentacat_response({:error, reason}, operation, metadata) do
    {:error, Error.ensure_error(reason, "GitHub issues #{operation} failed", metadata)}
  end

  defp normalize_tentacat_response(data, _operation, _metadata)
       when is_map(data) or is_list(data),
       do: {:ok, data}

  defp normalize_tentacat_response(other, operation, metadata) do
    {:error,
     Error.execution_error(
       "Unexpected GitHub issues #{operation} response",
       Map.merge(metadata, %{response: other})
     )}
  end

  defmodule Create do
    @moduledoc "Action for creating new GitHub issues."

    use Jido.Action,
      name: "github_issues_create",
      description: "Create a new issue on GitHub",
      category: "Github API",
      tags: ["github", "issues", "api"],
      vsn: "1.0.0",
      schema: [
        client: [type: :any, doc: "The Github client"],
        owner: [type: :string, doc: "The owner of the repository"],
        repo: [type: :string, doc: "The name of the repository"],
        title: [type: :string, doc: "The title of the issue"],
        body: [type: :string, doc: "The body of the issue"],
        assignee: [type: :string, doc: "The assignee of the issue"],
        milestone: [type: :string, doc: "The milestone of the issue"],
        labels: [type: {:list, :string}, doc: "The labels of the issue"]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, Jido.Action.Error.t()}
    def run(params, context) do
      client = Jido.Tools.Github.Issues.get_client(params, context)

      body = %{
        title: params[:title],
        body: params[:body],
        assignee: params[:assignee],
        milestone: params[:milestone],
        labels: params[:labels]
      }

      with {:ok, result} <-
             Jido.Tools.Github.Issues.issues_request(
               "create",
               %{owner: params[:owner], repo: params[:repo], title: params[:title]},
               fn -> Tentacat.Issues.create(client, params[:owner], params[:repo], body) end
             ) do
        Jido.Tools.Github.Issues.success_payload(result)
      end
    end
  end

  defmodule Filter do
    @moduledoc "Action for filtering GitHub issues by various criteria."

    use Jido.Action,
      name: "github_issues_filter",
      description: "Filter repository issues on GitHub",
      category: "Github API",
      tags: ["github", "issues", "api"],
      vsn: "1.0.0",
      schema: [
        client: [type: :any, doc: "The Github client"],
        owner: [type: :string, doc: "The owner of the repository"],
        repo: [type: :string, doc: "The name of the repository"],
        state: [type: :string, doc: "The state of the issues (open, closed, all)"],
        assignee: [type: :string, doc: "Filter by assignee"],
        creator: [type: :string, doc: "Filter by creator"],
        labels: [type: :string, doc: "Filter by labels (comma-separated)"],
        sort: [type: :string, doc: "Sort by (created, updated, comments)"],
        direction: [type: :string, doc: "Sort direction (asc, desc)"],
        since: [type: :string, doc: "Only show issues updated after this time"]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, Jido.Action.Error.t()}
    def run(params, context) do
      client = Jido.Tools.Github.Issues.get_client(params, context)

      filters = %{
        state: params[:state],
        assignee: params[:assignee],
        creator: params[:creator],
        labels: params[:labels],
        sort: params[:sort],
        direction: params[:direction],
        since: params[:since]
      }

      with {:ok, result} <-
             Jido.Tools.Github.Issues.issues_request(
               "filter",
               %{owner: params[:owner], repo: params[:repo], filters: filters},
               fn -> Tentacat.Issues.filter(client, params[:owner], params[:repo], filters) end
             ) do
        Jido.Tools.Github.Issues.success_payload(result)
      end
    end
  end

  defmodule Find do
    @moduledoc "Action for finding a specific GitHub issue by number."

    use Jido.Action,
      name: "github_issues_find",
      description: "Get a specific issue from GitHub",
      category: "Github API",
      tags: ["github", "issues", "api"],
      vsn: "1.0.0",
      schema: [
        client: [type: :any, doc: "The Github client"],
        owner: [type: :string, doc: "The owner of the repository"],
        repo: [type: :string, doc: "The name of the repository"],
        number: [type: :integer, doc: "The issue number"]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, Jido.Action.Error.t()}
    def run(params, context) do
      client = Jido.Tools.Github.Issues.get_client(params, context)

      with {:ok, result} <-
             Jido.Tools.Github.Issues.issues_request(
               "find",
               %{owner: params[:owner], repo: params[:repo], number: params[:number]},
               fn ->
                 Tentacat.Issues.find(client, params[:owner], params[:repo], params[:number])
               end
             ) do
        Jido.Tools.Github.Issues.success_payload(result)
      end
    end
  end

  defmodule List do
    @moduledoc "Action for listing all issues from a GitHub repository."

    use Jido.Action,
      name: "github_issues_list",
      description: "List all issues from a GitHub repository",
      category: "Github API",
      tags: ["github", "issues", "api"],
      vsn: "1.0.0",
      schema: [
        client: [type: :any, doc: "The Github client"],
        owner: [type: :string, doc: "The owner of the repository"],
        repo: [type: :string, doc: "The name of the repository"]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, Jido.Action.Error.t()}
    def run(params, context) do
      client = Jido.Tools.Github.Issues.get_client(params, context)

      with {:ok, result} <-
             Jido.Tools.Github.Issues.issues_request(
               "list",
               %{owner: params[:owner], repo: params[:repo]},
               fn -> Tentacat.Issues.list(client, params[:owner], params[:repo]) end
             ) do
        Jido.Tools.Github.Issues.success_payload(result)
      end
    end
  end

  defmodule Update do
    @moduledoc "Action for updating existing GitHub issues."

    use Jido.Action,
      name: "github_issues_update",
      description: "Update an existing issue on GitHub",
      category: "Github API",
      tags: ["github", "issues", "api"],
      vsn: "1.0.0",
      schema: [
        client: [type: :any, doc: "The Github client"],
        owner: [type: :string, doc: "The owner of the repository"],
        repo: [type: :string, doc: "The name of the repository"],
        number: [type: :integer, doc: "The issue number"],
        title: [type: :string, doc: "The new title of the issue"],
        body: [type: :string, doc: "The new body of the issue"],
        assignee: [type: :string, doc: "The new assignee of the issue"],
        state: [type: :string, doc: "The new state of the issue (open, closed)"],
        milestone: [type: :string, doc: "The new milestone of the issue"],
        labels: [type: {:list, :string}, doc: "The new labels of the issue"]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, Jido.Action.Error.t()}
    def run(params, context) do
      client = Jido.Tools.Github.Issues.get_client(params, context)

      body = %{
        title: params[:title],
        body: params[:body],
        assignee: params[:assignee],
        state: params[:state],
        milestone: params[:milestone],
        labels: params[:labels]
      }

      result =
        Jido.Tools.Github.Issues.issues_request(
          "update",
          %{owner: params[:owner], repo: params[:repo], number: params[:number]},
          fn ->
            Tentacat.Issues.update(client, params[:owner], params[:repo], params[:number], body)
          end
        )

      with {:ok, response} <- result do
        Jido.Tools.Github.Issues.success_payload(response)
      end
    end
  end
end
