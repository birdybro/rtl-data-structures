// =============================================================================
// task_scheduler.sv  –  Example: Task Scheduler using Priority Queue
// =============================================================================
// Demonstrates a 4-slot task scheduler that accepts tasks with priority
// (lower number = higher priority) and dispatches the highest-priority ready
// task each cycle.
//
// Instantiates: priority_queue_linear
//
// Interface:
//   clk, rst_n
//   task_submit        – pulse to submit a new task
//   task_priority[3:0] – priority of submitted task (0 = highest)
//   task_id[7:0]       – identifier of submitted task
//   dispatch_en        – pulse to dispatch (dequeue) next task
//   dispatched_id[7:0]       – task ID of dispatched task
//   dispatched_priority[3:0] – priority of dispatched task
//   scheduler_full     – no room for new tasks
//   scheduler_empty    – no tasks pending
//   task_count[4:0]    – number of pending tasks
// =============================================================================

`timescale 1ns/1ps

`include "../rtl/priority/priority_queue_linear.sv"

module task_scheduler #(
    parameter int TASK_ID_WIDTH    = 8,
    parameter int PRIORITY_WIDTH   = 4,
    parameter int QUEUE_DEPTH      = 16
) (
    input  logic                        clk,
    input  logic                        rst_n,

    // Task submission
    input  logic                        task_submit,
    input  logic [PRIORITY_WIDTH-1:0]   task_priority,
    input  logic [TASK_ID_WIDTH-1:0]    task_id,

    // Task dispatch
    input  logic                        dispatch_en,
    output logic [TASK_ID_WIDTH-1:0]    dispatched_id,
    output logic [PRIORITY_WIDTH-1:0]   dispatched_priority,

    // Status
    output logic                        scheduler_full,
    output logic                        scheduler_empty,
    output logic [$clog2(QUEUE_DEPTH):0] task_count
);

    // -------------------------------------------------------------------------
    // Instantiate priority queue
    // -------------------------------------------------------------------------
    // priority_queue_linear presents the highest-priority (lowest numeric
    // value) entry at dout/priority_out whenever the queue is non-empty.
    // A push adds one entry; a pop removes the current head.
    // -------------------------------------------------------------------------
    priority_queue_linear #(
        .DATA_WIDTH     (TASK_ID_WIDTH),
        .PRIORITY_WIDTH (PRIORITY_WIDTH),
        .DEPTH          (QUEUE_DEPTH)
    ) u_pq (
        .clk          (clk),
        .rst_n        (rst_n),
        .push         (task_submit),
        .pop          (dispatch_en),
        .din          (task_id),
        .priority_in  (task_priority),
        .dout         (dispatched_id),
        .priority_out (dispatched_priority),
        .full         (scheduler_full),
        .empty        (scheduler_empty),
        .count        (task_count)
    );

endmodule
