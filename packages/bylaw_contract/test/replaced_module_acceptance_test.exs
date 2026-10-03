defmodule Bylaw.Contract.ReplacedModuleAcceptanceTest do
  use ExUnit.Case

  alias Bylaw.Contract
  alias Bylaw.Contract.Fixtures.Greeter

  defp replace_from_disk(module) do
    {^module, binary, filename} = :code.get_object_code(module)
    :code.purge(module)
    {:module, ^module} = :code.load_binary(module, filename, binary)
    module.module_info(:md5)
  end

  defp replace_with_stub(module) do
    :code.purge(module)

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      Code.compile_string("defmodule #{inspect(module)} do def greet(_), do: :stub end")
    end)
  end

  defp greeter_properties(report), do: Enum.filter(report.properties, &(&1.module == Greeter))

  test "reports every property of a module replaced during observation as unassessable" do
    report =
      Contract.observe([Greeter], fn ->
        Greeter.greet(:admin)
        replace_from_disk(Greeter)
        Greeter.greet(:member)
      end)

    properties = greeter_properties(report)

    refute Enum.empty?(properties)
    assert Enum.all?(properties, &(&1.status == :unassessable))
    assert Enum.all?(properties, &(&1.reason =~ "replaced"))
  end

  test "warns that names the replaced module" do
    report =
      Contract.observe([Greeter], fn ->
        replace_from_disk(Greeter)
        Greeter.greet(:member)
      end)

    assert [warning] = Enum.filter(report.warnings, &(&1 =~ inspect(Greeter)))
    assert warning =~ "replaced"
  end

  test "reports a module that was never replaced exactly as before" do
    report =
      Contract.observe([Greeter], fn ->
        Greeter.greet(:admin)
        Greeter.greet(:member)
      end)

    assert Enum.any?(greeter_properties(report), &(&1.status == :missed))
    refute Enum.any?(report.warnings, &(&1 =~ "replaced"))
  end

  test "leaves the replacement loaded when observation stops" do
    on_exit(fn -> replace_from_disk(Greeter) end)

    Contract.observe([Greeter], fn -> replace_with_stub(Greeter) end)

    assert apply(Greeter, :greet, [:anything]) == :stub
  end

  test "still restores a module that was not replaced" do
    Contract.observe([Greeter], fn -> Greeter.greet(:admin) end)

    assert :code.which(Greeter) != ~c"bylaw-contract"
    assert Greeter.greet(:admin) == "admin"
  end
end
