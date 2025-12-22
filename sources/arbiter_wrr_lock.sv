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
    
    // Configuration (Packed: [Client N-1 | ... | Client 0])
    input  wire [NUM_CLIENTS*WEIGHT_WIDTH-1:0] i_weight,
    
    // Output Grant (One-Hot)
    output wire [NUM_CLIENTS-1:0]           o_gnt
);

    // -------------------------------------------------------------------------
    // Parameters & Helper Functions
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
    reg [PTR_WIDTH-1:0]    ptr_q;      // Pointer to current or last owner
    reg [WEIGHT_WIDTH-1:0] weight_q;   // Current weight counter
    reg                    active_q;   // 1 if a client actively holds grant

    // -------------------------------------------------------------------------
    // Combinational Logic Variables
    // -------------------------------------------------------------------------
    reg                    next_active;
    reg [PTR_WIDTH-1:0]    next_ptr;
    reg [WEIGHT_WIDTH-1:0] next_weight;
    reg                    load_weight;
    
    // Variable for loop
    integer i;

    // -------------------------------------------------------------------------
    // Next State Logic
    // -------------------------------------------------------------------------
    always @(*) begin
        // Defaults
        next_active = active_q;
        next_ptr    = ptr_q;
        next_weight = weight_q;
        load_weight = 1'b0;

        // 1. Check if current owner maintains the grant
        // --------------------------------------------
        if (active_q && i_req[ptr_q]) begin
            // Locked by client OR Weight credits remaining
            if (i_lock[ptr_q] || (weight_q > 0)) begin
                // Maintain current state
                next_active = 1'b1;
                next_ptr    = ptr_q;
                
                // Decrement weight if not locked (and weight > 0)
                // Note: Spec says "While locked, weight counter decrements normally"
                if (weight_q > 0) begin
                    next_weight = weight_q - 1'b1;
                end
            end else begin
                // Grant expired
                next_active = 1'b0; 
            end
        end else begin
            // Request dropped or was already idle
            next_active = 1'b0;
        end

        // 2. Arbitration Search (If not maintaining current)
        // --------------------------------------------------
        if (!next_active) begin
            // Search for the next request starting from (ptr_q + 1).
            // We iterate NUM_CLIENTS times. The standard "Double Request" 
            // logic is effectively implemented here via the loop and modulo.
            
            for (i = 1; i <= NUM_CLIENTS; i = i + 1) begin
                // Calculate index with wrap-around logic
                // Using intermediate int ensures cleaner synthesis than % operator
                integer idx;
                idx = ptr_q + i;
                if (idx >= NUM_CLIENTS) idx = idx - NUM_CLIENTS;

                // Priority Check
                // If we found a request, update next state and break the search
                // (Note: 'next_active' is currently 0, acts as 'found' flag)
                if (i_req[idx] && !next_active) begin
                    next_ptr    = idx[PTR_WIDTH-1:0];
                    next_active = 1'b1;
                    load_weight = 1'b1;
                end
            end
        end

        // 3. Weight Loading (If switching to new client)
        // ----------------------------------------------
        if (load_weight) begin
            // Indexed Part-Select to extract weight
            next_weight = i_weight[next_ptr * WEIGHT_WIDTH +: WEIGHT_WIDTH];
        end
    end

    // -------------------------------------------------------------------------
    // Sequential Update
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_q <= 1'b0;
            // Reset to N-1 so first search (ptr+1) checks Client 0
            ptr_q    <= NUM_CLIENTS[PTR_WIDTH-1:0] - 1'b1; 
            weight_q <= {WEIGHT_WIDTH{1'b0}};
        end else begin
            active_q <= next_active;
            ptr_q    <= next_ptr;
            weight_q <= next_weight;
        end
    end

    // -------------------------------------------------------------------------
    // Output Logic
    // -------------------------------------------------------------------------
    // Decode the binary pointer to one-hot grant
    assign o_gnt = active_q ? ({{(NUM_CLIENTS-1){1'b0}}, 1'b1} << ptr_q) : {NUM_CLIENTS{1'b0}};

endmodule