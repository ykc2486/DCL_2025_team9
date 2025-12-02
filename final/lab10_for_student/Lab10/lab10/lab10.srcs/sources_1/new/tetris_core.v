module tetris_core (
    input wire clk, rst,
    input wire [3:0] btn, 
    input wire [9:0] pixel_x, pixel_y,
    output reg [2:0] pixel_block_id, 
    output reg [7:0] score
);

    parameter COLS = 10;
    parameter ROWS = 20;
    parameter BLK = 20;
    parameter OFF_X = 220; 
    parameter OFF_Y = 40;  

    reg [2:0] board [19:0][9:0]; 
    reg [2:0] cur_piece; 
    reg [1:0] cur_rot;   
    integer cur_x, cur_y;
    
    reg [25:0] timer;
    reg [2:0] state; // 0:Spawn, 1:Active, 2:Lock, 3:Clear
    
    reg [3:0] btn_prev;
    wire [3:0] btn_press = btn & ~btn_prev;
    always @(posedge clk) btn_prev <= btn;

    // --- 1. Geometry ---
    function [7:0] get_offset;
        input [2:0] p; input [1:0] r; input [1:0] idx;
        reg signed [3:0] dx, dy;
        begin
            dx=0; dy=0;
            case(p)
                1: if(!r[0]) case(idx) 0:dx=-1; 1:dx=0; 2:dx=1; 3:dx=2; endcase 
                   else      case(idx) 0:dy=-1; 1:dy=0; 2:dy=1; 3:dy=2; endcase
                2: case(r) 0:begin case(idx) 0:{dx,dy}={-1,-1}; 1:dx=-1; 2:dx=0; 3:dx=1; endcase end 
                           1:begin case(idx) 0:{dx,dy}={1,-1};  1:dy=-1; 2:dy=0; 3:dy=1; endcase end
                           2:begin case(idx) 0:{dx,dy}={1,1};   1:dx=1;  2:dx=0; 3:dx=-1; endcase end
                           3:begin case(idx) 0:{dx,dy}={-1,1};  1:dy=1;  2:dy=0; 3:dy=-1; endcase end endcase
                3: case(r) 0:begin case(idx) 0:{dx,dy}={1,-1};  1:dx=-1; 2:dx=0; 3:dx=1; endcase end 
                           1:begin case(idx) 0:{dx,dy}={1,1};   1:dy=-1; 2:dy=0; 3:dy=1; endcase end
                           2:begin case(idx) 0:{dx,dy}={-1,1};  1:dx=1;  2:dx=0; 3:dx=-1; endcase end
                           3:begin case(idx) 0:{dx,dy}={-1,-1}; 1:dy=1;  2:dy=0; 3:dy=-1; endcase end endcase
                4: case(idx) 1:dx=1; 2:dy=1; 3:{dx,dy}={1,1}; endcase 
                5: if(!r[0]) case(idx) 0:{dx,dy}={-1,1}; 1:dy=1; 2:dx=0; 3:dx=1; endcase 
                   else      case(idx) 0:{dx,dy}={-1,-1}; 1:dx=-1; 2:dx=0; 3:dy=1; endcase
                6: case(r) 0: case(idx) 0:dy=-1; 1:dx=-1; 2:dx=0; 3:dx=1; endcase 
                           1: case(idx) 0:dx=1;  1:dy=-1; 2:dy=0; 3:dy=1; endcase
                           2: case(idx) 0:dy=1;  1:dx=1;  2:dx=0; 3:dx=-1; endcase
                           3: case(idx) 0:dx=-1; 1:dy=1;  2:dy=0; 3:dy=-1; endcase endcase
                7: if(!r[0]) case(idx) 0:dx=-1; 1:dx=0; 2:dy=1; 3:{dx,dy}={1,1}; endcase 
                   else      case(idx) 0:{dx,dy}={1,-1}; 1:dx=1; 2:dx=0; 3:dy=1; endcase
                default: {dx, dy} = {4'd0, 4'd0};
            endcase
            get_offset = {dx, dy};
        end
    endfunction

    // --- 2. Collision ---
    reg col_res;
    integer m;
    reg signed [3:0] tox, toy;
    
    task check_collision;
        input integer tx, ty; input [1:0] tr;
        begin
            col_res = 0;
            for(m=0; m<4; m=m+1) begin
                {tox, toy} = get_offset(cur_piece, tr, m[1:0]);
                if (tx+tox < 0 || tx+tox >= COLS || ty+toy >= ROWS) col_res = 1;
                else if (ty+toy >= 0 && board[ty+toy][tx+tox] > 0) col_res = 1;
            end
        end
    endtask

    // --- 3. FSM ---
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
            if (state == 1) begin
                 if (btn[0]) timer <= 25000000; 
                 else timer <= timer + 1;
            end

            case(state)
                0: begin // SPAWN
                    cur_piece <= next_piece; cur_x <= 4; cur_y <= 1; cur_rot <= 0;
                    check_collision(4, 1, 0); 
                    if (col_res) begin
                        for(i=0; i<ROWS; i=i+1) for(j=0; j<COLS; j=j+1) board[i][j] <= 0;
                        score <= 0;
                    end 
                    state <= 1; timer <= 0;
                end
                1: begin // ACTIVE
                    if (btn_press[3]) begin
                        check_collision(cur_x, cur_y, cur_rot+1);
                        if (!col_res) cur_rot <= cur_rot + 1;
                    end
                    if (btn_press[2]) begin
                        check_collision(cur_x+1, cur_y, cur_rot);
                        if (!col_res) cur_x <= cur_x + 1;
                    end
                    if (btn_press[1]) begin
                        check_collision(cur_x-1, cur_y, cur_rot);
                        if (!col_res) cur_x <= cur_x - 1;
                    end
                    if (timer >= 25000000) begin 
                        timer <= 0;
                        check_collision(cur_x, cur_y+1, cur_rot);
                        if (!col_res) cur_y <= cur_y + 1;
                        else state <= 2; 
                    end
                end
                2: begin // LOCK
                    for (k=0; k<4; k=k+1) begin
                        {ox, oy} = get_offset(cur_piece, cur_rot, k[1:0]);
                        // 嚴格檢查邊界，防止寫入錯誤或覆蓋 index 0
                        if ((cur_y+oy) >= 0 && (cur_y+oy) < ROWS && 
                            (cur_x+ox) >= 0 && (cur_x+ox) < COLS) begin
                            board[cur_y+oy][cur_x+ox] <= cur_piece;
                        end
                    end
                    state <= 3;
                end
                3: begin // CLEAR
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

    // --- 4. Rendering (Safe Coordinate Calculation) ---
    // 先檢查是否在區域內，如果是，才計算 grid index，否則給 0
    // 這避免了 pixel_x < OFF_X 時產生巨大的 unsigned 數字導致越界讀取
    wire in_area = (pixel_x >= OFF_X && pixel_x < OFF_X + COLS*BLK &&
                    pixel_y >= OFF_Y && pixel_y < OFF_Y + ROWS*BLK);
                    
    wire [9:0] gx = in_area ? (pixel_x - OFF_X) / BLK : 0;
    wire [9:0] gy = in_area ? (pixel_y - OFF_Y) / BLK : 0;
    
    reg is_active_blk;
    integer n;
    reg signed [3:0] nox, noy;

    always @(*) begin
        pixel_block_id = 0;
        is_active_blk = 0;
        
        if (in_area) begin
            // Check Active
            if (state == 1 || state == 2) begin
                for (n=0; n<4; n=n+1) begin
                    {nox, noy} = get_offset(cur_piece, cur_rot, n[1:0]);
                    if (gx == cur_x + nox && gy == cur_y + noy) is_active_blk = 1;
                end
            end
            
            if (is_active_blk) pixel_block_id = cur_piece;
            else pixel_block_id = board[gy][gx]; // 安全讀取
        end
    end

endmodule