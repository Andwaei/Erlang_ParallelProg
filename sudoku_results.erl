-module(sudoku_results).
-export([print_summary/4, write_results/5]).

%% -----------------------------------------------------------------------
%% Console summary  (mirrors ResultWriter.printSummary)
%% -----------------------------------------------------------------------

print_summary(Results, ParallelMs, SequentialMs, NumWorkers) ->
    Solved     = count_status(Results, solved),
    Invalid    = count_status(Results, invalid),
    Unsolvable = count_status(Results, unsolvable),

    TotalNanos = lists:foldl(fun(R, Acc) -> Acc + maps:get(nanos, R) end, 0, Results),
    AvgMs      = case length(Results) of
                     0 -> "N/A";
                     N -> io_lib:format("~.4f", [TotalNanos / N / 1_000_000])
                 end,

    io:format("~n"),
    io:format("╔══════════════════════════════════════════════════════════╗~n"),
    io:format("║           BATCH SUDOKU VALIDATOR & SOLVER                ║~n"),
    io:format("║           PLT-Parallel Bridge Matrix — Erlang            ║~n"),
    io:format("╠══════════════════════════════════════════════════════════╣~n"),
    io:format("║  Total puzzles processed : ~-30w║~n", [length(Results)]),
    io:format("║  ✓ Solved                : ~-30w║~n", [Solved]),
    io:format("║  ✗ Invalid initial state : ~-30w║~n", [Invalid]),
    io:format("║  ✗ No solution exists    : ~-30w║~n", [Unsolvable]),
    io:format("╠══════════════════════════════════════════════════════════╣~n"),
    io:format("║  Worker processes        : ~-30w║~n", [NumWorkers]),
    io:format("║  Sequential time (Ts)    : ~-27w ms ║~n", [SequentialMs]),
    io:format("║  Parallel time   (Tp)    : ~-27w ms ║~n", [ParallelMs]),

    case ParallelMs > 0 andalso SequentialMs > 0 of
        true ->
            Speedup    = SequentialMs / ParallelMs,
            Efficiency = Speedup / NumWorkers * 100.0,
            io:format("║  Speedup  S = Ts/Tp      : ~-27s   ║~n",
                      [io_lib:format("~.2f", [Speedup])]),
            io:format("║  Efficiency E = S/N      : ~-26s%  ║~n",
                      [io_lib:format("~.1f", [Efficiency])]);
        false ->
            ok
    end,

    io:format("║  Avg solve time per puzzle: ~-25s ms ║~n", [AvgMs]),
    io:format("║  Total CPU work (sum)    : ~-27s ms ║~n",
              [io_lib:format("~.2f", [TotalNanos / 1_000_000])]),
    io:format("╚══════════════════════════════════════════════════════════╝~n"),

    %% Per-worker workload breakdown
    io:format("~n── Per-worker workload ──────────────────────────────────────~n"),
    WorkerCounts = lists:foldl(fun(R, Acc) ->
        W = maps:get(worker, R),
        maps:update_with(W, fun(C) -> C + 1 end, 1, Acc)
    end, #{}, Results),
    Sorted = lists:sort(fun({_, A}, {_, B}) -> A >= B end, maps:to_list(WorkerCounts)),
    lists:foreach(fun({Pid, Count}) ->
        io:format("  ~-30s → ~w puzzles~n", [Pid, Count])
    end, Sorted),
    io:format("~n").

%% -----------------------------------------------------------------------
%% File output  (mirrors ResultWriter.writeResults)
%% -----------------------------------------------------------------------

write_results(Results, OutputDir, ParallelMs, SequentialMs, NumWorkers) ->
    ok = filelib:ensure_dir(OutputDir ++ "/"),
    write_solved    (Results, OutputDir),
    write_invalid   (Results, OutputDir),
    write_unsolvable(Results, OutputDir),
    write_benchmark (Results, OutputDir, ParallelMs, SequentialMs, NumWorkers),
    io:format("[Writer] Output written to: ~s~n", [filename:absname(OutputDir)]).

%% results_solved.txt — id + flat 81-char solution
write_solved(Results, Dir) ->
    Path = filename:join(Dir, "results_solved.txt"),
    {ok, F} = file:open(Path, [write]),
    io:fwrite(F, "# id,solution_81chars~n", []),
    Solved = lists:filter(fun(R) -> status(R) =:= solved end, Results),
    Indexed = index_results(Solved),
    lists:foreach(fun({Id, R}) ->
        {solved, Board} = maps:get(result, R),
        io:fwrite(F, "~w,~s~n", [Id, Board])
    end, Indexed),
    file:close(F).

%% results_invalid.txt — ids of puzzles with illegal initial states
write_invalid(Results, Dir) ->
    Path = filename:join(Dir, "results_invalid.txt"),
    {ok, F} = file:open(Path, [write]),
    io:fwrite(F, "# Puzzles with illegal initial states~n", []),
    Invalid  = lists:filter(fun(R) -> status(R) =:= invalid end, Results),
    Indexed  = index_results(Invalid),
    lists:foreach(fun({Id, _R}) ->
        io:fwrite(F, "~w~n", [Id])
    end, Indexed),
    file:close(F).

%% results_unsolvable.txt — ids of valid but unsolvable puzzles
write_unsolvable(Results, Dir) ->
    Path = filename:join(Dir, "results_unsolvable.txt"),
    {ok, F} = file:open(Path, [write]),
    io:fwrite(F, "# Valid puzzles for which no solution exists~n", []),
    Unsolvable = lists:filter(fun(R) -> status(R) =:= unsolvable end, Results),
    Indexed    = index_results(Unsolvable),
    lists:foreach(fun({Id, _R}) ->
        io:fwrite(F, "~w~n", [Id])
    end, Indexed),
    file:close(F).

%% benchmark_report.txt — timing / speedup table
write_benchmark(Results, Dir, ParallelMs, SequentialMs, NumWorkers) ->
    Path = filename:join(Dir, "benchmark_report.txt"),
    {ok, F} = file:open(Path, [write, {encoding, utf8}]),
    io:fwrite(F, "PLT-Parallel Bridge Matrix — Benchmark Report~n", []),
    io:fwrite(F, "==============================================~n", []),
    io:fwrite(F, "Paradigm  : Message-Passing (Erlang)~n", []),
    io:fwrite(F, "Construct : spawn + receive + send (!)~n", []),
    io:fwrite(F, "Pattern   : Dealer / Worker pool~n", []),
    io:fwrite(F, "Workers N : ~w~n", [NumWorkers]),
    io:fwrite(F, "Ts (seq)  : ~w ms~n", [SequentialMs]),
    io:fwrite(F, "Tp (par)  : ~w ms~n", [ParallelMs]),
    case ParallelMs > 0 andalso SequentialMs > 0 of
        true ->
            S = SequentialMs / ParallelMs,
            io:fwrite(F, "S = Ts/Tp : ~s~n",  [io_lib:format("~.2f", [S])]),
            io:fwrite(F, "E = S/N   : ~s%~n", [io_lib:format("~.1f", [S / NumWorkers * 100.0])]);
        false ->
            ok
    end,
    io:fwrite(F, "~n# Per-puzzle timing (id, status, nanos, worker)~n", []),
    Indexed = index_results(Results),
    lists:foreach(fun({Id, R}) ->
        io:fwrite(F, "~w,~s,~w,~s~n",
                  [Id, atom_to_list(status(R)),
                   maps:get(nanos, R), maps:get(worker, R)])
    end, Indexed),
    file:close(F).

%% -----------------------------------------------------------------------
%% Internal helpers
%% -----------------------------------------------------------------------

status(R) ->
    {S, _} = maps:get(result, R),
    S.

%% Pair each result with a 1-based integer id (original insertion order)
index_results(Results) ->
    lists:zip(lists:seq(1, length(Results)), Results).

count_status(Results, S) ->
    length(lists:filter(fun(R) -> status(R) =:= S end, Results)).