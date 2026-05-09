## Batch Sudoku Validator & Solver
A high-performance, concurrent Sudoku solver built in Erlang, designed to demonstrate the Actor Model and Message Passing paradigm. This application ingests batches of unsolved or partially solved Sudoku puzzles, validates their initial states, and solves them using a backtracking algorithm.

## Theoretical Implementations
Task Parallelism (Coarse-Grained): Puzzles are grouped into optimal chunks based on the number of available worker processes.

Variable Architecture: The Sudoku board is modeled as a flat 81-element Tuple to provide O(1) memory access times and eliminate garbage collection bottlenecks.

Control Constructs (Message Passing): A Supervisor distributes tasks to lightweight Worker processes and aggregates the results asynchronously without explicit locks.

Full-Stack Integration: An Erlang-native TCP server processes HTTP POST requests from a vanilla JavaScript frontend.

## Project Structure
ERLANG_PARALLELPROG/
├── index.html
├── puzzles.txt
├── sudoku_batch.beam
├── sudoku_batch.erl
├── sudoku_web.beam
└── sudoku_web.erl

## Execution Instructions
Open a terminal and navigate to the project directory.

Start the Erlang shell:

Bash
erl
Compile the source files inside the shell:

Erlang
1> c(sudoku_batch).
2> c(sudoku_web).
Start the TCP server (listens on port 8080):

Erlang
3> sudoku_web:start().
Open index.html in a web browser, upload your puzzles.txt file, specify worker count, and run the batch.