module tetris_core (
    input wire clk, rst,
    input wire [3:0] btn, // {3:Rot, 2:Left, 1:Right, 0:Down}
    input wire sw_hold,   // From sw[0]
    input wire [9:0] grid_x, grid_y, 
    output reg [2:0] pixel_block_id, 
    output reg [7:0] score,
    output wire [2:0] next_piece_id,
    output wire [2:0] hold_piece_id
);
    parameter COLS = 10;
    parameter ROWS = 20;

    reg [2:0] board [19:0][9:0]; 
    reg [2:0] cur_piece; 
    reg [1:0] cur_rot;
    integer cur_x, cur_y;
    
    // Next Piece
    reg [2:0] next_piece_reg;
    assign next_piece_id = next_piece_reg;
    // Hold Piece
    reg [2:0] hold_piece;
    reg hold_used; 
    assign hold_piece_id = hold_piece;
    
    localparam TIME_DROP_FAST = 5000000;
    localparam TIME_DROP_SLOW = 25000000; 
    
    reg [25:0] timer;
    reg [2:0] state;
    
    // State Definitions
    localparam S_SPAWN     = 3'd0;
    localparam S_ACTIVE    = 3'd1;
    localparam S_LOCK      = 3'd2;
    localparam S_CHECK     = 3'd3; // New State: Check row
    localparam S_ELIMINATE = 3'd4; // New State: Remove row
    
    // Button Edge Detection
    reg [3:0] btn_prev;
    wire [3:0] btn_press = btn & ~btn_prev;
    
    // Switch Edge Detection
    reg sw_prev;
    wire sw_change = (sw_hold != sw_prev); 

    always @(posedge clk) begin
        btn_prev <= btn;
        sw_prev <= sw_hold;
    end

    wire [25:0] drop_limit = (~btn[0]) ? TIME_DROP_FAST : TIME_DROP_SLOW;
    
    // --- Geometry Function ---
    function [7:0] get_offset;
        input [2:0] shape; 
        input [1:0] rot; 
        input [1:0] idx;
        reg signed [3:0] dx, dy;
        begin
            dx = 4'sd0;
            dy = 4'sd0;
            case (shape)
                1: case (rot[0]) // I
                    0: case(idx) 0: begin dx=-4'sd1; dy=4'sd0; end 1: begin dx=4'sd0; dy=4'sd0; end 2: begin dx=4'sd1; dy=4'sd0; end 3: begin dx=4'sd2; dy=4'sd0; end endcase
                    1: case(idx) 0: begin dx=4'sd0; dy=-4'sd1; end 1: begin dx=4'sd0; dy=4'sd0; end 2: begin dx=4'sd0; dy=4'sd1; end 3: begin dx=4'sd0; dy=4'sd2; end endcase
                   endcase
                2: case (rot) // J
                    0: case(idx) 0:{dx,dy}={-4'sd1,-4'sd1}; 1:{dx,dy}={-4'sd1, 4'sd0}; 2:{dx,dy}={ 4'sd0, 4'sd0}; 3:{dx,dy}={ 4'sd1, 4'sd0}; endcase
                    1: case(idx) 0:{dx,dy}={ 4'sd0,-4'sd1}; 1:{dx,dy}={ 4'sd1,-4'sd1}; 2:{dx,dy}={ 4'sd0, 4'sd0}; 3:{dx,dy}={ 4'sd0, 4'sd1}; endcase
                    2: case(idx) 0:{dx,dy}={-4'sd1, 4'sd0}; 1:{dx,dy}={ 4'sd0, 4'sd0}; 2:{dx,dy}={ 4'sd1, 4'sd0}; 3:{dx,dy}={ 4'sd1, 4'sd1}; endcase
                    3: case(idx) 0:{dx,dy}={ 4'sd0,-4'sd1}; 1:{dx,dy}={ 4'sd0, 4'sd0}; 2:{dx,dy}={-4'sd1, 4'sd1}; 3:{dx,dy}={ 4'sd0, 4'sd1}; endcase
                   endcase
                3: case (rot) // L
                    0: case(idx) 0:{dx,dy}={ 4'sd1,-4'sd1}; 1:{dx,dy}={-4'sd1, 4'sd0}; 2:{dx,dy}={ 4'sd0, 4'sd0}; 3:{dx,dy}={ 4'sd1, 4'sd0}; endcase
                    1: case(idx) 0:{dx,dy}={ 4'sd0,-4'sd1}; 1:{dx,dy}={ 4'sd0, 4'sd0}; 2:{dx,dy}={ 4'sd0, 4'sd1}; 3:{dx,dy}={ 4'sd1, 4'sd1}; endcase
                    2: case(idx) 0:{dx,dy}={-4'sd1, 4'sd0}; 1:{dx,dy}={ 4'sd0, 4'sd0}; 2:{dx,dy}={ 4'sd1, 4'sd0}; 3:{dx,dy}={-4'sd1, 4'sd1}; endcase
                    3: case(idx) 0:{dx,dy}={-4'sd1,-4'sd1}; 1:{dx,dy}={ 4'sd0,-4'sd1}; 2:{dx,dy}={ 4'sd0, 4'sd0}; 3:{dx,dy}={ 4'sd0, 4'sd1}; endcase
                   endcase
                4: case(idx) // O
                    0:{dx,dy}={ 4'sd0, 4'sd0}; 1:{dx,dy}={ 4'sd1, 4'sd0}; 2:{dx,dy}={ 4'sd0, 4'sd1}; 3:{dx,dy}={ 4'sd1, 4'sd1}; 
                   endcase
                5: case (rot[0]) // S
                    0: case(idx) 0:{dx,dy}={ 4'sd0, 4'sd0}; 1:{dx,dy}={ 4'sd1, 4'sd0}; 2:{dx,dy}={-4'sd1, 4'sd1}; 3:{dx,dy}={ 4'sd0, 4'sd1}; endcase
                    1: case(idx) 0:{dx,dy}={ 4'sd0,-4'sd1}; 1:{dx,dy}={ 4'sd0, 4'sd0}; 2:{dx,dy}={ 4'sd1, 4'sd0}; 3:{dx,dy}={ 4'sd1, 4'sd1}; endcase
                   endcase
                6: case (rot) // T
                    0: case(idx) 0:{dx,dy}={ 4'sd0,-4'sd1}; 1:{dx,dy}={-4'sd1, 4'sd0}; 2:{dx,dy}={ 4'sd0, 4'sd0}; 3:{dx,dy}={ 4'sd1, 4'sd0}; endcase
                    1: case(idx) 0:{dx,dy}={ 4'sd0,-4'sd1}; 1:{dx,dy}={ 4'sd0, 4'sd0}; 2:{dx,dy}={ 4'sd1, 4'sd0}; 3:{dx,dy}={ 4'sd0, 4'sd1}; endcase
                    2: case(idx) 0:{dx,dy}={-4'sd1, 4'sd0}; 1:{dx,dy}={ 4'sd0, 4'sd0}; 2:{dx,dy}={ 4'sd1, 4'sd0}; 3:{dx,dy}={ 4'sd0, 4'sd1}; endcase
                    3: case(idx) 0:{dx,dy}={ 4'sd0,-4'sd1}; 1:{dx,dy}={-4'sd1, 4'sd0}; 2:{dx,dy}={ 4'sd0, 4'sd0}; 3:{dx,dy}={ 4'sd0, 4'sd1}; endcase
                   endcase
                7: case (rot[0]) // Z
                    0: case(idx) 0:{dx,dy}={-4'sd1, 4'sd0}; 1:{dx,dy}={ 4'sd0, 4'sd0}; 2:{dx,dy}={ 4'sd0, 4'sd1}; 3:{dx,dy}={ 4'sd1, 4'sd1}; endcase
                    1: case(idx) 0:{dx,dy}={ 4'sd1,-4'sd1}; 1:{dx,dy}={ 4'sd0, 4'sd0}; 2:{dx,dy}={ 4'sd1, 4'sd0}; 3:{dx,dy}={ 4'sd0, 4'sd1}; endcase
                   endcase
                default: {dx, dy} = {4'sd0, 4'sd0};
            endcase
            get_offset = {dx, dy};
        end
    endfunction

    // --- Collision Task ---
    reg col_res;
    integer m;
    reg signed [3:0] tox, toy;
    task check_collision;
        input integer tx, ty; 
        input [1:0] tr;
        begin
            col_res = 0;
            for(m=0; m<4; m=m+1) begin
                {tox, toy} = get_offset(cur_piece, tr, m[1:0]);
                if (tx + tox < 0 || tx + tox >= COLS || ty + toy >= ROWS) begin
                    col_res = 1;
                end
                else if (ty + toy >= 0) begin
                    if (board[ty + toy][tx + tox] != 0) col_res = 1;
                end
            end
        end
    endtask

    // --- FSM ---
    integer i, j, k;
    reg signed [3:0] ox, oy;
    
    // Line Clearing Variables
    reg [4:0] lc_row_idx; // Row iterator (0-19)
    reg [1:0] lc_phase;   // 4-clock phase counter
    reg is_row_full;      // Flag
    
    reg [7:0] rand_reg;
    wire [2:0] random_val = (rand_reg[2:0] == 0) ? 1 : rand_reg[2:0];
    reg [2:0] tmp_piece;
    
    always @(posedge clk) begin
        if (rst) begin
            state <= S_SPAWN;
            score <= 0;
            timer <= 0;
            
            rand_reg <= 8'hA5;
            hold_piece <= 0; 
            hold_used <= 0;
            
            lc_row_idx <= 0;
            lc_phase <= 0;

            next_piece_reg <= 1; 
            cur_x <= 0; cur_y <= 0; cur_piece <= 1;
            cur_rot <= 0;
            for(i = 0; i < ROWS; i = i+1) 
                for(j = 0; j < COLS; j = j+1) 
                    board[i][j] <= 0;
        end else begin
            rand_reg <= {rand_reg[6:0], rand_reg[7] ^ rand_reg[5]};
            
            // Timer only counts in Active state
            if (state == S_ACTIVE && timer < drop_limit) timer <= timer + 1;
            
            case(state)
                S_SPAWN: begin // 0: SPAWN
                    cur_piece <= next_piece_reg;
                    next_piece_reg <= random_val;
                    cur_x <= 4; cur_y <= 1; cur_rot <= 0;
                    hold_used <= 0;
                    
                    check_collision(4, 1, 0);
                    if (col_res) begin 
                        for(i=0; i<ROWS; i=i+1) for(j=0; j<COLS; j=j+1) board[i][j] <= 0;
                        score <= 0;
                        hold_piece <= 0;
                    end
                    state <= S_ACTIVE;
                    timer <= 0;
                end

                S_ACTIVE: begin // 1: ACTIVE
                    if (sw_change && !hold_used) begin
                        hold_used <= 1;
                        timer <= 0; 
                        
                        cur_x <= 4;
                        cur_y <= 1; 
                        cur_rot <= 0; 

                        if (hold_piece == 0) begin
                            hold_piece <= cur_piece;
                            cur_piece <= next_piece_reg;
                            next_piece_reg <= random_val;
                        end else begin
                            tmp_piece = cur_piece;
                            cur_piece <= hold_piece;
                            hold_piece <= tmp_piece;
                        end
                    end

                    // Movement
                    if (btn_press[3]) begin
                        check_collision(cur_x, cur_y, cur_rot + 1);
                        if (!col_res) cur_rot <= cur_rot + 1;
                    end
                    if (btn_press[2]) begin // Left
                        check_collision(cur_x - 1, cur_y, cur_rot);
                        if (!col_res) cur_x <= cur_x - 1;
                    end
                    if (btn_press[1]) begin // Right
                        check_collision(cur_x + 1, cur_y, cur_rot);
                        if (!col_res) cur_x <= cur_x + 1;
                    end
                    
                    if (timer >= drop_limit) begin 
                        timer <= 0;
                        check_collision(cur_x, cur_y + 1, cur_rot);
                        if (!col_res) cur_y <= cur_y + 1;
                        else state <= S_LOCK;
                    end
                end

                S_LOCK: begin // 2: LOCK
                    for (k=0; k<4; k=k+1) begin
                        {ox, oy} = get_offset(cur_piece, cur_rot, k[1:0]);
                        if ((cur_y + oy) >= 0 && (cur_y + oy) < ROWS && 
                            (cur_x + ox) >= 0 && (cur_x + ox) < COLS) begin
                            board[cur_y + oy][cur_x + ox] <= cur_piece;
                        end
                    end
                    // Trigger Line Clearing Check
                    state <= S_CHECK;
                    lc_row_idx <= ROWS - 1; // Start check from bottom
                    lc_phase <= 0;
                end

                S_CHECK: begin // 3: CHECK (New State)
                    // Phase 0: Setup / Wait (1 Clock)
                    if (lc_phase == 0) begin
                        lc_phase <= 1;
                    end 
                    // Phase 1: Logic Check (1 Clock)
                    else if (lc_phase == 1) begin
                        // Check if row is full
                        is_row_full = 1;
                        for (j=0; j<COLS; j=j+1) begin
                            if (board[lc_row_idx][j] == 0) is_row_full = 0;
                        end

                        if (is_row_full) begin
                            state <= S_ELIMINATE;
                            lc_phase <= 2;
                        end else begin
                            if (lc_row_idx == 0) begin
                                state <= S_SPAWN; // Checked all rows
                            end else begin
                                lc_row_idx <= lc_row_idx - 1; // Move Up
                                lc_phase <= 0;
                            end
                        end
                    end
                end

                S_ELIMINATE: begin // 4: ELIMINATE (New State)
                    // Phase 2: Setup (1 Clock)
                    if (lc_phase == 2) begin
                        lc_phase <= 3;
                    end
                    // Phase 3: Shift (1 Clock)
                    else if (lc_phase == 3) begin
                        // Shift all rows above lc_row_idx down by 1
                        for (i = 0; i < ROWS; i = i + 1) begin
                            // Shift rows down only if they are at or above the cleared row
                            // We scan from top to 'lc_row_idx'
                            if (i > 0 && i <= lc_row_idx) begin
                                for(j=0; j<COLS; j=j+1) begin
                                    board[i][j] <= board[i-1][j];
                                end
                            end
                        end
                        // Clear the very top row
                        for(j=0; j<COLS; j=j+1) board[0][j] <= 0;
                        
                        score <= score + 1; // Increase score
                        
                        // Stay on same row index because the row above dropped in here
                        state <= S_CHECK;
                        lc_phase <= 0;
                    end
                end
            endcase
        end
    end

    // Rendering
    reg is_active_blk;
    integer n;
    reg signed [3:0] nox, noy;

    always @(*) begin
        pixel_block_id = 0;
        is_active_blk = 0;
        // Only show active piece in SPAWN, ACTIVE, LOCK
        if (state == S_ACTIVE || state == S_LOCK || state == S_SPAWN) begin
            for (n=0; n<4; n=n+1) begin
                {nox, noy} = get_offset(cur_piece, cur_rot, n[1:0]);
                if ($signed({1'b0, grid_x}) == cur_x + nox && 
                    $signed({1'b0, grid_y}) == cur_y + noy) 
                begin
                    is_active_blk = 1;
                end
            end
        end
        if (is_active_blk) pixel_block_id = cur_piece;
        else if (grid_x < COLS && grid_y < ROWS) pixel_block_id = board[grid_y][grid_x];
        else pixel_block_id = 0;
    end
endmodule