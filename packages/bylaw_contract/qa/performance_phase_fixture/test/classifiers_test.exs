for index <- 1..12 do
  defmodule Module.concat(BylawPhaseFixture, "Classifier#{index}Test") do
    use ExUnit.Case, async: true
    @subject Module.concat(BylawPhaseFixture, "Classifier#{index}")

    test "classifies twenty sign calls and twenty literal choices" do
      for _ <- 1..10 do
        assert @subject.classify(1) == :positive
        assert @subject.classify(-1) == :nonpositive
        assert @subject.choose(:left) == :left
        assert @subject.choose(:right) == :right
      end
    end
  end
end
