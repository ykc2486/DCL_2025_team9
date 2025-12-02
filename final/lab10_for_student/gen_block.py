# gen_tech_blocks.py
import os
from PIL import Image, ImageDraw

# 輔助函式：計算較暗的顏色
def get_darker(color, factor=3):
    return (color[0] // factor, color[1] // factor, color[2] // factor)

def create_tech_tetris_assets():
    # --- 設定參數 ---
    BLOCK_SIZE = 20
    NUM_BLOCKS = 8 # 0=空, 1-7=七種顏色
    WIDTH = BLOCK_SIZE
    HEIGHT = BLOCK_SIZE * NUM_BLOCKS
    
    # 輸出檔名
    OUTPUT_IMG = "blocks.png"
    OUTPUT_MEM = "blocks.mem"

    # --- 定義霓虹顏色 (R, G, B) - 挑選高飽和度、高亮度的顏色 ---
    neon_colors = [
        (0, 0, 0),         # 0: Empty (黑)
        (0, 255, 255),     # 1: I (青霓虹) - 最接近背景風格
        (60, 100, 255),    # 2: J (藍霓虹)
        (255, 180, 50),    # 3: L (橘霓虹)
        (255, 255, 0),     # 4: O (黃霓虹)
        (50, 255, 50),     # 5: S (綠霓虹)
        (220, 50, 255),    # 6: T (紫霓虹)
        (255, 50, 50)      # 7: Z (紅霓虹)
    ]

    # --- 繪圖 ---
    # 背景設為全黑
    img = Image.new("RGB", (WIDTH, HEIGHT), "black")
    draw = ImageDraw.Draw(img)

    print(f"正在建立科技風格材質圖 {WIDTH}x{HEIGHT}...")

    for i in range(NUM_BLOCKS):
        base_y = i * BLOCK_SIZE
        main_color = neon_colors[i]

        if i == 0: continue # 跳過黑色背景

        # 計算不同亮度的顏色
        dark_core = get_darker(main_color, factor=5)   # 最暗的核心
        mid_grid = get_darker(main_color, factor=2)    # 中間亮度的網格線

        # --- 開始繪製單個 20x20 方塊 ---

        # 1. 填充深色核心背景
        draw.rectangle(
            [1, base_y + 1, BLOCK_SIZE - 2, base_y + BLOCK_SIZE - 2], 
            fill=dark_core
        )

        # 2. 繪製內部科技網格 (Tech Grid) - 營造電路感
        # 畫十字線
        center = BLOCK_SIZE // 2
        draw.line([(center, base_y + 2), (center, base_y + BLOCK_SIZE - 3)], fill=mid_grid, width=1)
        draw.line([(2, base_y + center), (BLOCK_SIZE - 3, base_y + center)], fill=mid_grid, width=1)
        # 畫內圈細線
        draw.rectangle(
            [5, base_y + 5, BLOCK_SIZE - 6, base_y + BLOCK_SIZE - 6], 
            outline=mid_grid, width=1
        )

        # 3. 繪製高亮霓虹邊框 (外發光效果)
        # 最外圈 (極亮)
        draw.rectangle(
            [0, base_y, BLOCK_SIZE - 1, base_y + BLOCK_SIZE - 1], 
            outline=main_color, width=1
        )
        # 次外圈 (稍微柔和，製造發光暈開的感覺)
        draw.rectangle(
            [1, base_y + 1, BLOCK_SIZE - 2, base_y + BLOCK_SIZE - 2], 
            outline=mid_grid, width=1
        )
        # 強調四個角落的亮點
        draw.point([(0, base_y), (BLOCK_SIZE-1, base_y), (0, base_y+BLOCK_SIZE-1), (BLOCK_SIZE-1, base_y+BLOCK_SIZE-1)], fill=(255,255,255))


    # 存圖片 (預覽用)
    img.save(OUTPUT_IMG)
    print(f"--> 已生成預覽圖片: {OUTPUT_IMG} (請打開檢查效果)")

    # --- 轉檔為 Verilog .mem (12-bit Hex) ---
    print(f"正在轉換為 {OUTPUT_MEM}...")
    
    with open(OUTPUT_MEM, 'w') as f:
        for y in range(HEIGHT):
            for x in range(WIDTH):
                r, g, b = img.getpixel((x, y))
                # 壓縮為 12-bit (RGB444)
                r4 = r >> 4
                g4 = g >> 4
                b4 = b >> 4
                val = (r4 << 8) | (g4 << 4) | b4
                f.write(f"{val:03x}\n")

    print(f"--> 已生成 MEM: {OUTPUT_MEM}")
    print("完成！新的科技風格方塊已準備就緒。")

if __name__ == "__main__":
    create_tech_tetris_assets()