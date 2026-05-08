defmodule Bylaw.Credo.Check.Elixir.NoParamExtractionInFunctionHeadTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.NoParamExtractionInFunctionHead

  # -- Should flag ------------------------------------------------------

  test "flags extracting a single field from a struct" do
    """
    defmodule Example do
      def perform(%Oban.Job{args: args}) do
        args
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue()
  end

  test "flags extracting multiple fields from a struct" do
    """
    defmodule Example do
      def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
        {args, attempt, max_attempts}
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue()
  end

  test "flags extracting fields from a plain map" do
    """
    defmodule Example do
      def create_user(%{email: email, role: role}) do
        {email, role}
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue()
  end

  test "flags extracting from map with = binding" do
    """
    defmodule Example do
      def create_user(%{email: email, role: role} = attrs) do
        {email, role, attrs}
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue()
  end

  test "reports a rewrite-shaped message when the whole param is already bound" do
    """
    defmodule Example do
      def map_provider_error(%{cause: cause} = error), do: map_provider_error(cause)
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue(%{
      line_no: 2,
      trigger: "%{cause: cause}",
      message: ~r/%\{cause: _\} = error.+error\.cause/
    })
  end

  test "reports a rewrite-shaped message for reversed = bindings" do
    """
    defmodule Example do
      def map_provider_error(error = %{cause: cause}), do: map_provider_error(cause)
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue(%{
      line_no: 2,
      trigger: "%{cause: cause}",
      message: ~r/%\{cause: _\} = error.+error\.cause/
    })
  end

  test "flags nested map extraction inside struct" do
    """
    defmodule Example do
      def process(%Oban.Job{args: %{"invoice_id" => invoice_id}}) do
        invoice_id
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue()
  end

  test "reports a rewrite-shaped message for nested extraction with an existing binding" do
    """
    defmodule Example do
      def process(%Oban.Job{args: %{"invoice_id" => invoice_id}} = job) do
        invoice_id
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue(%{
      line_no: 2,
      trigger: "%Oban.Job{args: %{\"invoice_id\" => invoice_id}}",
      message: ~r/%Oban\.Job\{args: %\{"invoice_id" => _\}\} = job/
    })
  end

  test "reports a rewrite-shaped message when the whole param still needs binding" do
    """
    defmodule Example do
      def map_provider_error(%ReqLLM.Error.API.Stream{cause: cause}), do: map_provider_error(cause)
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue(%{
      line_no: 2,
      trigger: "%ReqLLM.Error.API.Stream{cause: cause}",
      message: ~r/%ReqLLM\.Error\.API\.Stream\{\} = stream.+stream\.cause/
    })
  end

  test "flags extraction with when guard" do
    """
    defmodule Example do
      def guarded(%{key: value} = map) when is_map(map) do
        value
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue()
  end

  test "flags extraction from string-keyed map" do
    """
    defmodule Example do
      def extract(%{"name" => name, "email" => email}) do
        {name, email}
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue()
  end

  test "reports a rewrite-shaped message for string-keyed maps without implying dot access" do
    """
    defmodule Example do
      def extract(%{"name" => name} = params) do
        name
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue(%{
      line_no: 2,
      trigger: "%{\"name\" => name}",
      message: ~r/%\{"name" => _\} = params.+from `params` in the body\.$/
    })
  end

  test "flags nested struct extraction" do
    """
    defmodule Example do
      def extract(%Oban.Job{args: %{"config" => %Config{name: name}}}) do
        name
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue()
  end

  test "flags mixed literal + extraction" do
    """
    defmodule Example do
      def extract(%{type: :email, address: address}) do
        address
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue()
  end

  test "flags struct extraction with = binding" do
    """
    defmodule Example do
      def extract(%Oban.Job{args: args} = job) do
        {args, job}
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue()
  end

  test "flags defp the same as def" do
    """
    defmodule Example do
      defp extract(%{key: value}) do
        value
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue()
  end

  test "flags extraction in anonymous function" do
    """
    defmodule Example do
      def run do
        Enum.map(items, fn %{name: name} -> name end)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue()
  end

  test "flags extraction in multi-clause anonymous function" do
    """
    defmodule Example do
      def run do
        Enum.map(items, fn
          %{type: :email, address: address} -> address
          %{type: :sms, number: number} -> number
        end)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issues()
  end

  test "flags extraction from struct in anonymous function" do
    """
    defmodule Example do
      def run do
        Enum.map(jobs, fn %Oban.Job{args: args} -> args end)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue()
  end

  # -- Should NOT flag --------------------------------------------------

  test "allows empty struct type check" do
    """
    defmodule Example do
      def perform(%Oban.Job{} = job) do
        job.args
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows literal atom dispatch in map" do
    """
    defmodule Example do
      def dispatch(%{type: :email} = notification) do
        notification
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows literal string dispatch in map" do
    """
    defmodule Example do
      def dispatch(%{"action" => "create"} = params) do
        params
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows underscore shape check in nested map" do
    """
    defmodule Example do
      def check(%Oban.Job{args: %{"invoice_id" => _}} = job) do
        job
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows underscore-prefixed variable" do
    """
    defmodule Example do
      def check(%{key: _value}) do
        :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows tuple dispatch" do
    """
    defmodule Example do
      def handle({:ok, value}), do: value
      def handle({:error, reason}), do: reason
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows nil dispatch" do
    """
    defmodule Example do
      def fetch(nil), do: {:error, :missing}
      def fetch(id), do: id
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows empty list dispatch" do
    """
    defmodule Example do
      def enqueue([]), do: :ok
      def enqueue(job_ids), do: job_ids
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows plain variable param" do
    """
    defmodule Example do
      def process(attrs) do
        attrs
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows literal atom param" do
    """
    defmodule Example do
      def process(:ok), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows multiple literal dispatch clauses" do
    """
    defmodule Example do
      def dispatch(%{type: :sms}), do: :sms
      def dispatch(%{type: :email}), do: :email
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows multiple underscore shape checks in nested map" do
    """
    defmodule Example do
      def check(%Oban.Job{args: %{"tenant_id" => _, "invoice_id" => _}} = job) do
        job
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows empty map with binding" do
    """
    defmodule Example do
      def process(%{} = map) do
        map
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows bare struct without binding" do
    """
    defmodule Example do
      def process(%Oban.Job{}) do
        :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows boolean literal dispatch in map" do
    """
    defmodule Example do
      def dispatch(%{active: true} = user) do
        user
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows integer literal dispatch in map" do
    """
    defmodule Example do
      def dispatch(%{status: 0} = record) do
        record
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows nested struct type check without extraction" do
    """
    defmodule Example do
      def check(%Oban.Job{args: %Config{}} = job) do
        job
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows list head dispatch" do
    """
    defmodule Example do
      def process([first | rest]) do
        {first, rest}
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows binary pattern matching" do
    """
    defmodule Example do
      def process(<<header::binary-size(4), _rest::binary>>) do
        header
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows pin operator in map" do
    """
    defmodule Example do
      def process(%{id: ^id}) do
        id
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows literal dispatch in anonymous function" do
    """
    defmodule Example do
      def run do
        Enum.map(items, fn
          %{type: :email} -> :email
          %{type: :sms} -> :sms
        end)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows type check in anonymous function" do
    """
    defmodule Example do
      def run do
        Enum.map(jobs, fn %Oban.Job{} = job -> job end)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows variable extraction when variable is used in guard" do
    """
    defmodule Example do
      def create(conn, %{"_json" => list}) when is_list(list) do
        {conn, list}
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "allows struct field extraction when variable is used in guard" do
    """
    defmodule Example do
      def process(%MyStruct{count: count}) when count > 0 do
        count
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> refute_issues()
  end

  test "flags extraction when only some variables are used in guard" do
    """
    defmodule Example do
      def process(%{type: type, name: name}) when is_atom(type) do
        name
      end
    end
    """
    |> to_source_file()
    |> run_check(NoParamExtractionInFunctionHead)
    |> assert_issue(%{
      message: ~r/%\{type: type, name: _\} = value/
    })
  end
end
