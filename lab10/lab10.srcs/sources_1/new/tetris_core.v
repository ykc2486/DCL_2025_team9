module tetris_core (
    input  wire       clk,          // 50MHz (from divider)
    input  wire       rst,
    input  wire [3:0] btn,          // {3:Rot, 2:Left, 1:Right, 0:Down/Start}
    input  wire       sw_hold,      // sw[0]: Hold
    input  wire       sw_pause,     // sw[1]: Pause
    input  wire [9:0] grid_x,
    input  wire [9:0] grid_y,
    output reg  [2:0] pixel_block_id,
    output reg  [7:0] score,
    output wire [2:0] next_piece_id,
    output wire [2:0] hold_piece_id,
    output wire [2:0] game_status,  // 0:IDLE, 1:SPAWN, 2:ACTIVE, 3:LOCK, 4:CLEAR, 5:OVER, 6:PAUSE
    output reg  [7:0] level         // [New] 輸出等級
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
    // 假設 clk 是 50MHz (由 Top 的 100MHz 除以 2)
    // 0.1秒 = 50,000,000 * 0.1 = 5,000,000 ticks
    
    localparam TIME_DROP_FAST = 5000000;   // 按下 Down 鍵的速度 (0.1s)
    localparam TIME_BASE      = 25000000;  // 基礎速度 (0.5s)
    localparam TIME_STEP      = 5000000;   // 每階加速 (0.1s)
    localparam TIME_MIN       = 2500000;   // 最快速度限制 (0.05s)

    reg [25:0] current_speed_limit;
    wire [7:0] speed_stage = level / 3; // [關鍵] 每 3 個 Level 為一個加速階段 (整數除法)

    always @(*) begin
        // 公式：速度 = 基礎 - (階段 * 0.1秒)
        // 例如: Lv0~2=0.5s, Lv3~5=0.4s, Lv6~8=0.3s ...
        if ((speed_stage * TIME_STEP) >= (TIME_BASE - TIME_MIN)) begin
            current_speed_limit = TIME_MIN;
        end else begin
            current_speed_limit = TIME_BASE - (speed_stage * TIME_STEP);
        end
    end

    reg [25:0] timer;
    wire [25:0] drop_limit = (~btn[0]) ? TIME_DROP_FAST : current_speed_limit;

    // --- [Line Count] ---
    reg [5:0] lines_cleared_accumulator; // 用來數 0~30 行

    // --- Input Edge Detection ---
    reg [3:0] btn_prev;
    wire [3:0] btn_press = btn & ~btn_prev;
    reg sw_prev;
    wire sw_change = (sw_hold != sw_prev);
    reg pause_sw_prev;
    wire pause_sw_change = (sw_pause != pause_sw_prev);

    // --- FSM Variables ---
    integer check_row, k, i, j, loop_k;
    reg full_row;
    reg signed [3:0] ox, oy;
    reg [7:0] rand_reg;
    wire [2:0] random_val = (rand_reg[2:0] == 0) ? 1 : rand_reg[2:0];
    reg [2:0] tmp_piece;
    reg [31:0] init_timer;

    // --- Geometry Function ---
    function [7:0] get_offset;
        input [2:0] shape; input [1:0] rot; input [1:0] idx;
        reg signed [3:0] dx, dy;
        begin
            dx=0; dy=0;
            case (shape)
                1: case (rot[0]) 0: case(idx) 0:{dx,dy}={-4'sd1,4'sd0}; 1:{dx,dy}={4'sd0,4'sd0}; 2:{dx,dy}={4'sd1,4'sd0}; 3:{dx,dy}={4'sd2,4'sd0}; endcase
                                 1: case(idx) 0:{dx,dy}={4'sd0,-4'sd1}; 1:{dx,dy}={4'sd0,4'sd0}; 2:{dx,dy}={4'sd0,4'sd1}; 3:{dx,dy}={4'sd0,4'sd2}; endcase endcase
                2: case (rot) 0: case(idx) 0:{dx,dy}={-4'sd1,-4'sd1}; 1:{dx,dy}={-4'sd1,4'sd0}; 2:{dx,dy}={4'sd0,4'sd0}; 3:{dx,dy}={4'sd1,4'sd0}; endcase
                              1: case(idx) 0:{dx,dy}={4'sd0,-4'sd1}; 1:{dx,dy}={4'sd1,-4'sd1}; 2:{dx,dy}={4'sd0,4'sd0}; 3:{dx,dy}={4'sd0,4'sd1}; endcase
                              2: case(idx) 0:{dx,dy}={-4'sd1,4'sd0}; 1:{dx,dy}={4'sd0,4'sd0}; 2:{dx,dy}={4'sd1,4'sd0}; 3:{dx,dy}={4'sd1,4'sd1}; endcase
                              3: case(idx) 0:{dx,dy}={4'sd0,-4'sd1}; 1:{dx,dy}={4'sd0,4'sd0}; 2:{dx,dy}={-4'sd1,4'sd1}; 3:{dx,dy}={4'sd0,4'sd1}; endcase endcase
                3: case (rot) 0: case(idx) 0:{dx,dy}={4'sd1,-4'sd1}; 1:{dx,dy}={-4'sd1,4'sd0}; 2:{dx,dy}={4'sd0,4'sd0}; 3:{dx,dy}={4'sd1,4'sd0}; endcase
                              1: case(idx) 0:{dx,dy}={4'sd0,-4'sd1}; 1:{dx,dy}={4'sd0,4'sd0}; 2:{dx,dy}={4'sd0,4'sd1}; 3:{dx,dy}={4'sd1,4'sd1}; endcase
                              2: case(idx) 0:{dx,dy}={-4'sd1,4'sd0}; 1:{dx,dy}={4'sd0,4'sd0}; 2:{dx,dy}={4'sd1,4'sd0}; 3:{dx,dy}={-4'sd1,4'sd1}; endcase
                              3: case(idx) 0:{dx,dy}={-4'sd1,-4'sd1}; 1:{dx,dy}={4'sd0,-4'sd1}; 2:{dx,dy}={4'sd0,4'sd0}; 3:{dx,dy}={4'sd0,4'sd1}; endcase endcase
                4: case (idx) 0:{dx,dy}={4'sd0,4'sd0}; 1:{dx,dy}={4'sd1,4'sd0}; 2:{dx,dy}={4'sd0,4'sd1}; 3:{dx,dy}={4'sd1,4'sd1}; endcase
                5: case (rot[0]) 0: case(idx) 0:{dx,dy}={4'sd0,4'sd0}; 1:{dx,dy}={4'sd1,4'sd0}; 2:{dx,dy}={-4'sd1,4'sd1}; 3:{dx,dy}={4'sd0,4'sd1}; endcase
                                 1: case(idx) 0:{dx,dy}={4'sd0,-4'sd1}; 1:{dx,dy}={4'sd0,4'sd0}; 2:{dx,dy}={4'sd1,4'sd0}; 3:{dx,dy}={4'sd1,4'sd1}; endcase endcase
                6: case (rot) 0: case(idx) 0:{dx,dy}={4'sd0,-4'sd1}; 1:{dx,dy}={-4'sd1,4'sd0}; 2:{dx,dy}={4'sd0,4'sd0}; 3:{dx,dy}={4'sd1,4'sd0}; endcase
                              1: case(idx) 0:{dx,dy}={4'sd0,-4'sd1}; 1:{dx,dy}={4'sd0,4'sd0}; 2:{dx,dy}={4'sd1,4'sd0}; 3:{dx,dy}={4'sd0,4'sd1}; endcase
                              2: case(idx) 0:{dx,dy}={-4'sd1,4'sd0}; 1:{dx,dy}={4'sd0,4'sd0}; 2:{dx,dy}={4'sd1,4'sd0}; 3:{dx,dy}={4'sd0,4'sd1}; endcase
                              3: case(idx) 0:{dx,dy}={4'sd0,-4'sd1}; 1:{dx,dy}={-4'sd1,4'sd0}; 2:{dx,dy}={4'sd0,4'sd0}; 3:{dx,dy}={4'sd0,4'sd1}; endcase endcase
                7: case (rot[0]) 0: case(idx) 0:{dx,dy}={-4'sd1,4'sd0}; 1:{dx,dy}={4'sd0,4'sd0}; 2:{dx,dy}={4'sd0,4'sd1}; 3:{dx,dy}={4'sd1,4'sd1}; endcase
                                 1: case(idx) 0:{dx,dy}={4'sd1,-4'sd1}; 1:{dx,dy}={4'sd0,4'sd0}; 2:{dx,dy}={4'sd1,4'sd0}; 3:{dx,dy}={4'sd0,4'sd1}; endcase endcase
                default: {dx, dy} = {4'sd0, 4'sd0};
            endcase
            get_offset = {dx, dy};
        end
    endfunction

    // --- Collision ---
    reg col_res;
    integer m;
    reg signed [3:0] tox, toy;
    reg [3:0] tmp_score;
    task check_collision;
        input integer tx, ty; input [1:0] tr;
        begin
            col_res = 0;
            for (m = 0; m < 4; m = m + 1) begin
                {tox, toy} = get_offset(cur_piece, tr, m[1:0]);
                if (tx + tox < 0 || tx + tox >= COLS || ty + toy >= ROWS) col_res = 1;
                else if (ty + toy >= 0 && board[ty + toy][tx + tox] != 0) col_res = 1;
            end
        end
    endtask

    // --- FSM ---
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            score <= 0;
            timer <= 0;
            level <= 0;
            lines_cleared_accumulator <= 0;
            rand_reg <= 8'hA5;
            next_piece_reg <= 1;
            hold_piece <= 0;
            hold_used <= 0;
            init_timer <= 0;
            cur_x <= 0; cur_y <= 0; cur_piece <= 1; cur_rot <= 0;
            for (i=0; i<ROWS; i=i+1) for (j=0; j<COLS; j=j+1) board[i][j] <= 0;
            btn_prev <= btn; sw_prev <= sw_hold; pause_sw_prev <= sw_pause;
        end else begin
            btn_prev <= btn; sw_prev <= sw_hold; pause_sw_prev <= sw_pause;
            rand_reg <= {rand_reg[6:0], rand_reg[7] ^ rand_reg[5]};

            case (state)
                S_IDLE: begin
                    if (init_timer < 100000000) init_timer <= init_timer + 1;
                    else begin
                        rand_reg <= rand_reg + 1; // 增加亂數種子變異
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
                    check_collision(4, 1, 0);
                    if (col_res) state <= S_GAMEOVER;
                    else begin state <= S_ACTIVE; timer <= 0; end
                end

                S_ACTIVE: begin
                    if (pause_sw_change && sw_pause) state <= S_PAUSE;
                    else begin
                        if (timer < drop_limit) timer <= timer + 1;

                        if (sw_change && !hold_used) begin
                            hold_used <= 1; timer <= 0; cur_x <= 4; cur_y <= 1; cur_rot <= 0;
                            if (hold_piece == 0) begin hold_piece <= cur_piece; cur_piece <= next_piece_reg; next_piece_reg <= random_val; end
                            else begin tmp_piece = cur_piece; cur_piece <= hold_piece; hold_piece <= tmp_piece; end
                        end

                        if (btn_press[3]) begin
                            check_collision(cur_x, cur_y, cur_rot + 1);
                            if (!col_res) cur_rot <= cur_rot + 1;
                            else begin
                                check_collision(cur_x+1, cur_y, cur_rot+1);
                                if (!col_res) begin cur_rot <= cur_rot+1; cur_x <= cur_x+1; end
                                else begin
                                    check_collision(cur_x-1, cur_y, cur_rot+1);
                                    if (!col_res) begin cur_rot <= cur_rot+1; cur_x <= cur_x-1; end
                                    else begin
                                        check_collision(cur_x, cur_y-1, cur_rot+1);
                                        if (!col_res) begin cur_rot <= cur_rot+1; cur_y <= cur_y-1; end
                                    end
                                end
                            end
                        end

                        if (btn_press[2]) begin check_collision(cur_x-1, cur_y, cur_rot); if (!col_res) cur_x <= cur_x-1; end
                        if (btn_press[1]) begin check_collision(cur_x+1, cur_y, cur_rot); if (!col_res) cur_x <= cur_x+1; end

                        if (timer >= drop_limit) begin
                            timer <= 0;
                            check_collision(cur_x, cur_y+1, cur_rot);
                            if (!col_res) cur_y <= cur_y + 1;
                            else state <= S_LOCK;
                        end
                    end
                end

                S_PAUSE: if (pause_sw_change && !sw_pause) state <= S_ACTIVE;

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
                    if (check_row < 0) state <= S_SPAWN;
                    else begin
                        full_row = 1;
                        for (j=0; j<COLS; j=j+1) if (board[check_row][j] == 0) full_row = 0;

                        if (full_row) begin
                            // [Level Control] 每30行升一級
                            if (lines_cleared_accumulator >= 5) begin
                                lines_cleared_accumulator <= 0;
                                level <= level + 1;
                            end else begin
                                lines_cleared_accumulator <= lines_cleared_accumulator + 1;
                            end

                            if (tmp_score == 0) tmp_score <= 1;
                            else if (tmp_score == 1) tmp_score <= 3;
                            else if (tmp_score == 3) tmp_score <= 5;
                            else tmp_score <= 8;

                            for (loop_k = ROWS-1; loop_k > 0; loop_k = loop_k - 1)
                                if (loop_k <= check_row)
                                    for (j=0; j<COLS; j=j+1) board[loop_k][j] <= board[loop_k-1][j];
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

                S_GAMEOVER: if (btn_press[1]) state <= S_IDLE;
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
                if ($signed({1'b0, grid_x}) == cur_x + nox && $signed({1'b0, grid_y}) == cur_y + noy)
                    is_active_blk = 1;
            end
        end
        if (is_active_blk) pixel_block_id = cur_piece;
        else if (grid_x < COLS && grid_y < ROWS) pixel_block_id = board[grid_y][grid_x];
        else pixel_block_id = 0;
    end
endmodule