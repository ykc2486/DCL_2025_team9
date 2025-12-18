module tetris_core (
    input  wire       clk,            // 50MHz (from divider)
    input  wire       rst,
    input  wire [3:0] btn,            // {3:Rot, 2:Left, 1:Right, 0:Down/Start}
    input  wire       sw_hold,        // sw[0]: Hold
    input  wire       sw_pause,       // sw[1]: Pause
    input  wire [9:0] grid_x,
    input  wire [9:0] grid_y,
    output reg  [2:0] pixel_block_id,
    output reg  [7:0] score,
    output wire [2:0] next_piece_id,
    output wire [2:0] hold_piece_id,
    output wire [2:0] game_status,    // 0:IDLE, 1:SPAWN, 2:ACTIVE, 3:LOCK, 4:CLEAR, 5:OVER, 6:PAUSE
    output reg  [7:0] level           // Output Level
);

    // --- Parameters ---
    parameter COLS = 10;
    parameter ROWS = 20;

    // --- State Definitions ---
    localparam S_IDLE     = 0;
    localparam S_SPAWN    = 1;
    localparam S_ACTIVE   = 2;
    localparam S_LOCK     = 3;
    localparam S_CLEAR    = 4;
    localparam S_GAMEOVER = 5;
    localparam S_PAUSE    = 6;

    reg [2:0] state;
    assign game_status = state;

    // --- Game Board & Piece State ---
    reg [2:0] board [19:0][9:0];
    reg [2:0] cur_piece;
    reg [1:0] cur_rot;
    integer   cur_x, cur_y;

    // --- Next & Hold ---
    reg [2:0] next_piece_reg;
    assign next_piece_id = next_piece_reg;

    reg [2:0] hold_piece;
    reg       hold_used;
    assign hold_piece_id = hold_piece;

    // --- [Speed Control] ---
    // Assuming clk is 50MHz
    // 0.1s = 50,000,000 * 0.1 = 5,000,000 ticks
    localparam TIME_DROP_FAST = 5000000;   // Down key speed (0.1s)
    localparam TIME_BASE      = 25000000;  // Base speed (0.5s)
    localparam TIME_STEP      = 5000000;   // Speed increase step (0.1s)
    localparam TIME_MIN       = 2500000;   // Max speed limit (0.05s)

    reg  [25:0] current_speed_limit;
    wire [7:0]  speed_stage = level; // Every 3 levels is a speed stage

    always @(*) begin
        // Formula: Speed = Base - (Stage * 0.1s)
        if ((speed_stage * TIME_STEP) >= (TIME_BASE - TIME_MIN)) begin
            current_speed_limit = TIME_MIN;
        end else begin
            current_speed_limit = TIME_BASE - (speed_stage * TIME_STEP);
        end
    end

    reg  [25:0] timer;
    wire [25:0] drop_limit = (~btn[0]) ? TIME_DROP_FAST : current_speed_limit;

    // --- [Line Count] ---
    reg [5:0] lines_cleared_accumulator;

    // --- Input Edge Detection ---
    reg  [3:0] btn_prev;
    wire [3:0] btn_press = btn & ~btn_prev;
    
    reg  sw_prev;
    wire sw_change = (sw_hold != sw_prev);
    
    reg  pause_sw_prev;
    wire pause_sw_change = (sw_pause != pause_sw_prev);

    // --- FSM Variables ---
    integer check_row, k, i, j, loop_k;
    reg     full_row;
    reg signed [3:0] ox, oy;
    reg [7:0] rand_reg;
    wire [2:0] random_val = (rand_reg[2:0] == 0) ? 1 : rand_reg[2:0];
    reg [2:0] tmp_piece;
    reg [31:0] init_timer;

    // --- Geometry Function ---
    function [7:0] get_offset;
        input [2:0] shape;
        input [1:0] rot;
        input [1:0] idx;
        reg signed [3:0] dx, dy;
        begin
            dx = 0; dy = 0;
            case (shape)
                1: begin // I-Piece
                    case (rot[0])
                        0: case(idx)
                               0: {dx, dy} = {-4'sd1, 4'sd0};
                               1: {dx, dy} = { 4'sd0, 4'sd0};
                               2: {dx, dy} = { 4'sd1, 4'sd0};
                               3: {dx, dy} = { 4'sd2, 4'sd0};
                           endcase
                        1: case(idx)
                               0: {dx, dy} = { 4'sd0, -4'sd1};
                               1: {dx, dy} = { 4'sd0,  4'sd0};
                               2: {dx, dy} = { 4'sd0,  4'sd1};
                               3: {dx, dy} = { 4'sd0,  4'sd2};
                           endcase
                    endcase
                end
                2: begin // J-Piece
                    case (rot)
                        0: case(idx)
                               0: {dx, dy} = {-4'sd1, -4'sd1};
                               1: {dx, dy} = {-4'sd1,  4'sd0};
                               2: {dx, dy} = { 4'sd0,  4'sd0};
                               3: {dx, dy} = { 4'sd1,  4'sd0};
                           endcase
                        1: case(idx)
                               0: {dx, dy} = { 4'sd0, -4'sd1};
                               1: {dx, dy} = { 4'sd1, -4'sd1};
                               2: {dx, dy} = { 4'sd0,  4'sd0};
                               3: {dx, dy} = { 4'sd0,  4'sd1};
                           endcase
                        2: case(idx)
                               0: {dx, dy} = {-4'sd1,  4'sd0};
                               1: {dx, dy} = { 4'sd0,  4'sd0};
                               2: {dx, dy} = { 4'sd1,  4'sd0};
                               3: {dx, dy} = { 4'sd1,  4'sd1};
                           endcase
                        3: case(idx)
                               0: {dx, dy} = { 4'sd0, -4'sd1};
                               1: {dx, dy} = { 4'sd0,  4'sd0};
                               2: {dx, dy} = {-4'sd1,  4'sd1};
                               3: {dx, dy} = { 4'sd0,  4'sd1};
                           endcase
                    endcase
                end
                3: begin // L-Piece
                    case (rot)
                        0: case(idx)
                               0: {dx, dy} = { 4'sd1, -4'sd1};
                               1: {dx, dy} = {-4'sd1,  4'sd0};
                               2: {dx, dy} = { 4'sd0,  4'sd0};
                               3: {dx, dy} = { 4'sd1,  4'sd0};
                           endcase
                        1: case(idx)
                               0: {dx, dy} = { 4'sd0, -4'sd1};
                               1: {dx, dy} = { 4'sd0,  4'sd0};
                               2: {dx, dy} = { 4'sd0,  4'sd1};
                               3: {dx, dy} = { 4'sd1,  4'sd1};
                           endcase
                        2: case(idx)
                               0: {dx, dy} = {-4'sd1,  4'sd0};
                               1: {dx, dy} = { 4'sd0,  4'sd0};
                               2: {dx, dy} = { 4'sd1,  4'sd0};
                               3: {dx, dy} = {-4'sd1,  4'sd1};
                           endcase
                        3: case(idx)
                               0: {dx, dy} = {-4'sd1, -4'sd1};
                               1: {dx, dy} = { 4'sd0, -4'sd1};
                               2: {dx, dy} = { 4'sd0,  4'sd0};
                               3: {dx, dy} = { 4'sd0,  4'sd1};
                           endcase
                    endcase
                end
                4: begin // O-Piece
                    case (idx)
                        0: {dx, dy} = { 4'sd0, 4'sd0};
                        1: {dx, dy} = { 4'sd1, 4'sd0};
                        2: {dx, dy} = { 4'sd0, 4'sd1};
                        3: {dx, dy} = { 4'sd1, 4'sd1};
                    endcase
                end
                5: begin // S-Piece
                    case (rot[0])
                        0: case(idx)
                               0: {dx, dy} = { 4'sd0, 4'sd0};
                               1: {dx, dy} = { 4'sd1, 4'sd0};
                               2: {dx, dy} = {-4'sd1, 4'sd1};
                               3: {dx, dy} = { 4'sd0, 4'sd1};
                           endcase
                        1: case(idx)
                               0: {dx, dy} = { 4'sd0, -4'sd1};
                               1: {dx, dy} = { 4'sd0,  4'sd0};
                               2: {dx, dy} = { 4'sd1,  4'sd0};
                               3: {dx, dy} = { 4'sd1,  4'sd1};
                           endcase
                    endcase
                end
                6: begin // T-Piece
                    case (rot)
                        0: case(idx)
                               0: {dx, dy} = { 4'sd0, -4'sd1};
                               1: {dx, dy} = {-4'sd1,  4'sd0};
                               2: {dx, dy} = { 4'sd0,  4'sd0};
                               3: {dx, dy} = { 4'sd1,  4'sd0};
                           endcase
                        1: case(idx)
                               0: {dx, dy} = { 4'sd0, -4'sd1};
                               1: {dx, dy} = { 4'sd0,  4'sd0};
                               2: {dx, dy} = { 4'sd1,  4'sd0};
                               3: {dx, dy} = { 4'sd0,  4'sd1};
                           endcase
                        2: case(idx)
                               0: {dx, dy} = {-4'sd1,  4'sd0};
                               1: {dx, dy} = { 4'sd0,  4'sd0};
                               2: {dx, dy} = { 4'sd1,  4'sd0};
                               3: {dx, dy} = { 4'sd0,  4'sd1};
                           endcase
                        3: case(idx)
                               0: {dx, dy} = { 4'sd0, -4'sd1};
                               1: {dx, dy} = {-4'sd1,  4'sd0};
                               2: {dx, dy} = { 4'sd0,  4'sd0};
                               3: {dx, dy} = { 4'sd0,  4'sd1};
                           endcase
                    endcase
                end
                7: begin // Z-Piece
                    case (rot[0])
                        0: case(idx)
                               0: {dx, dy} = {-4'sd1, 4'sd0};
                               1: {dx, dy} = { 4'sd0, 4'sd0};
                               2: {dx, dy} = { 4'sd0, 4'sd1};
                               3: {dx, dy} = { 4'sd1, 4'sd1};
                           endcase
                        1: case(idx)
                               0: {dx, dy} = { 4'sd1, -4'sd1};
                               1: {dx, dy} = { 4'sd0,  4'sd0};
                               2: {dx, dy} = { 4'sd1,  4'sd0};
                               3: {dx, dy} = { 4'sd0,  4'sd1};
                           endcase
                    endcase
                end
                default: {dx, dy} = {4'sd0, 4'sd0};
            endcase
            get_offset = {dx, dy};
        end
    endfunction

    // --- Collision Detection Task ---
    reg col_res;
    integer m;
    reg signed [3:0] tox, toy;
    reg [3:0] tmp_score;

    task check_collision;
        input integer tx, ty;
        input [1:0] tr;
        begin
            col_res = 0;
            for (m = 0; m < 4; m = m + 1) begin
                {tox, toy} = get_offset(cur_piece, tr, m[1:0]);
                if (tx + tox < 0 || tx + tox >= COLS || ty + toy >= ROWS) begin
                    col_res = 1;
                end else if (ty + toy > -1 && board[ty + toy][tx + tox] != 0) begin
                    col_res = 1;
                end
            end
        end
    endtask
    
    reg [31:0] rand_timer;
    // --- Main FSM ---
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            score <= 0;
            timer <= 0;
            level <= 0;
            lines_cleared_accumulator <= 0;
            rand_reg <= 8'hA5;
            rand_timer <= 0;
            next_piece_reg <= 1;
            hold_piece <= 0;
            hold_used <= 0;
            init_timer <= 0;
            cur_x <= 0; cur_y <= 0; cur_piece <= 1; cur_rot <= 0;
            for (i=0; i<ROWS; i=i+1) 
                for (j=0; j<COLS; j=j+1) 
                    board[i][j] <= 0;
            btn_prev <= btn;
            sw_prev <= sw_hold;
            pause_sw_prev <= sw_pause;
        end else begin
            btn_prev <= btn;
            sw_prev <= sw_hold;
            pause_sw_prev <= sw_pause;
            
            if(rand_timer < 1_000_000) begin
                rand_timer <= rand_timer + 1;
                rand_reg <= {rand_reg[6:0], rand_reg[7] ^ rand_reg[5]};
            end
            else begin
                rand_timer <= 0;
                rand_reg <= rand_reg + 1;
            end
            case (state)
                S_IDLE: begin
                    if (init_timer < 100000000) begin
                        init_timer <= init_timer + 1;
                    end else begin
                        rand_reg <= rand_reg + 1; // Increase random seed variation
                        if (btn_press[0]) begin
                            score <= 0;
                            level <= 0;
                            lines_cleared_accumulator <= 0;
                            hold_piece <= 0;
                            for (i=0; i<ROWS; i=i+1) for (j=0; j<COLS; j=j+1) board[i][j] <= 0;
                            state <= S_SPAWN;
                        end
                    end
                end

                S_SPAWN: begin
                    cur_piece <= next_piece_reg;
                    next_piece_reg <= random_val;
                    cur_x <= 4; cur_y <= 1; cur_rot <= 0;
                    hold_used <= 0;
                    check_collision(4, 0, 0);
                    if (col_res) state <= S_GAMEOVER;
                    else begin
                        state <= S_ACTIVE;
                        timer <= 0;
                    end
                end

                S_ACTIVE: begin
                    if (pause_sw_change && sw_pause) begin
                        state <= S_PAUSE;
                    end else begin
                        if (timer < drop_limit) timer <= timer + 1;

                        // Hold Functionality
                        if (sw_change && !hold_used) begin
                            hold_used <= 1;
                            timer <= 0;
                            cur_x <= 4; cur_y <= 1; cur_rot <= 0;
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

                        // Rotate Logic (with wall kicks)
                        if (btn_press[3]) begin
                            check_collision(cur_x, cur_y, cur_rot + 1);
                            if (!col_res) begin
                                cur_rot <= cur_rot + 1;
                            end else begin
                                // Kick Right
                                check_collision(cur_x + 1, cur_y, cur_rot + 1);
                                if (!col_res) begin
                                    cur_rot <= cur_rot + 1;
                                    cur_x <= cur_x + 1;
                                end else begin
                                    // Kick Left
                                    check_collision(cur_x - 1, cur_y, cur_rot + 1);
                                    if (!col_res) begin
                                        cur_rot <= cur_rot + 1;
                                        cur_x <= cur_x - 1;
                                    end else begin
                                        // Kick Up (Floor kick)
                                        check_collision(cur_x, cur_y - 1, cur_rot + 1);
                                        if (!col_res) begin
                                            cur_rot <= cur_rot + 1;
                                            cur_y <= cur_y - 1;
                                        end
                                    end
                                end
                            end
                        end

                        // Move Left/Right
                        if (btn_press[2]) begin
                            check_collision(cur_x - 1, cur_y, cur_rot);
                            if (!col_res) cur_x <= cur_x - 1;
                        end
                        if (btn_press[1]) begin
                            check_collision(cur_x + 1, cur_y, cur_rot);
                            if (!col_res) cur_x <= cur_x + 1;
                        end

                        // Gravity
                        if (timer >= drop_limit) begin
                            timer <= 0;
                            check_collision(cur_x, cur_y + 1, cur_rot);
                            if (!col_res) cur_y <= cur_y + 1;
                            else state <= S_LOCK;
                        end
                    end
                end

                S_PAUSE: begin
                    if (pause_sw_change && !sw_pause) state <= S_ACTIVE;
                end

                S_LOCK: begin
                    for (k=0; k<4; k=k+1) begin
                        {ox, oy} = get_offset(cur_piece, cur_rot, k[1:0]);
                        if ((cur_y+oy)>=0 && (cur_y+oy)<ROWS && (cur_x+ox)>=0 && (cur_x+ox)<COLS)
                            board[cur_y+oy][cur_x+ox] <= cur_piece;
                    end
                    state <= S_CLEAR;
                    check_row <= ROWS - 1;
                end

                S_CLEAR: begin
                    if (check_row < 0) begin
                        state <= S_SPAWN;
                    end else begin
                        full_row = 1;
                        for (j=0; j<COLS; j=j+1) begin
                            if (board[check_row][j] == 0) full_row = 0;
                        end

                        if (full_row) begin
                            // [Level Control] Increase level every 5 lines cleared
                            if (lines_cleared_accumulator >= 5) begin
                                lines_cleared_accumulator <= 0;
                                level <= level + 1;
                            end else begin
                                lines_cleared_accumulator <= lines_cleared_accumulator + 1;
                            end

                            // Score calculation logic
                            if (tmp_score == 0) tmp_score <= 1;
                            else if (tmp_score == 1) tmp_score <= 3;
                            else if (tmp_score == 3) tmp_score <= 5;
                            else tmp_score <= 8;

                            // Shift lines down
                            for (loop_k = ROWS-1; loop_k > 0; loop_k = loop_k - 1) begin
                                if (loop_k <= check_row) begin
                                    for (j=0; j<COLS; j=j+1) board[loop_k][j] <= board[loop_k-1][j];
                                end
                            end
                            for (j=0; j<COLS; j=j+1) board[0][j] <= 0;

                        end else if (check_row == 0) begin
                            state <= S_SPAWN;
                            score <= score + tmp_score;
                            tmp_score <= 0;
                        end else begin
                            check_row <= check_row - 1;
                        end
                    end
                end

                S_GAMEOVER: begin
                    if (btn_press[1]) state <= S_IDLE;
                end
            endcase
        end
    end

    // --- Rendering ---
    reg is_active_blk;
    integer n;
    reg signed [3:0] nox, noy;

    always @(*) begin
        pixel_block_id = 0;
        is_active_blk = 0;
        
        if (state == S_ACTIVE || state == S_LOCK || state == S_PAUSE) begin
            for (n=0; n<4; n=n+1) begin
                {nox, noy} = get_offset(cur_piece, cur_rot, n[1:0]);
                if ($signed({1'b0, grid_x}) == cur_x + nox && $signed({1'b0, grid_y}) == cur_y + noy) begin
                    is_active_blk = 1;
                end
            end
        end

        if (is_active_blk) begin
            pixel_block_id = cur_piece;
        end else if (grid_x < COLS && grid_y < ROWS) begin
            pixel_block_id = board[grid_y][grid_x];
        end else begin
            pixel_block_id = 0;
        end
    end

endmodule