`timescale 1ns/1ps

module arbiter_wrr_lock #(
    parameter NUM_CLIENTS  = 4,
    parameter WEIGHT_WIDTH = 4
) (
    input  wire                        clk,
    input  wire                        rst_n,
    
    // Client Interface
    input  wire [NUM_CLIENTS-1:0]      i_req,
    input  wire [NUM_CLIENTS-1:0]      i_lock,
    
    // Configuration (Packed array flattened)
    // Format: [ (CLIENT_N_W).. | .. | (CLIENT_1_W) | (CLIENT_0_W) ]
    input  wire [NUM_CLIENTS*WEIGHT_WIDTH-1:0] i_weight,
    
    // Output Grant (One-Hot)
    output wire [NUM_CLIENTS-1:0]      o_gnt
);

    // -------------------------------------------------------------------------
    // Helper Functions
    // -------------------------------------------------------------------------
    function integer clog2;
        input integer value;
        begin
            value = value - 1;
            for (clog2 = 0; value > 0; clog2 = clog2 + 1)
                value = value >> 1;
        end
    endfunction

    localparam PTR_WIDTH = clog2(NUM_CLIENTS);

    // -------------------------------------------------------------------------
    // Signal Declarations
    // -------------------------------------------------------------------------
    
    // State Registers - Optimized
    reg [NUM_CLIENTS-1:0]      current_gnt;
    reg [PTR_WIDTH-1:0]        current_ptr;
    reg [WEIGHT_WIDTH-1:0]     weight_cnt;
    
    // Combinational signals
    wire                       keep_current;
    wire [NUM_CLIENTS-1:0]     req_rotated;
    wire [PTR_WIDTH-1:0]       next_ptr;
    
    // -------------------------------------------------------------------------
    // Priority Encoder - Find lowest bit set (parameterized)
    // -------------------------------------------------------------------------
    function automatic [PTR_WIDTH-1:0] find_first_set;
        input [NUM_CLIENTS-1:0] req;
        integer i;
        begin
            find_first_set = {PTR_WIDTH{1'b0}};
            for (i = 0; i < NUM_CLIENTS; i = i + 1) begin
                if (req[i]) begin
                    find_first_set = i[PTR_WIDTH-1:0];
                    i = NUM_CLIENTS; // Break
                end
            end
        end
    endfunction
    
    // -------------------------------------------------------------------------
    // Keep Current Logic
    // -------------------------------------------------------------------------
    assign keep_current = (|current_gnt) & i_req[current_ptr] & (i_lock[current_ptr] | (|weight_cnt));
    
    // -------------------------------------------------------------------------
    // Round Robin Search (Optimized with Rotation)
    // -------------------------------------------------------------------------
    // Rotate requests so that position after current_ptr is at bit 0
    assign req_rotated = {i_req, i_req} >> (current_ptr + 1'b1);
    
    // Find first request and convert back to original indexing
    // For power-of-2 NUM_CLIENTS, modulo is automatic via bit width truncation
    assign next_ptr = current_ptr + 1'b1 + find_first_set(req_rotated[NUM_CLIENTS-1:0]);
    
    // -------------------------------------------------------------------------
    // Sequential State Update
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_gnt <= {NUM_CLIENTS{1'b0}};
            current_ptr <= NUM_CLIENTS[PTR_WIDTH-1:0] - 1'b1;
            weight_cnt  <= {WEIGHT_WIDTH{1'b0}};
        end else if (keep_current) begin
            // Maintain current grant, decrement weight (saturating at 0)
            weight_cnt <= (|weight_cnt) ? (weight_cnt - 1'b1) : weight_cnt;
        end else if (|i_req) begin
            // Switch to next requester
            current_gnt <= (1'b1 << next_ptr);
            current_ptr <= next_ptr;
            weight_cnt  <= i_weight[next_ptr*WEIGHT_WIDTH +: WEIGHT_WIDTH];
        end else begin
            // No requests - go idle
            current_gnt <= {NUM_CLIENTS{1'b0}};
        end
    end

    assign o_gnt = current_gnt;
    
endmodule
