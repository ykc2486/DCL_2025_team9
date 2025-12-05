module tetris_core (
    input wire clk, rst,
    input wire [3:0] btn, // {3:Rot, 2:Left, 1:Right, 0:Down}
    input wire sw_hold,   // 來自 sw[0]
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
    reg [2:0] state; // 0:Spawn, 1:Active, 2:Lock, 3:Clear
    
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

    // --- Geometry (函數保持不變) ---
    function [7:0] get_offset;
        input [2:0] shape; 
        input [1:0] rot; 
        input [1:0] idx; 
        reg signed [3:0] dx, dy;
        begin
            dx = 4'sd0; dy = 4'sd0;
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

    // --- Collision Task (保持不變) ---
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
    integer i, j, k, cleared_count;
    integer dst_row; 
    reg signed [3:0] ox, oy;
    reg full_row;
    
    reg [7:0] rand_reg;
    wire [2:0] random_val = (rand_reg[2:0] == 0) ? 1 : rand_reg[2:0];
    reg [2:0] tmp_piece;

    always @(posedge clk) begin
        if (rst) begin
            state <= 0;
            score <= 0;
            timer <= 0;
            rand_reg <= 8'hA5;
            
            // [恢復] Reset 時 Hold 為空
            hold_piece <= 0; 
            hold_used <= 0;

            next_piece_reg <= 1; 
            cur_x <= 0; cur_y <= 0; cur_piece <= 1; cur_rot <= 0;
            for(i=0; i<ROWS; i=i+1) for(j=0; j<COLS; j=j+1) board[i][j] <= 0;
        end else begin
            rand_reg <= {rand_reg[6:0], rand_reg[7] ^ rand_reg[5]};
            
            if (state == 1 && timer < drop_limit) timer <= timer + 1;

            case(state)
                0: begin // SPAWN
                    cur_piece <= next_piece_reg;
                    next_piece_reg <= random_val;
                    cur_x <= 4; cur_y <= 1; cur_rot <= 0;
                    hold_used <= 0; // 重置 Hold 次數
                    
                    check_collision(4, 1, 0); 
                    if (col_res) begin 
                        for(i=0; i<ROWS; i=i+1) for(j=0; j<COLS; j=j+1) board[i][j] <= 0;
                        score <= 0;
                        hold_piece <= 0; // Game Over 時也清空 Hold
                    end
                    state <= 1; timer <= 0;
                end

                1: begin // ACTIVE
                    if (sw_change && !hold_used) begin
                        hold_used <= 1; 
                        timer <= 0; 
                        
                        // [修改] 交換後重置位置與旋轉
                        cur_x <= 4; 
                        cur_y <= 1; 
                        cur_rot <= 0; 

                        if (hold_piece == 0) begin
                            // 第一次 Hold：存入當前，生成新的
                            hold_piece <= cur_piece;
                            cur_piece <= next_piece_reg;
                            next_piece_reg <= random_val;
                        end else begin
                            // 有 Hold：交換
                            tmp_piece = cur_piece;
                            cur_piece <= hold_piece;
                            hold_piece <= tmp_piece;
                        end
                    end

                    // 按鈕處理 (保持不變)
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
                        else state <= 2; 
                    end
                end

                2: begin // LOCK
                    for (k=0; k<4; k=k+1) begin
                        {ox, oy} = get_offset(cur_piece, cur_rot, k[1:0]);
                        if ((cur_y + oy) >= 0 && (cur_y + oy) < ROWS && 
                            (cur_x + ox) >= 0 && (cur_x + ox) < COLS) begin
                            board[cur_y + oy][cur_x + ox] <= cur_piece;
                        end
                    end
                    state <= 3;
                end

                3: begin // CLEAR
                    cleared_count = 0;
                    for (i=0; i<ROWS; i=i+1) begin
                        full_row = 1;
                        for (j=0; j<COLS; j=j+1) if (board[i][j] == 0) full_row = 0;
                        if (full_row) cleared_count = cleared_count + 1;
                    end
                    if (cleared_count > 0) begin
                        score <= score + cleared_count;
                        dst_row = ROWS - 1; 
                        for (i=ROWS-1; i>=0; i=i-1) begin
                            full_row = 1;
                            for (j=0; j<COLS; j=j+1) if (board[i][j] == 0) full_row = 0;
                            if (!full_row) begin
                                for (j=0; j<COLS; j=j+1) board[dst_row][j] <= board[i][j]; 
                                dst_row = dst_row - 1; 
                            end
                        end
                        for (i=0; i<ROWS; i=i+1) begin
                            if (i <= dst_row) for (j=0; j<COLS; j=j+1) board[i][j] <= 0; 
                        end
                    end 
                    state <= 0; 
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
        if (state == 1 || state == 2) begin
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