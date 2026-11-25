library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sprite_reward_pkg.all;

-- ============================================================================
-- Module 5: Real-Time VGA Pixel Renderer (640x480)
--   * Left 480x480 Square Map:
--       - Pixel-art grass tiles & dashed No-Spawn Safe Zone boundary (140..340)
--       - Player 1 Semi-Transparent Circular Attack Range (Radius = 48 px)
--       - Central Crypto Coin Pile (32x32), 8 Mole Sprites + Thin 3px HP Bars,
--         Human+Hammer Sprite, Red Aim Crosshair (+)
--   * Right 160x480 Status Sidebar (X: 480..639):
--       - Stage Indicator (STAGE 1/3..3/3), Remaining Coins, Remaining Time,
--         Combo & Unlock Stage (LV0..LV3), Match Status Box
--   * End-of-Round Winner Reward Overlay:
--       - Displays 50 MMC Reward Cloudflare Links (/r/1 ~ /r/5) & 16-Hex Claim Codes
-- ============================================================================
entity vga_renderer_unit is
    port (
        video_on      : in  std_logic;
        pixel_x       : in  integer range 0 to 799;
        pixel_y       : in  integer range 0 to 524;
        cursor_x      : in  integer range 0 to 479;
        cursor_y      : in  integer range 0 to 479;
        player_x      : in  integer range 0 to 479;
        player_y      : in  integer range 0 to 479;
        attack_anim   : in  integer range 0 to 15;
        moles         : in  mole_array_t;
        coin_count    : in  integer range 0 to 50;
        time_left_sec : in  integer range 0 to 30;
        round_num     : in  integer range 1 to 3;
        combo_cnt     : in  integer range 0 to 255;
        intro_sec     : in  integer range 0 to 10;
        game_state    : in  integer range 0 to 2;
        vga_r         : out std_logic_vector(9 downto 0);
        vga_g         : out std_logic_vector(9 downto 0);
        vga_b         : out std_logic_vector(9 downto 0)
    );
end entity vga_renderer_unit;

architecture behavioral of vga_renderer_unit is

    -- Helper Function: Convert single digit (0..9) to ASCII character
    function digit_char(d : integer) return character is
    begin
        case d is
            when 0 => return '0';
            when 1 => return '1';
            when 2 => return '2';
            when 3 => return '3';
            when 4 => return '4';
            when 5 => return '5';
            when 6 => return '6';
            when 7 => return '7';
            when 8 => return '8';
            when 9 => return '9';
            when others => return '0';
        end case;
    end function;

    -- Helper Procedure 1: Convert 8-bit RGB (0..255) to 10-bit DE2 VGA DAC values
    procedure set_rgb(
        constant r8, g8, b8    : in  integer;
        variable r10, g10, b10 : out std_logic_vector(9 downto 0)
    ) is
    begin
        r10 := std_logic_vector(to_unsigned(r8 * 4, 10));
        g10 := std_logic_vector(to_unsigned(g8 * 4, 10));
        b10 := std_logic_vector(to_unsigned(b8 * 4, 10));
    end procedure;

    -- Helper Procedure 2: Decode Sprite Palette Character into RGB Color
    -- (If ch = '.', it is transparent and leaves the background color untouched)
    procedure draw_sprite_pixel(
        constant ch            : in    character;
        constant flash         : in    boolean;
        variable r10, g10, b10 : inout std_logic_vector(9 downto 0)
    ) is
    begin
        case ch is
            when 'B' => -- Diglett Brown Body (Flashes gold when mining)
                if flash then set_rgb(255, 220, 80, r10, g10, b10);
                else          set_rgb(185, 115, 55, r10, g10, b10); end if;
            when 'D' => set_rgb(110, 65,  30,  r10, g10, b10); -- Dark Brown / Shading
            when 'W' => set_rgb(250, 250, 250, r10, g10, b10); -- White Eye / Handle
            when 'K' => set_rgb(20,  20,  20,  r10, g10, b10); -- Black Pupil / Boots
            when 'P' => set_rgb(255, 130, 170, r10, g10, b10); -- Pink Nose
            when 'E' => set_rgb(140, 105, 65,  r10, g10, b10); -- Earth Dirt Mound
            when 'S' => set_rgb(210, 220, 235, r10, g10, b10); -- Excadrill Silver Drill
            when 'R' => set_rgb(230, 45,  45,  r10, g10, b10); -- Excadrill Red Stripes
            when 'C' => set_rgb(40,  130, 245, r10, g10, b10); -- Human Blue Cap & Shirt
            when 'F' => set_rgb(255, 210, 165, r10, g10, b10); -- Human Skin Face
            when 'H' => -- Hammer Head (Flashes bright yellow during hammer swing)
                if flash then set_rgb(255, 255, 100, r10, g10, b10);
                else          set_rgb(190, 195, 205, r10, g10, b10); end if;
            when 'G' => set_rgb(255, 200, 20,  r10, g10, b10); -- Crypto Coin Gold
            when 'Y' => set_rgb(255, 245, 130, r10, g10, b10); -- Coin Bright Highlight
            when 'O' => set_rgb(200, 130, 10,  r10, g10, b10); -- Coin Deep Shadow
            when others => null; -- '.' Transparent pixel: keep background color
        end case;
    end procedure;

