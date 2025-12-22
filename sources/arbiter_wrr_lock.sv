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
    // Standard log2 function for width calculation
    function integer clog2;
        input integer value;
        begin
            value = value - 1;
            for (clog2 = 0; value > 0; clog2 = clog2 + 1)
                value = value >> 1;
        end
    endfunction

    localparam PTR_WIDTH = clog2(NUM_CLIENTS*2);

    // -------------------------------------------------------------------------
    // Signal Declarations
    // -------------------------------------------------------------------------
    
    // State Registers
    reg [NUM_CLIENTS*2-1:0]      current_gnt;
    reg [PTR_WIDTH-1:0]        current_ptr;
    reg [WEIGHT_WIDTH-1:0]     weight_cnt;
    reg                        is_active;

    // Next State / Combinational Logic
    reg                        keep_current;
    reg                        found_next;
    reg [PTR_WIDTH-1:0]        next_ptr_search;
    reg [NUM_CLIENTS-1:0]      next_gnt_search;
    
    // Combinational Weight Mux
    reg [WEIGHT_WIDTH-1:0]     next_weight_val;

    // Loop variables
    integer i;
    integer idx;
    reg     already_found;
    integer weight_idx_base;

    // -------------------------------------------------------------------------
    // Arbitration Logic
    // -------------------------------------------------------------------------

    // 1. Check if the Current Owner keeps the grant
    always @(*) begin
        keep_current = 1'b0; // Default

        if (is_active && i_req[current_ptr]) begin
            // Check Lock (Spec 3.3): Only valid if held by current owner
            if (i_lock[current_ptr]) begin
                keep_current = 1'b1;
            end 
            // Check Weight Credits (Spec 3.2)
            else if (weight_cnt > 0) begin
                keep_current = 1'b1;
            end 
            else begin
                keep_current = 1'b0; // Time's up
            end
        end else begin
            keep_current = 1'b0; // Dropped request or inactive
        end
    end

    // 2. Round Robin Search (Forward Loop with Flag)
    always @(*) begin
        found_next      = 1'b0;
        next_ptr_search = {PTR_WIDTH{1'b0}};
        next_gnt_search = {NUM_CLIENTS{1'b0}};
        already_found   = 1'b0;
        idx             = 0;
        
        // Scan from CLOSEST (current_ptr + 1) to FURTHEST
        for (i = 1; i <= NUM_CLIENTS; i = i + 1) begin
            // Calculate candidate index with manual wrap-around
            idx = current_ptr + i;
            if (idx >= NUM_CLIENTS) begin
                idx = idx - NUM_CLIENTS;
            end
            
            // If request exists AND we haven't found a closer one yet
            if (i_req[idx] && !already_found) begin
                found_next        = 1'b1;
                next_ptr_search   = idx[PTR_WIDTH-1:0];
                
                next_gnt_search   = {NUM_CLIENTS{1'b0}};
                next_gnt_search[idx] = 1'b1;
                
                already_found     = 1'b1; // Lock the decision
            end
        end
    end
    
    // 3. Weight Mux 
    // Uses Verilog-2001 Indexed Part-Select [base +: width]
    always @(*) begin
        weight_idx_base = next_ptr_search * WEIGHT_WIDTH;
        next_weight_val = i_weight[weight_idx_base +: WEIGHT_WIDTH];
    end

    // -------------------------------------------------------------------------
    // Sequential State Update
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_gnt <= {NUM_CLIENTS{1'b0}};
            // Initialize to N-1 so the first search (ptr+1) checks Client 0 first.
            current_ptr <= NUM_CLIENTS[PTR_WIDTH-1:0] - 1'b1;
            weight_cnt  <= {WEIGHT_WIDTH{1'b0}};
            is_active   <= 1'b0;
        end else begin
            if (keep_current) begin
                // --- Maintain Current Grant ---
                // Decrement weight if > 0
                if (weight_cnt > 0) begin
                    weight_cnt <= weight_cnt - 1'b1;
                end
            end else begin
                // --- Rotate / Switch ---
                if (found_next) begin
                    current_gnt <= next_gnt_search;
                    current_ptr <= next_ptr_search;
                    
                    // Load extracted weight
                    weight_cnt  <= next_weight_val;
                    is_active   <= 1'b1;
                end else begin
                    // No requests: Go Idle
                    current_gnt <= {NUM_CLIENTS{1'b0}};
                    is_active   <= 1'b0;
                end
            end
        end
    end

    assign o_gnt = current_gnt;
endmodule
