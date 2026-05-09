-module(sudoku_web).
-export([start/0, accept/1]).

start() ->
    {ok, ListenSocket} = gen_tcp:listen(8080, [
        binary, {packet, http_bin}, {active, false}, {reuseaddr, true}
    ]),
    io:format("~n🚀 Erlang Batch Server running at http://localhost:8080~n"),
    spawn(fun() -> accept(ListenSocket) end).

accept(ListenSocket) ->
    {ok, Socket} = gen_tcp:accept(ListenSocket),
    spawn(fun() -> accept(ListenSocket) end),
    handle_request(Socket).

handle_request(Socket) ->
    case gen_tcp:recv(Socket, 0) of
        %% Batch POST endpoint
        {ok, {http_request, 'POST', {abs_path, <<"/solve_batch">>}, _}} ->
            Headers = get_headers(Socket, []),
            ContentLengthStr = proplists:get_value("content-length", Headers, "0"),
            ContentLength = list_to_integer(ContentLengthStr),
            
            %% Switch socket to raw binary to read the body
            inet:setopts(Socket, [{packet, raw}]),
            {ok, BodyBin} = gen_tcp:recv(Socket, ContentLength),
            
            %% Parse Worker Count from headers (Default 1)
            WorkersStr = proplists:get_value("workers", Headers, "1"),
            NumWorkers = list_to_integer(WorkersStr),
            
            %% Extract puzzles
            PuzzlesBin = binary:split(BodyBin, <<"\n">>, [global, trim_all]),
            PuzzleStrs = [binary_to_list(P) || P <- PuzzlesBin, byte_size(P) =:= 81],
            
            %% Pass to the Erlang Dealer (now returns {Results, ParallelMs})
            {Results, ParallelMs} = sudoku_batch:run_batch(PuzzleStrs, NumWorkers),

            %% Sequential baseline: re-run with 1 worker for Ts
            {SeqResults, SeqMs} = sudoku_batch:run_batch(PuzzleStrs, 1),
            _ = SeqResults,

            %% Print summary + write output files
            sudoku_results:print_summary(Results, ParallelMs, SeqMs, NumWorkers),
            sudoku_results:write_results(Results, "output", ParallelMs, SeqMs, NumWorkers),

            %% Return JSON
            JsonRes = format_results_json(Results),
            ResponseBin = list_to_binary(JsonRes),
            HttpRes = <<"HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: application/json\r\n\r\n", ResponseBin/binary>>,
            gen_tcp:send(Socket, HttpRes),
            gen_tcp:close(Socket);
        
        %% Handle Preflight CORS
        {ok, {http_request, 'OPTIONS', _, _}} ->
            consume_headers(Socket),
            HttpRes = <<"HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type, Workers\r\n\r\n">>,
            gen_tcp:send(Socket, HttpRes),
            gen_tcp:close(Socket);
            
        _ ->
            gen_tcp:close(Socket)
    end.

get_headers(Socket, Acc) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, {http_header, _, Name, _, Value}} ->
            HeaderName = string:to_lower(case is_atom(Name) of true -> atom_to_list(Name); false -> binary_to_list(Name) end),
            get_headers(Socket, [{HeaderName, binary_to_list(Value)} | Acc]);
        {ok, http_eoh} -> Acc;
        _ -> Acc
    end.

consume_headers(Socket) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, {http_header, _, _, _, _}} -> consume_headers(Socket);
        {ok, http_eoh} -> ok;
        _ -> ok
    end.

format_results_json(Results) ->
    Items = [
        lists:flatten(io_lib:format("{\"puzzle\":\"~s\",\"status\":\"~s\",\"board\":\"~s\"}",
        [maps:get(input, R), get_status(maps:get(result, R)), get_board(maps:get(result, R))]))
        || R <- Results
    ],
    "[" ++ string:join(Items, ",") ++ "]".

get_status({solved, _}) -> "solved";
get_status({invalid, _}) -> "invalid";
get_status({unsolvable, _}) -> "unsolvable".
get_board({solved, B}) -> B;
get_board({unsolvable, B}) -> B;
get_board({invalid, _}) -> "".