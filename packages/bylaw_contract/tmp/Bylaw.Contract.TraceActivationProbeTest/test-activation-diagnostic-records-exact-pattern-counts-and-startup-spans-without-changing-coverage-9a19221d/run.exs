Code.require_file("/Users/ryanzidago/Projects/bylaw/.worktrees/claude-ecto-no-repo-in-loop/packages/bylaw_contract/qa/trace-activation-check.exs")
alias Bylaw.Contract.StructuralExample, as: Fixture
mfa = {Fixture, :classify, 1}
{:ok, observer} = Bylaw.Contract.start([Fixture], checks: [{BylawTraceActivationCheck, calls: [mfa], returns: [mfa]}])
:exact = Fixture.classify(:exact)
coverage = Bylaw.Contract.stop(observer)
:complete = Map.get(coverage, :status, :complete)
[{{:call, ^mfa, [:exact]}, caller}, {{:return, ^mfa, :exact}, caller}] = coverage.checks[BylawTraceActivationCheck].events
true = caller == self()
