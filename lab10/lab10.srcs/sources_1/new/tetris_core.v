module tetris_core (
    input wire clk, rst,
    input wire [3:0] btn, 
    input wire [9:0] grid_x, grid_y, // 來自 Top 的安全座標
    output reg [2:0] pixel_block_id, 
    output reg [7:0] score
);

    parameter COLS = 10;
    parameter ROWS = 20;

    reg [2:0] board [19:0][9:0]; 
    reg [2:0] cur_piece; 
    reg [1:0] cur_rot;   
    integer cur_x, cur_y;
    
    localparam TIME_DROP_FAST = 5000000; 
    localparam TIME_DROP_SLOW = 25000000; 
    
    reg [25:0] timer;
    reg [2:0] state; // 0:Spawn, 1:Active, 2:Lock, 3:Clear
    
    reg [3:0] btn_prev;
    wire [3:0] btn_press = btn & ~btn_prev;
    always @(posedge clk) btn_prev <= btn;

    wire [25:0] drop_limit = (~btn[0]) ? TIME_DROP_FAST : TIME_DROP_SLOW;

    // --- 1. Geometry (保持不變) ---
    function [7:0] get_offset;
        input [2:0] p; input [1:0] r; input [1:0] idx;
        reg signed [3:0] dx, dy;
        begin
            // Inputs: p, idx, r[0] (assuming r is an array or vector, and we are only checking the first element)
            // Inputs: p, idx, r[0]
            // Outputs: dx, dy (which are combined into get_offset)
            
            dx = 0;
            dy = 0;
            
            case (p) // Main case based on input 'p'
                // --- Case 1 ---
                1: begin
                    if (!r[0]) begin // r[0] is false (0)
                        case (idx)
                            0: begin dx = -1; end // Added begin/end
                            1: begin dx = 0; end
                            2: begin dx = 1; end
                            3: begin dx = 2; end
                        endcase
                    end else begin // r[0] is true (1)
                        case (idx)
                            0: begin dy = -1; end
                            1: begin dy = 0; end
                            2: begin dy = 1; end
                            3: begin dy = 2; end
                        endcase
                    end
                end
            
                // --- Case 2 ---
                2: begin
                    case (r)
                        0: begin
                            case (idx)
                                0: begin dx = -1; dy = -1; end // Multiple statements always need begin/end
                                1: begin dx = -1; dy = 0; end
                                2: begin dx = 0; dy = 0; end
                                3: begin dx = 1; dy = 0; end
                            endcase
                        end
                        1: begin
                            case (idx)
                                0: begin dx = 1; dy = -1; end // Compound single statement, wrapped for safety
                                1: begin dy = -1; end
                                2: begin dy = 0; end
                                3: begin dy = 1; end
                            endcase
                        end
                        2: begin
                            case (idx)
                                0: begin dx = 1; dy = 1; end
                                1: begin dx = 1; end
                                2: begin dx = 0; end
                                3: begin dx = -1; end
                            endcase
                        end
                        3: begin
                            case (idx)
                                0: begin dx = -1; dy = 1; end
                                1: begin dy = 1; end
                                2: begin dy = 0; end
                                3: begin dy = -1; end
                            endcase
                        end
                    endcase
                end
            
                // --- Case 3 ---
                3: begin
                    case (r)
                        0: begin
                            case (idx)
                                0: begin dx = 1; dy = -1; end
                                1: begin dx = -1; end
                                2: begin dx = 0; end
                                3: begin dx = 1; end
                            endcase
                        end
                        1: begin
                            case (idx)
                                0: begin dx = 1; dy = 1; end
                                1: begin dy = -1; end
                                2: begin dy = 0; end
                                3: begin dy = 1; end
                            endcase
                        end
                        2: begin
                            case (idx)
                                0: begin dx = -1; dy = 1; end
                                1: begin dx = 1; end
                                2: begin dx = 0; end
                                3: begin dx = -1; end
                            endcase
                        end
                        3: begin
                            case (idx)
                                0: begin dx = -1; dy = -1; end
                                1: begin dy = 1; end
                                2: begin dy = 0; end
                                3: begin dy = -1; end
                            endcase
                        end
                    endcase
                end
            
                // --- Case 4 ---
                4: begin
                    case (idx)
                        1: begin dx = 1; end
                        2: begin dy = 1; end
                        3: begin dx = 1; dy = 1; end
                    endcase
                end
            
                // --- Case 5 ---
                5: begin
                    if (!r[0]) begin
                        case (idx)
                            0: begin dx = -1; dy = 1; end
                            1: begin dy = 1; end
                            2: begin dx = 0; end
                            3: begin dx = 1; end
                        endcase
                    end else begin
                        case (idx)
                            0: begin dx = -1; dy = -1; end
                            1: begin dx = -1; end
                            2: begin dx = 0; end
                            3: begin dy = 1; end
                        endcase
                    end
                end
            
                // --- Case 6 ---
                6: begin
                    case (r)
                        0: begin
                            case (idx)
                                0: begin dy = -1; end
                                1: begin dx = -1; end
                                2: begin dx = 0; end
                                3: begin dx = 1; end
                            endcase
                        end
                        1: begin
                            case (idx)
                                0: begin dx = 1; end
                                1: begin dy = -1; end
                                2: begin dy = 0; end
                                3: begin dy = 1; end
                            endcase
                        end
                        2: begin
                            case (idx)
                                0: begin dy = 1; end
                                1: begin dx = 1; end
                                2: begin dx = 0; end
                                3: begin dx = -1; end
                            endcase
                        end
                        3: begin
                            case (idx)
                                0: begin dx = -1; end
                                1: begin dy = 1; end
                                2: begin dy = 0; end
                                3: begin dy = -1; end
                            endcase
                        end
                    endcase
                end
            
                // --- Case 7 ---
                7: begin
                    if (!r[0]) begin
                        case (idx)
                            0: begin dx = -1; end
                            1: begin dx = 0; end
                            2: begin dy = 1; end
                            3: begin dx = 1; dy = 1; end
                        endcase
                    end else begin
                        case (idx)
                            0: begin dx = 1; dy = -1; end
                            1: begin dx = 1; end
                            2: begin dx = 0; end
                            3: begin dy = 1; end
                        endcase
                    end
                end
            
                // --- Default Case ---
                default: begin
                    {dx, dy} = {4'd0, 4'd0};
                end
            endcase
            
            get_offset = {dx, dy};

        end
    endfunction

    // --- 2. Collision (保持不變) ---
    reg col_res;
    integer m;
    reg signed [3:0] tox, toy;
    task check_collision;
        input integer tx, ty; input [1:0] tr;
        begin
            col_res = 0;
            for(m=0; m<4; m=m+1) begin
                {tox, toy} = get_offset(cur_piece, tr, m[1:0]);
                if (tx + tox < 0 || tx + tox >= COLS || ty + toy >= ROWS) col_res = 1;
                else if (ty + toy >= 0 && board[ty+toy][tx+tox] > 0) col_res = 1;
            end
        end
    endtask

    // --- 3. FSM (保持不變) ---
    integer i, j, k;
    reg signed [3:0] ox, oy;
    reg full_row;
    reg [7:0] rand_reg;
    wire [2:0] next_piece = (rand_reg[2:0] == 0) ? 1 : rand_reg[2:0];
    
    always @(posedge clk) begin
        if (rst) begin
            state <= 0; score <= 0; timer <= 0; rand_reg <= 8'hA5;
            for(i=0; i<ROWS; i=i+1) for(j=0; j<COLS; j=j+1) board[i][j] <= 0;
        end else begin
            rand_reg <= {rand_reg[6:0], rand_reg[7] ^ rand_reg[5]};
            if (state == 1 && timer < drop_limit) timer <= timer + 1;

            case(state)
                0: begin 
                    cur_piece <= next_piece; cur_x <= 4; cur_y <= 1; cur_rot <= 0;
                    check_collision(4, 1, 0); 
                    if (col_res) begin
                        for(i = 0; i < ROWS; i=i+1) for(j = 0; j < COLS; j=j+1) board[i][j] <= 0;
                        score <= 0;
                    end 
                    state <= 1; timer <= 0;
                end
                1: begin 
                    if (btn_press[3]) begin
                        check_collision(cur_x, cur_y, cur_rot+1);
                        if (!col_res) cur_rot <= cur_rot + 1;
                    end
                    if (btn_press[1]) begin
                        check_collision(cur_x+1, cur_y, cur_rot);
                        if (!col_res) cur_x <= cur_x + 1;
                    end
                    if (btn_press[2]) begin
                        check_collision(cur_x-1, cur_y, cur_rot);
                        if (!col_res) cur_x <= cur_x - 1;
                    end
                    if (timer >= drop_limit) begin 
                        timer <= 0;
                        check_collision(cur_x, cur_y+1, cur_rot);
                        if (!col_res) cur_y <= cur_y + 1;
                        else state <= 2; 
                    end
                end
                2: begin 
                    for (k=0; k<4; k=k+1) begin
                        {ox, oy} = get_offset(cur_piece, cur_rot, k[1:0]);
                        if ((cur_y+oy) >= 0 && (cur_y+oy) < ROWS && 
                            (cur_x+ox) >= 0 && (cur_x+ox) < COLS) begin
                            board[cur_y+oy][cur_x+ox] <= cur_piece;
                        end
                    end
                    state <= 3;
                end
                3: begin 
                    for (i=0; i<ROWS; i=i+1) begin
                        full_row = 1;
                        for (j=0; j<COLS; j=j+1) if (board[i][j] == 0) full_row = 0;
                        if (full_row) begin
                            score <= score + 1;
                            for (k=i; k>0; k=k-1) for (j=0; j<COLS; j=j+1) board[k][j] <= board[k-1][j];
                            for (j=0; j<COLS; j=j+1) board[0][j] <= 0;
                        end
                    end
                    state <= 0; 
                end
            endcase
        end
    end

    // --- 4. Rendering (Safe Comparison) ---
    reg is_active_blk;
    integer n;
    reg signed [3:0] nox, noy;

    always @(*) begin
        pixel_block_id = 0;
        is_active_blk = 0;
        
        if (state == 1 || state == 2) begin
            for (n=0; n<4; n=n+1) begin
                {nox, noy} = get_offset(cur_piece, cur_rot, n[1:0]);
                // [關鍵修正] 使用 $signed() 確保比較時是使用有號數邏輯
                // 這樣當 cur_x + nox 為負數時，不會被誤判為巨大的正數
                if ($signed({1'b0, grid_x}) == cur_x + nox && 
                    $signed({1'b0, grid_y}) == cur_y + noy) 
                    is_active_blk = 1;
            end
        end
        
        if (is_active_blk) begin
            pixel_block_id = cur_piece;
        end else begin
            // 因為 Top 層已經保證 grid_x/y 在 0-9/0-19 範圍內，這裡直接讀取
            pixel_block_id = board[grid_y][grid_x]; 
        end
    end

endmodule