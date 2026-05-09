-module(sudoku_batch).
-export([run/2, run/0, generate_puzzles/2]).

run() ->
    Puzzles = generate_puzzles(100, classic),
    io:format("~nStarting batch solver: ~w puzzles, 4 workers~n", [length(Puzzles)]),
    Results = supervisor_loop(Puzzles, 4),
    print_summary(Results).

run(Filename, NumWorkers) ->
    io:format("Loading puzzles from ~s ...~n", [Filename]),
    Puzzles = load_puzzles(Filename),
    io:format("Loaded ~w puzzles. Spawning ~w workers ...~n",
              [length(Puzzles), NumWorkers]),
    Results = supervisor_loop(Puzzles, NumWorkers),
    print_summary(Results),
    save_results("results.txt", Results).

supervisor_loop(AllPuzzles, NumWorkers) ->
    Self = self(),
    Workers = [spawn(fun() -> worker_init(Self) end)
               || _ <- lists:seq(1, NumWorkers)],
    dealer(AllPuzzles, Workers, length(AllPuzzles), []).

dealer([], _Workers, 0, Results) ->
    lists:reverse(Results);
dealer(Pending, Workers, Outstanding, Results) ->
    receive
        {want_work, WorkerPid} when Pending =/= [] ->
            [Next | Rest] = Pending,
            WorkerPid ! {puzzle, Next},
            dealer(Rest, Workers, Outstanding, Results);
        {want_work, WorkerPid} ->
            WorkerPid ! stop,
            dealer([], Workers, Outstanding, Results);
        {result, Ref, PuzzleIn, SolveResult} ->
            Entry = #{ref => Ref, input => PuzzleIn, result => SolveResult},
            dealer(Pending, Workers, Outstanding - 1, [Entry | Results])
    end.

worker_init(SupervisorPid) ->
    SupervisorPid ! {want_work, self()},
    worker_loop(SupervisorPid).

worker_loop(SupervisorPid) ->
    receive
        {puzzle, PuzzleStr} ->
            Ref     = make_ref(),
            Board   = parse_board(PuzzleStr),
            IsValid = validate(Board),
            Result  =
                case IsValid of
                    false ->
                        {invalid, "Initial board state violates Sudoku rules"};
                    true ->
                        case solve(Board) of
                            {ok, Solved} -> {solved, board_to_string(Solved)};
                            no_solution  -> {unsolvable, PuzzleStr}
                        end
                end,
            SupervisorPid ! {result, Ref, PuzzleStr, Result},
            SupervisorPid ! {want_work, self()},
            worker_loop(SupervisorPid);
        stop ->
            ok
    end.

validate(Board) ->
    validate_rows(Board) andalso
    validate_cols(Board) andalso
    validate_boxes(Board).

validate_rows(Board) ->
    lists:all(fun(Row) -> no_duplicates(Row) end, Board).

validate_cols(Board) ->
    Cols = [[lists:nth(Col, Row) || Row <- Board] || Col <- lists:seq(1, 9)],
    lists:all(fun(Col) -> no_duplicates(Col) end, Cols).

validate_boxes(Board) ->
    BoxStarts = [{R, C} || R <- [1, 4, 7], C <- [1, 4, 7]],
    lists:all(
        fun({R, C}) ->
            Box = [lists:nth(BC, lists:nth(BR, Board))
                   || BR <- lists:seq(R, R+2),
                      BC <- lists:seq(C, C+2)],
            no_duplicates(Box)
        end,
        BoxStarts).

no_duplicates(Cells) ->
    Filled = [V || V <- Cells, V =/= 0],
    length(Filled) =:= length(lists:usort(Filled)).

solve(Board) ->
    case find_empty(Board) of
        none ->
            {ok, Board};
        {Row, Col} ->
            Candidates = get_candidates(Board, Row, Col),
            try_candidates(Board, Row, Col, Candidates)
    end.

try_candidates(_Board, _Row, _Col, []) ->
    no_solution;
try_candidates(Board, Row, Col, [Val | Rest]) ->
    NewBoard = set_cell(Board, Row, Col, Val),
    case solve(NewBoard) of
        {ok, Solved} -> {ok, Solved};
        no_solution  -> try_candidates(Board, Row, Col, Rest)
    end.

