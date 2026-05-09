-module(sudoku_batch).
-export([run_batch/2, parse_board/1, board_to_string/1]).

%% Phase 1: Task Parallelism Initiation
run_batch(Puzzles, NumWorkers) ->
    Self = self(),
    io:format("Spawning ~p workers for ~p puzzles...~n", [NumWorkers, length(Puzzles)]),
    [spawn(fun() -> worker_loop(Self) end) || _ <- lists:seq(1, NumWorkers)],
    T0 = erlang:monotonic_time(millisecond),
    Results = dealer(Puzzles, NumWorkers, length(Puzzles), []),
    ParallelMs = erlang:monotonic_time(millisecond) - T0,
    {Results, ParallelMs}.

%% Phase 3: Control Constructs (Message Passing)
dealer([], 0, 0, Results) -> lists:reverse(Results);
dealer(Pending, ActiveWorkers, Outstanding, Results) ->
    receive
        {want_work, WorkerPid} ->
            case Pending of
                [Next | Rest] ->
                    WorkerPid ! {task, Next},
                    dealer(Rest, ActiveWorkers, Outstanding, Results);
                [] ->
                    WorkerPid ! stop,
                    dealer([], ActiveWorkers - 1, Outstanding, Results)
            end;
        {result, PuzzleIn, SolveResult, Nanos, WorkerPid} ->
            Entry = #{input => PuzzleIn, result => SolveResult,
                      nanos => Nanos, worker => WorkerPid},
            dealer(Pending, ActiveWorkers, Outstanding - 1, [Entry | Results])
    end.

worker_loop(SupervisorPid) ->
    SupervisorPid ! {want_work, self()},
    receive
        {task, PuzzleStr} ->
            T0 = erlang:monotonic_time(nanosecond),
            Board = parse_board(PuzzleStr),
            Result = solve_board(Board),
            Nanos = erlang:monotonic_time(nanosecond) - T0,
            WorkerPid = pid_to_list(self()),
            SupervisorPid ! {result, PuzzleStr, Result, Nanos, WorkerPid},
            worker_loop(SupervisorPid);
        stop ->
            ok
    end.

%% --- O(1) Tuple-Based Sudoku Logic ---

solve_board(Board) ->
    case is_valid_initial(Board, 1) of
        false -> {invalid, "Rule violation"};
        true ->
            case backtrack(Board, 1) of
                {ok, Solved} -> {solved, board_to_string(Solved)};
                no_solution -> {unsolvable, board_to_string(Board)}
            end
    end.

%% Phase 4: Recursive Base Case
backtrack(Board, Index) when Index > 81 -> {ok, Board};
backtrack(Board, Index) ->
    case erlang:element(Index, Board) of
        0 ->
            Candidates = get_candidates(Board, Index),
            try_candidates(Board, Index, Candidates);
        _ ->
            backtrack(Board, Index + 1) % Move forward only
    end.

try_candidates(_Board, _Index, []) -> no_solution;
try_candidates(Board, Index, [Val | Rest]) ->
    %% setelement creates a new immutable copy, safely isolating memory
    NewBoard = erlang:setelement(Index, Board, Val),
    case backtrack(NewBoard, Index + 1) of
        {ok, Solved} -> {ok, Solved};
        no_solution -> try_candidates(Board, Index, Rest)
    end.

get_candidates(Board, Index) ->
    Row = (Index - 1) div 9,
    Col = (Index - 1) rem 9,
    Used = used_in_row(Board, Row) ++ used_in_col(Board, Col) ++ used_in_box(Board, Row, Col),
    [V || V <- lists:seq(1, 9), not lists:member(V, Used)].

used_in_row(Board, Row) ->
    Start = Row * 9 + 1,
    [erlang:element(I, Board) || I <- lists:seq(Start, Start + 8), erlang:element(I, Board) =/= 0].

used_in_col(Board, Col) ->
    Start = Col + 1,
    [erlang:element(I, Board) || I <- lists:seq(Start, 81, 9), erlang:element(I, Board) =/= 0].

used_in_box(Board, Row, Col) ->
    BoxR = (Row div 3) * 3,
    BoxC = (Col div 3) * 3,
    Start = BoxR * 9 + BoxC + 1,
    Indices = [Start, Start+1, Start+2, Start+9, Start+10, Start+11, Start+18, Start+19, Start+20],
    [erlang:element(I, Board) || I <- Indices, erlang:element(I, Board) =/= 0].

is_valid_initial(_Board, 82) -> true;
is_valid_initial(Board, Index) ->
    Val = erlang:element(Index, Board),
    if Val == 0 -> is_valid_initial(Board, Index + 1);
       true ->
           TempBoard = erlang:setelement(Index, Board, 0),
           case lists:member(Val, get_candidates(TempBoard, Index)) of
               true -> is_valid_initial(Board, Index + 1);
               false -> false
           end
    end.

parse_board(Str) ->
    erlang:list_to_tuple([C - $0 || C <- Str, C >= $0, C =< $9]).

board_to_string(Board) ->
    [C + $0 || C <- erlang:tuple_to_list(Board)].