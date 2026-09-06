for index <- 1..12 do
  defmodule Module.concat(BylawWarmFixture, "Session#{index}Test") do
    use ExUnit.Case, async: true
    @subject Module.concat(BylawPhaseFixture, "Classifier#{index}")
    @index index

    test "executes the complete declared workload in this session" do
      scenario = System.fetch_env!("BYLAW_WARM_SCENARIO")
      if @index == 1 and scenario == "overflow", do: BylawWarmLifecycleCapture.overflow()

      for _ <- 1..10 do
        assert @subject.classify(1) == :positive
        assert @subject.classify(-1) == :nonpositive
        assert @subject.choose(:left) == :left
        assert @subject.choose(:right) == :right
      end

      if @index == 1 and scenario == "failure", do: flunk("deliberate first-session failure")
    end
  end
end
