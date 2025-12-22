`timescale 1ns/1ps

module arbiter_wrr_lock #(
    parameter NUM_CLIENTS  = 4,
    parameter WEIGHT_WIDTH = 4
) (
    input  wire                             clk,
    input  wire                             rst_n,
    
    // Client Interface
    input  wire [NUM_CLIENTS-1:0]           i_req,
    input  wire [NUM_CLIENTS-1:0]           i_lock,
    
    // Configuration (Packed array)
    input  wire [NUM_CLIENTS*WEIGHT_WIDTH-1:0] i_weight,
    
    // Output Grant (One-Hot)
    output wire [NUM_CLIENTS-1:0]           o_gnt
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
    // Internal State
    // -------------------------------------------------------------------------
    reg [PTR_WIDTH-1:0]    ptr_q;      // Pointer to current owner
    reg [WEIGHT_WIDTH-1:0] weight_q;   // Weight counter
    reg                    active_q;   // Active transaction flag

    // -------------------------------------------------------------------------
    // Combinational Logic Signals
    // -------------------------------------------------------------------------
    reg [PTR_WIDTH-1:0]    next_ptr;
    reg                    next_active;
    reg                    load_weight;
    
    // Rotated request vector for simple priority encoding
    wire [NUM_CLIENTS-1:0] req_rotated;
    wire [NUM_CLIENTS-1:0] req_masked;
    
    // -------------------------------------------------------------------------
    // 1. Double-Request masking (Replaces barrel shifter)
    // -------------------------------------------------------------------------
    // We concatenate i_req to itself to simulate the "wrap around" search.
    // We mask out bits lower than (ptr_q + 1) to force search to start AFTER current.
    wire [2*NUM_CLIENTS-1:0] double_req = {i_req, i_req};
    
    // Mask out bits <= ptr_q in the lower half to strictly enforce round-robin
    wire [2*NUM_CLIENTS-1:0] search_mask = {NUM_CLIENTS{1'b1}} << (ptr_q + 1'b1);
    wire [2*NUM_CLIENTS-1:0] masked_req  = double_req & search_mask;

    // -------------------------------------------------------------------------
    // 2. Priority Encoder (Find First Set)
    // -------------------------------------------------------------------------
    // Finds the first '1' in the masked vector. Because we use a 2*N vector,
    // the result naturally handles the wrap-around case.
    integer i;
    reg [PTR_WIDTH:0] found_offset; // 1 bit wider to handle "no match"
    reg               found_any;

    always @(*) begin
        found_offset = '0;
        found_any    = 1'b0;
        
        // Scan limited range: from (ptr+1) up to (ptr+N)
        for (i = 0; i < NUM_CLIENTS; i = i + 1) begin
            if (masked_req[ptr_q + 1 + i]) begin
                found_offset = ptr_q + 1 + i; // Absolute index in double_req
                found_any    = 1'b1;
                // Break loop simulation (synthesis ignores 'break' but honors logic)
                i = NUM_CLIENTS; 
            end
        end
    end

    // -------------------------------------------------------------------------
    // 3. Next State Logic
    // -------------------------------------------------------------------------
    always @(*) begin
        // Defaults: Hold state
        next_ptr    = ptr_q;
        next_active = active_q;
        load_weight = 1'b0;

        // A. Check if current owner keeps grant
        if (active_q && i_req[ptr_q]) begin
            if (i_lock[ptr_q] || (|weight_q)) begin
                next_active = 1'b1;
            end else begin
                next_active = 1'b0; // Time expired
            end
        end else begin
            next_active = 1'b0; // Request dropped or idle
        end

        // B. Search for new owner (if not keeping current)
        if (!next_active) begin
            if (found_any) begin
                // Modulo arithmetic is automatic if we just take lower bits
                // because NUM_CLIENTS is power-of-2.
                next_ptr    = found_offset[PTR_WIDTH-1:0];
                next_active = 1'b1;
                load_weight = 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 4. Sequential Update
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_q <= 1'b0;
            ptr_q    <= {PTR_WIDTH{1'b1}}; // N-1 (all 1s)
            weight_q <= '0;
        end else begin
            ptr_q    <= next_ptr;
            active_q <= next_active;

            // Weight Logic
            if (active_q && next_active && (ptr_q == next_ptr)) begin
                // Decrement if holding and valid
                if (|weight_q) weight_q <= weight_q - 1'b1;
            end else if (load_weight) begin
                // Load new weight
                weight_q <= i_weight[next_ptr*WEIGHT_WIDTH +: WEIGHT_WIDTH];
            end
        end
    end

    // -------------------------------------------------------------------------
    // 5. Output Logic (Combinational)
    // -------------------------------------------------------------------------
    assign o_gnt = active_q ? (1'b1 << ptr_q) : {NUM_CLIENTS{1'b0}};

endmodule