begin

    process(video_on, pixel_x, pixel_y, cursor_x, cursor_y, player_x, player_y,
            attack_anim, moles, coin_count, time_left_sec,
            round_num, combo_cnt, intro_sec, game_state)
        variable r, g, b            : std_logic_vector(9 downto 0);
        variable dx, dy             : integer;
        variable dist_sq            : integer;
        variable sprite_x           : integer;
        variable sprite_y           : integer;
        variable char_col, char_row : integer;
        variable sub_x, sub_y       : integer;
        variable text_ch            : character;
        variable mining_shake       : integer;
        variable pixel_char         : character;
        variable hp_fill_w          : integer;
        variable combo_bar_w        : integer;
        variable hud_str            : string(1 to 18);
    begin
        -- Initialize all combinational variables to prevent latch inference
        r            := (others => '0');
        g            := (others => '0');
        b            := (others => '0');
        dx           := 0;
        dy           := 0;
        dist_sq      := 0;
        sprite_x     := 0;
        sprite_y     := 0;
        char_col     := 0;
        char_row     := 0;
        sub_x        := 0;
        sub_y        := 0;
        text_ch      := ' ';
        mining_shake := 0;
        pixel_char   := '.';
        hp_fill_w    := 0;
        combo_bar_w  := 0;
        hud_str      := (others => ' ');

        if video_on = '1' then

            -- ================================================================
            -- 0. PRE-GAME 10s RULE EXPLANATION & 3s COUNTDOWN OVERLAY
            -- ================================================================
            if game_state = 0 and intro_sec > 0 and
               pixel_x >= 16 and pixel_x < 464 and
               pixel_y >= 80 and pixel_y < 400 then

                if pixel_x < 24 or pixel_x >= 456 or pixel_y < 88 or pixel_y >= 392 then
                    if intro_sec <= 3 then
                        set_rgb(255, 195, 40, r, g, b);  -- 3s Countdown: Gold Frame
                    else
                        set_rgb(80, 190, 255, r, g, b);  -- Rule Screen: Cyan Frame
                    end if;
                elsif pixel_x < 26 or pixel_x >= 454 or pixel_y < 90 or pixel_y >= 390 then
                    set_rgb(255, 255, 255, r, g, b);
                else
                    set_rgb(18, 24, 38, r, g, b);

                    if intro_sec > 3 then
                        -- 10s..4s: Show 16x34 Rule Explanation Text
                        if pixel_x >= 36 and pixel_x < 444 and
                           pixel_y >= 112 and pixel_y < 368 then
                            char_col := (pixel_x - 36) / 12;
                            char_row := (pixel_y - 112) / 16;
                            sub_x    := ((pixel_x - 36) mod 12) / 2;
                            sub_y    := ((pixel_y - 112) mod 16) / 2;
                            text_ch  := RULE_OVERLAY_TEXT(char_row)(char_col + 1);
                            if sub_x < 5 and sub_y < 7 then
                                if get_font_pixel(text_ch, sub_y, sub_x) = '1' then
                                    if char_row = 0 then
                                        set_rgb(255, 225, 80, r, g, b);
                                    elsif char_row = 4 or char_row = 9 then
                                        set_rgb(90, 230, 255, r, g, b);
                                    elsif char_row = 14 or char_row = 15 then
                                        set_rgb(120, 240, 180, r, g, b);
                                    elsif char_row = 1 or char_row = 13 then
                                        set_rgb(110, 125, 155, r, g, b);
                                    else
                                        set_rgb(240, 245, 255, r, g, b);
                                    end if;
                                end if;
                            end if;
                        end if;
                    else
                        -- 3s..1s: Big "GET READY!" + 12x Scaled Countdown Digit (3, 2, 1)
                        if pixel_x >= 180 and pixel_x < 300 and
                           pixel_y >= 130 and pixel_y < 146 then
                            hud_str(1 to 10) := "GET READY!";
                            char_col := (pixel_x - 180) / 12;
                            sub_x    := ((pixel_x - 180) mod 12) / 2;
                            sub_y    := (pixel_y - 130) / 2;
                            if sub_x < 5 and sub_y < 7 then
                                if get_font_pixel(hud_str(char_col + 1), sub_y, sub_x) = '1' then
                                    set_rgb(120, 230, 255, r, g, b);
                                end if;
                            end if;
                        elsif pixel_x >= 210 and pixel_x < 270 and
                              pixel_y >= 185 and pixel_y < 269 then
                            sub_x := (pixel_x - 210) / 12;
                            sub_y := (pixel_y - 185) / 12;
                            if sub_x < 5 and sub_y < 7 then
                                if get_font_pixel(digit_char(intro_sec), sub_y, sub_x) = '1' then
                                    set_rgb(255, 215, 60, r, g, b);
                                end if;
                            end if;
                        end if;
                    end if;
                end if;

            -- ================================================================
            -- 1. END-OF-ROUND REWARD LINK & CLAIM CODE OVERLAY (game_state = 1 or 2)
            -- ================================================================
            elsif game_state /= 0 and
               pixel_x >= 16 and pixel_x < 464 and
               pixel_y >= 80 and pixel_y < 400 then

                -- Outer Colored Victory Frame (8px thick: X 16..23 / 456..463, Y 80..87 / 392..399)
                if pixel_x < 24 or pixel_x >= 456 or pixel_y < 88 or pixel_y >= 392 then
                    if game_state = 1 then
                        set_rgb(30, 210, 100, r, g, b); -- Human Victory: Green Frame
                    else
                        set_rgb(245, 170, 20, r, g, b); -- Mole Victory: Gold Frame
                    end if;

                -- Inner White Border Line (2px thick)
                elsif pixel_x < 26 or pixel_x >= 454 or pixel_y < 90 or pixel_y >= 390 then
                    set_rgb(255, 255, 255, r, g, b);

                -- Dark Navy Text Panel (X: 26..453, Y: 90..389)
                else
                    set_rgb(18, 24, 38, r, g, b);

                    -- 34 Cols x 16 Rows Text Grid (Each char scaled 2x to 12x16 px -> 408x256 px)
                    if pixel_x >= 36 and pixel_x < 444 and
                       pixel_y >= 112 and pixel_y < 368 then

                        char_col := (pixel_x - 36) / 12;
                        char_row := (pixel_y - 112) / 16;
                        sub_x    := ((pixel_x - 36) mod 12) / 2;
                        sub_y    := ((pixel_y - 112) mod 16) / 2;
                        text_ch  := REWARD_OVERLAY_TEXT(char_row)(char_col + 1);

                        if sub_x < 5 and sub_y < 7 then
                            if get_font_pixel(text_ch, sub_y, sub_x) = '1' then
                                if char_row = 0 then
                                    if game_state = 1 then
                                        set_rgb(50, 235, 120, r, g, b);  -- Human Win Title
                                    else
                                        set_rgb(255, 195, 30, r, g, b);  -- Mole Win Title
                                    end if;
                                elsif char_row = 2 or char_row = 6 then
                                    set_rgb(100, 225, 255, r, g, b);     -- Section Header (Cyan)
                                elsif char_row = 3 or char_row = 4 then
                                    set_rgb(255, 235, 110, r, g, b);     -- Cloudflare URL (Yellow)
                                elsif char_row >= 8 and char_row <= 12 then
                                    if char_col < 5 then
                                        set_rgb(120, 240, 180, r, g, b); -- /r/1..5 Path (Mint)
                                    elsif char_col >= 24 then
                                        set_rgb(255, 175, 85, r, g, b);  -- (1-TIME) Badge (Orange)
                                    else
                                        set_rgb(255, 255, 255, r, g, b); -- 16-Hex Claim Code (White)
                                    end if;
                                elsif char_row = 1 or char_row = 5 or char_row = 7 or char_row = 13 then
                                    set_rgb(110, 125, 155, r, g, b);     -- Divider Line (Gray)
                                else
                                    set_rgb(175, 210, 250, r, g, b);     -- Footer Guide (Light Blue)
                                end if;
                            end if;
                        end if;
                    end if;
                end if;

            -- ================================================================
            -- 2. LEFT 480x480 SQUARE GAME MAP (X: 0..479, Y: 0..479)
            -- ================================================================
            elsif pixel_x < 480 then

                -- Layer A: Pixel-Art Grass Checkerboard Tile Background (16x16 tiles)
                if ((pixel_x / 16) + (pixel_y / 16)) mod 2 = 0 then
                    set_rgb(55, 135, 55, r, g, b);
                else
                    set_rgb(48, 122, 48, r, g, b);
                end if;

                -- Grass blade dot detail inside each 16x16 tile
                if (pixel_x mod 16 = 3 and pixel_y mod 16 = 5) or
                   (pixel_x mod 16 = 11 and pixel_y mod 16 = 12) then
                    set_rgb(75, 165, 70, r, g, b);
                end if;

                -- Outer brown map border (4px thick)
                if pixel_x < 4 or pixel_x >= 476 or pixel_y < 4 or pixel_y >= 476 then
                    set_rgb(90, 65, 40, r, g, b);
                end if;

                -- Layer B: Inner No-Spawn Safe Square Dashed Boundary (X: 140..340, Y: 140..340)
                if ((pixel_x = 140 or pixel_x = 340) and (pixel_y >= 140 and pixel_y <= 340)) or
                   ((pixel_y = 140 or pixel_y = 340) and (pixel_x >= 140 and pixel_x <= 340)) then
                    if ((pixel_x + pixel_y) / 4) mod 2 = 0 then
                        set_rgb(220, 210, 120, r, g, b);
                    end if;
                end if;

                -- Layer C: Player 1 Semi-Transparent Circular Attack Range (R = 48, R^2 = 2304)
                dx      := pixel_x - player_x;
                dy      := pixel_y - player_y;
                dist_sq := (dx * dx) + (dy * dy);

                if dist_sq >= 2116 and dist_sq <= 2304 then
                    if attack_anim > 0 then
                        set_rgb(255, 240, 80, r, g, b);  -- Bright Yellow during attack
                    else
                        set_rgb(100, 220, 255, r, g, b); -- Cyan Range Ring
                    end if;
                elsif dist_sq < 2116 then
                    if ((pixel_x + pixel_y) mod 2) = 0 then
                        if attack_anim > 0 then
                            set_rgb(160, 180, 90, r, g, b);
                        else
                            set_rgb(70, 165, 110, r, g, b);
                        end if;
                    end if;
                end if;

                -- Layer D: Central Crypto Coin Pile (32x32 centered at 240, 240)
                if coin_count > 0 and
                   pixel_x >= 224 and pixel_x < 256 and
                   pixel_y >= 224 and pixel_y < 256 then
                    sprite_x   := (pixel_x - 224) / 2;
                    sprite_y   := (pixel_y - 224) / 2;
                    pixel_char := SPRITE_COIN(sprite_y)(sprite_x + 1);
                    draw_sprite_pixel(pixel_char, false, r, g, b);
                end if;

                -- Layer E: 8 Active Mole Sprites + Thin 3px HP Bars above each mole
                for i in 0 to MAX_MOLES - 1 loop
                    if moles(i).active = '1' then
                        if moles(i).mining = '1' and ((moles(i).mine_timer / 4) mod 2) = 1 then
                            mining_shake := 2;
                        else
                            mining_shake := 0;
                        end if;

                        -- 1) Mole 32x32 Sprite
                        if pixel_x >= (moles(i).x - 16 + mining_shake) and
                           pixel_x <  (moles(i).x + 16 + mining_shake) and
                           pixel_y >= (moles(i).y - 16) and
                           pixel_y <  (moles(i).y + 16) then
                            sprite_x := (pixel_x - (moles(i).x - 16 + mining_shake)) / 2;
                            sprite_y := (pixel_y - (moles(i).y - 16)) / 2;

                            if moles(i).kind = '0' then
                                pixel_char := SPRITE_DIGLETT(sprite_y)(sprite_x + 1);
                            else
                                pixel_char := SPRITE_EXCADRILL(sprite_y)(sprite_x + 1);
                            end if;

                            draw_sprite_pixel(pixel_char, (moles(i).mining = '1'), r, g, b);
                        end if;

                        -- 2) Thin 3px-High, 24px-Wide HP Bar (Y: y-21 .. y-19, X: x-12 .. x+11)
                        if pixel_x >= (moles(i).x - 12 + mining_shake) and
                           pixel_x <  (moles(i).x + 12 + mining_shake) and
                           pixel_y >= (moles(i).y - 21) and
                           pixel_y <  (moles(i).y - 18) then
                            -- Compute exact 24px-scaled HP bar width without hardware division
                            if round_num = 1 then
                                if moles(i).kind = '0' then hp_fill_w := moles(i).hp * 24; -- max 1
                                else                        hp_fill_w := moles(i).hp * 12; -- max 2
                                end if;
                            elsif round_num = 2 then
                                if moles(i).kind = '0' then hp_fill_w := moles(i).hp * 12; -- max 2
                                else                        hp_fill_w := moles(i).hp * 6;  -- max 4
                                end if;
                            else
                                if moles(i).kind = '0' then hp_fill_w := moles(i).hp * 8;  -- max 3
                                else                        hp_fill_w := moles(i).hp * 4;  -- max 6
                                end if;
                            end if;

                            if (pixel_x - (moles(i).x - 12 + mining_shake)) < hp_fill_w then
                                if moles(i).kind = '0' then
                                    set_rgb(80, 235, 110, r, g, b); -- Diglett HP: Green
                                else
                                    set_rgb(255, 85, 85, r, g, b);  -- Excadrill HP: Red
                                end if;
                            else
                                set_rgb(30, 30, 40, r, g, b);       -- Empty HP background
                            end if;
                        end if;
                    end if;
                end loop;

                -- Layer F: Player 1 Evolving Hammer Sprite (32x32 centered at player_x, player_y)
                if pixel_x >= (player_x - 16) and pixel_x < (player_x + 16) and
                   pixel_y >= (player_y - 16) and pixel_y < (player_y + 16) then
                    sprite_x := (pixel_x - (player_x - 16)) / 2;
                    sprite_y := (pixel_y - (player_y - 16)) / 2;
                    if combo_cnt >= 6 then
                        pixel_char := SPRITE_HAMMER_3(sprite_y)(sprite_x + 1);
                    elsif combo_cnt >= 3 then
                        pixel_char := SPRITE_HAMMER_2(sprite_y)(sprite_x + 1);
                    else
                        pixel_char := SPRITE_HAMMER_1(sprite_y)(sprite_x + 1);
                    end if;
                    draw_sprite_pixel(pixel_char, (attack_anim > 0 or combo_cnt >= 9), r, g, b);
                end if;

            -- ================================================================
            -- 3. RIGHT 160x480 STATUS HUD SIDEBAR (X: 480..639, Y: 0..479)
            -- ================================================================
            else
                -- Dark Navy HUD Background & Divider Line
                set_rgb(25, 30, 45, r, g, b);
                if pixel_x < 484 then
                    set_rgb(180, 190, 210, r, g, b);
                end if;

                -- ------------------------------------------------------------
                -- A. Stage / Coins / Time / Combo Bitmap Text Labels
                -- ------------------------------------------------------------
                -- 1) STAGE 1/3..3/3 (2x Scale: 12x16 px, X: 500..607, Y: 22..37)
                if pixel_x >= 500 and pixel_x < 608 and pixel_y >= 22 and pixel_y < 38 then
                    hud_str(1 to 9) := "STAGE " & digit_char(round_num) & "/3";
                    char_col := (pixel_x - 500) / 12;
                    sub_x    := ((pixel_x - 500) mod 12) / 2;
                    sub_y    := (pixel_y - 22) / 2;
                    if sub_x < 5 and sub_y < 7 then
                        if get_font_pixel(hud_str(char_col + 1), sub_y, sub_x) = '1' then
                            set_rgb(255, 220, 90, r, g, b); -- Gold Stage Header
                        end if;
                    end if;

                -- 2) COINS: XX (2x Scale: 12x16 px, X: 500..607, Y: 68..83)
                elsif pixel_x >= 500 and pixel_x < 608 and pixel_y >= 68 and pixel_y < 84 then
                    hud_str(1 to 9) := "COINS: " & digit_char((coin_count / 10) mod 10) & digit_char(coin_count mod 10);
                    char_col := (pixel_x - 500) / 12;
                    sub_x    := ((pixel_x - 500) mod 12) / 2;
                    sub_y    := (pixel_y - 68) / 2;
                    if sub_x < 5 and sub_y < 7 then
                        if get_font_pixel(hud_str(char_col + 1), sub_y, sub_x) = '1' then
                            set_rgb(255, 205, 25, r, g, b);
                        end if;
                    end if;

                -- 3) TIME: XXs (2x Scale: 12x16 px, X: 500..607, Y: 138..153)
                elsif pixel_x >= 500 and pixel_x < 608 and pixel_y >= 138 and pixel_y < 154 then
                    hud_str(1 to 9) := "TIME: " & digit_char((time_left_sec / 10) mod 10) & digit_char(time_left_sec mod 10) & "s";
                    char_col := (pixel_x - 500) / 12;
                    sub_x    := ((pixel_x - 500) mod 12) / 2;
                    sub_y    := (pixel_y - 138) / 2;
                    if sub_x < 5 and sub_y < 7 then
                        if get_font_pixel(hud_str(char_col + 1), sub_y, sub_x) = '1' then
                            set_rgb(70, 175, 255, r, g, b);
                        end if;
                    end if;

                -- 4) COMBO: XX (2x Scale: 12x16 px, X: 500..607, Y: 210..225)
                elsif pixel_x >= 500 and pixel_x < 608 and pixel_y >= 210 and pixel_y < 226 then
                    if combo_cnt > 99 then
                        hud_str(1 to 9) := "COMBO: 99";
                    else
                        hud_str(1 to 9) := "COMBO: " & digit_char((combo_cnt / 10) mod 10) & digit_char(combo_cnt mod 10);
                    end if;
                    char_col := (pixel_x - 500) / 12;
                    sub_x    := ((pixel_x - 500) mod 12) / 2;
                    sub_y    := (pixel_y - 210) / 2;
                    if sub_x < 5 and sub_y < 7 then
                        if get_font_pixel(hud_str(char_col + 1), sub_y, sub_x) = '1' then
                            set_rgb(255, 255, 255, r, g, b);
                        end if;
                    end if;

                -- 5) Combo Stage Label (2x Scale: 12x16 px, X: 496..615, Y: 234..249)
                elsif pixel_x >= 496 and pixel_x < 616 and pixel_y >= 234 and pixel_y < 250 then
                    if combo_cnt >= 9 then
                        hud_str(1 to 10) := "LV3 CRIT3!";
                    elsif combo_cnt >= 6 then
                        hud_str(1 to 10) := "LV2 SPD UP";
                    elsif combo_cnt >= 3 then
                        hud_str(1 to 10) := "LV1 DMG x2";
                    else
                        hud_str(1 to 10) := "LV0 NORMAL";
                    end if;
                    char_col := (pixel_x - 496) / 12;
                    sub_x    := ((pixel_x - 496) mod 12) / 2;
                    sub_y    := (pixel_y - 234) / 2;
                    if sub_x < 5 and sub_y < 7 then
                        if get_font_pixel(hud_str(char_col + 1), sub_y, sub_x) = '1' then
                            if combo_cnt >= 9 then
                                set_rgb(255, 170, 40, r, g, b);  -- LV3: Orange
                            elsif combo_cnt >= 6 then
                                set_rgb(70, 235, 130, r, g, b);  -- LV2: Green
                            elsif combo_cnt >= 3 then
                                set_rgb(90, 220, 255, r, g, b);  -- LV1: Cyan
                            else
                                set_rgb(160, 170, 190, r, g, b); -- LV0: Gray
                            end if;
                        end if;
                    end if;

                -- 6) Combo Threshold Hint (1x Scale: 6x8 px, X: 500..607, Y: 288..295)
                elsif pixel_x >= 500 and pixel_x < 608 and pixel_y >= 288 and pixel_y < 296 then
                    hud_str(1 to 18) := "3:DMG2 6:SPD 9:CR3";
                    char_col := (pixel_x - 500) / 6;
                    sub_x    := (pixel_x - 500) mod 6;
                    sub_y    := pixel_y - 288;
                    if sub_x < 5 and sub_y < 7 then
                        if get_font_pixel(hud_str(char_col + 1), sub_y, sub_x) = '1' then
                            set_rgb(140, 155, 185, r, g, b);
                        end if;
                    end if;
                end if;

                -- ------------------------------------------------------------
                -- B. Status Bars & Match State Box (X: 504..603, Width = 100 px)
                -- ------------------------------------------------------------
                if pixel_x >= 504 and pixel_x < 604 then

                    -- Bar 1 (Y: 90..111): Remaining Crypto Coins (50 -> 0, scaled * 2 = 100 px)
                    if pixel_y >= 90 and pixel_y < 112 then
                        if (pixel_x - 504) < (coin_count * 2) then
                            set_rgb(255, 205, 25, r, g, b); -- Gold Coin Bar
                        else
                            set_rgb(55, 60, 75, r, g, b);
                        end if;

                    -- Bar 2 (Y: 160..181): Remaining Round Time (R1/R2: 10s*10=100px, R3: 15s*20/3=100px)
                    elsif pixel_y >= 160 and pixel_y < 182 then
                        if (round_num < 3 and (pixel_x - 504) < (time_left_sec * 10)) or
                           (round_num = 3 and (pixel_x - 504) < ((time_left_sec * 20) / 3)) then
                            set_rgb(70, 170, 255, r, g, b); -- Blue Timer Bar
                        else
                            set_rgb(55, 60, 75, r, g, b);
                        end if;

                    -- Bar 3 (Y: 258..279): Combo Progress Bar (0..9 scaled to 100 px)
                    elsif pixel_y >= 258 and pixel_y < 280 then
                        if combo_cnt >= 9 then
                            combo_bar_w := 100;
                        else
                            combo_bar_w := combo_cnt * 11;
                        end if;

                        if (pixel_x - 504) < combo_bar_w then
                            if combo_cnt >= 9 then
                                set_rgb(255, 170, 40, r, g, b);
                            elsif combo_cnt >= 6 then
                                set_rgb(70, 235, 130, r, g, b);
                            elsif combo_cnt >= 3 then
                                set_rgb(90, 220, 255, r, g, b);
                            else
                                set_rgb(160, 170, 190, r, g, b);
                            end if;
                        else
                            set_rgb(55, 60, 75, r, g, b);
                        end if;

                    -- Box 4 (Y: 345..409): Match Status Indicator Box + Text
                    elsif pixel_y >= 345 and pixel_y < 410 then
                        if game_state = 0 then
                            set_rgb(60, 90, 140, r, g, b);  -- Playing
                        elsif game_state = 1 then
                            set_rgb(30, 210, 100, r, g, b); -- Human Wins!
                        else
                            set_rgb(235, 65, 55, r, g, b);  -- Mole Wins!
                        end if;

                        if pixel_x >= 512 and pixel_x < 596 and pixel_y >= 370 and pixel_y < 386 then
                            if game_state = 0 then
                                hud_str(1 to 7) := "PLAYING";
                            elsif game_state = 1 then
                                hud_str(1 to 7) := "P1 WIN!";
                            else
                                hud_str(1 to 7) := "P2 WIN!";
                            end if;
                            char_col := (pixel_x - 512) / 12;
                            sub_x    := ((pixel_x - 512) mod 12) / 2;
                            sub_y    := (pixel_y - 370) / 2;
                            if sub_x < 5 and sub_y < 7 then
                                if get_font_pixel(hud_str(char_col + 1), sub_y, sub_x) = '1' then
                                    set_rgb(255, 255, 255, r, g, b);
                                end if;
                            end if;
                        end if;
                    end if;

                end if;
            end if;

            -- Layer G: PS/2 Mouse Aim Crosshair (+) (Always visible on 480x480 map, including intro)
            if pixel_x < 480 and
               ((abs(pixel_x - cursor_x) <= 6 and abs(pixel_y - cursor_y) <= 1) or
                (abs(pixel_y - cursor_y) <= 6 and abs(pixel_x - cursor_x) <= 1)) then
                set_rgb(255, 60, 60, r, g, b);
            end if;
        end if;

        vga_r <= r;
        vga_g <= g;
        vga_b <= b;
    end process;

end architecture behavioral;