find_empty(Board) ->
    find_empty(Board, 1).

find_empty([], _) -> none;
find_empty([Row | Rest], R) ->
    case find_zero(Row, 1) of
        none -> find_empty(Rest, R + 1);
        Col  -> {R, Col}
    end.

find_zero([], _)         -> none;
find_zero([0 | _], C)    -> C;
find_zero([_ | Rest], C) -> find_zero(Rest, C + 1).

get_candidates(Board, Row, Col) ->
    Used = used_values(Board, Row, Col),
    [V || V <- lists:seq(1, 9), not lists:member(V, Used)].

used_values(Board, Row, Col) ->
    RowVals = lists:nth(Row, Board),
    ColVals = [lists:nth(Col, R) || R <- Board],
    BoxR    = ((Row - 1) div 3) * 3 + 1,
    BoxC    = ((Col - 1) div 3) * 3 + 1,
    BoxVals = [lists:nth(BC, lists:nth(BR, Board))
               || BR <- lists:seq(BoxR, BoxR + 2),
                  BC <- lists:seq(BoxC, BoxC + 2)],
    lists:usort(RowVals ++ ColVals ++ BoxVals) -- [0].

set_cell(Board, Row, Col, Val) ->
    OldRow = lists:nth(Row, Board),
    NewRow = lists:sublist(OldRow, Col - 1) ++ [Val] ++
             lists:nthtail(Col, OldRow),
    lists:sublist(Board, Row - 1) ++ [NewRow] ++
    lists:nthtail(Row, Board).

parse_board(Str) ->
    Digits = [D - $0 || D <- Str, D >= $0, D =< $9],
    [lists:sublist(Digits, (R - 1) * 9 + 1, 9) || R <- lists:seq(1, 9)].

board_to_string(Board) ->
    lists:flatten([integer_to_list(D) || Row <- Board, D <- Row]).

load_puzzles(Filename) ->
    {ok, Binary} = file:read_file(Filename),
    Lines = binary:split(Binary, <<"\n">>, [global, trim_all]),
    [binary_to_list(L) || L <- Lines, byte_size(L) =:= 81].

save_results(Filename, Results) ->
    Lines = [format_result(R) || R <- Results],
    file:write_file(Filename, string:join(Lines, "\n")),
    io:format("Results written to ~s~n", [Filename]).

format_result(#{result := {solved, Sol}}) ->
    "SOLVED:" ++ Sol;
format_result(#{result := {unsolvable, In}}) ->
    "UNSOLVABLE:" ++ In;
format_result(#{input := In, result := {invalid, Msg}}) ->
    "INVALID:" ++ In ++ ":" ++ Msg.

print_summary(Results) ->
    Total      = length(Results),
    Solved     = length([R || R = #{result := {solved, _}}     <- Results]),
    Unsolvable = length([R || R = #{result := {unsolvable, _}} <- Results]),
    Invalid    = length([R || R = #{result := {invalid, _}}    <- Results]),
    io:format("~n=== Batch Sudoku Results ===~n"),
    io:format("Total processed : ~w~n", [Total]),
    io:format("Solved          : ~w~n", [Solved]),
    io:format("Unsolvable      : ~w~n", [Unsolvable]),
    io:format("Invalid input   : ~w~n", [Invalid]).

generate_puzzles(N, classic) ->
    BaseSolved = "534678912672195348198342567859761423426853791713924856961537284287419635345286179",
    [make_partial(BaseSolved, I) || I <- lists:seq(1, N)].

make_partial(Solved, Seed) ->
    Indices = partial_indices(Seed),
    Chars   = [case lists:member(I, Indices) of
                   true  -> $0;
                   false -> lists:nth(I, Solved)
               end || I <- lists:seq(1, 81)],
    Chars.

partial_indices(Seed) ->
    Rand = fun(S) -> (S * 1664525 + 1013904223) band 16#FFFFFFFF end,
    {_, Indices} =
        lists:foldl(
            fun(_, {S, Acc}) ->
                S2 = Rand(S),
                Idx = (S2 rem 81) + 1,
                {S2, [Idx | Acc]}
            end,
            {Seed * 31337, []},
            lists:seq(1, 45)),
    lists:usort(Indices).

