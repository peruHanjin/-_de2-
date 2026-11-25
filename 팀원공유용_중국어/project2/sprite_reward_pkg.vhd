library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================================
-- Package: sprite_reward_pkg
-- Contains:
--   1. Mole Data Structure (8 Active Mole Slots for 50 Kills per Round)
--   2. 16x16 Pixel Art Sprites (Diglett/두더류, Excadrill/몰드류, Human+Hammer, Crypto Coin)
--   3. End-of-Round 50 MMC Reward Link & Claim Code Text ROM + 5x7 ASCII Font ROM
-- ============================================================================
package sprite_reward_pkg is

    constant MAX_MOLES : integer := 8;

    -- Active Mole Record Type
    type mole_rec_t is record
        active     : std_logic;
        x          : integer range 0 to 511;
        y          : integer range 0 to 511;
        kind       : std_logic;             -- '0' = Diglett (두더류), '1' = Excadrill (몰드류)
        hp         : integer range 0 to 7;  -- Remaining hits to kill (R1:1/2, R2:2/4, R3:3/6)
        mining     : std_logic;             -- '1' when within mining distance of coin pile
        mine_timer : integer range 0 to 63; -- 0..59 (60 ticks at 60Hz = 1.0 second mining motion)
    end record;

    type mole_array_t is array (0 to MAX_MOLES - 1) of mole_rec_t;

    -- 16x16 Sprite Palette Matrix
    type sprite_16x16_t is array (0 to 15) of string(1 to 16);

    -- ========================================================================
    -- 1. Diglett / Drilbur (두더류) 16x16 Dot Art
    -- Palette: '.'=Transparent, 'B'=Brown Body, 'D'=Dark Brown, 'W'=White Face/Claws,
    --          'K'=Black Outline/Eye, 'P'=Pink Nose, 'C'=Blue Markings
    -- ========================================================================
    constant SPRITE_DIGLETT : sprite_16x16_t := (
        "......KK........",
        ".....KBBKK......",
        "....KBBBBBK.....",
        "....KBBBBBD.....",
        "...KWBBBBBB.....",
        "...KWWWWBBBK....",
        "..KWWWWKBBBK....",
        "..DPWWWWBBBCKK..",
        ".KDDDKDDCDCBBCK.",
        "KWCKKKDCCDCBCCK.",
        "KWK..DCCDDDBDDWK",
        "KK...DCCDDDDWWWK",
        ".....BDKDCCWWWWK",
        ".....KK.KDDDWWK.",
        ".........KDKKBK.",
        "..........K..K.."
    );

    -- ========================================================================
    -- 2. Excadrill (몰드류 - Special Mole) 16x16 Dot Art
    -- Palette: 'S'=Silver Drill/Claws, 'R'=Red Stripes, 'B'/'D'=Body, 'P'=Pink Nose, 'K'=Black
    -- ========================================================================
    constant SPRITE_EXCADRILL : sprite_16x16_t := (
        "....K...........",
        ".....K.KK.......",
        "...KSDKBBK......",
        "..KDSDSBBB......",
        "...DSSSSBBK.....",
        ".KSSSSSSDBDK....",
        ".KSSSSDDDRDD....",
        ".KDDDBKSDDBD....",
        "..SDSSSRDBBBS.K.",
        ".DSDPDDDDDDSDSK.",
        "..KKDDDRDDSSSDK.",
        "KK..DDDRDDSSSSD.",
        "....BDDDDBRDKSSK",
        "....KKKDDBDK.KSK",
        ".......KKDK...KK",
        ".........KK....."
    );

    -- ========================================================================
    -- 3. Player 1 (Evolving Wooden/Iron/Spiked Hammer) 16x16 Dot Art
    --    * SPRITE_HAMMER_1: LV0 (0..2 Combo)  - Basic Wooden Mallet
    --    * SPRITE_HAMMER_2: LV1 (3..5 Combo)  - Iron-Banded Mallet
    --    * SPRITE_HAMMER_3: LV2/3 (6+ Combo)  - Spiked Giant Mallet
    -- Palette: 'B'=Wood Brown, 'D'=Dark Wood, 'G'=Bright Wood Grain,
    --          'S'=Silver Iron Band, 'H'=Spike/Highlight, 'K'=Black Outline
    -- ========================================================================
    constant SPRITE_HAMMER_1 : sprite_16x16_t := (
        "................",
        "................",
        ".......KK.......",
        "......KBBK......",
        ".....KBBBBK.....",
        "....KBBBBBGDK...",
        "....KDBBBBGGDK..",
        ".....KDBBBGGDK..",
        ".....KDKDBBGDK..",
        "....KDBK.KDDK...",
        "...KDBK...KK....",
        "..KDBK..........",
        ".KDBK...........",
        ".KDK............",
        "..K.............",
        "................"
    );

    constant SPRITE_HAMMER_2 : sprite_16x16_t := (
        "................",
        "......KK........",
        ".....KSSK.......",
        "....KSSBBK......",
        "...KSSBBBBK.....",
        "...KDBBSSBGDK...",
        "....KDBBSSGGDK..",
        "....KDKDBSSGDK..",
        "...KDBK.KBSSDK..",
        "..KDBK...KDDK...",
        ".KDBK.....KK....",
        ".KDBK...........",
        ".KDK............",
        "..K.............",
        "................",
        "................"
    );

    constant SPRITE_HAMMER_3 : sprite_16x16_t := (
        "......H.........",
        "....HKSSK.......",
        "...KSSBBBK......",
        "..HKSSBBBBK.....",
        "..KDBBSSBGGK....",
        "...KDBBSSBGGDK..",
        "...KDKDBSSGGDK..",
        "..KDBK.KBSSGDKH.",
        ".KDBK...KBSSDK..",
        ".KDBK....KGGDK..",
        "KDBK......KDK...",
        "KDK........H....",
        ".K..............",
        "................",
        "................",
        "................"
    );

    -- ========================================================================
    -- 4. Central Crypto Coin Pile (32x32 rendered by 2x scaling of 16x16 template)
    -- Palette: 'G'=Bright Gold, 'Y'=Yellow Highlight, 'O'=Orange Shadow
    -- ========================================================================
    constant SPRITE_COIN : sprite_16x16_t := (
        ".....GGGGGG.....",
        "...GGGGGGGGGG...",
        "..GGYYYYYYYYGG..",
        ".GGYYGGGGGGYYGG.",
        ".GGYGGYYYYGGYGG.",
        "GGYGGYYGGYYGGYGG",
        "GGYGGYGGGGYGGYGG",
        "GGYGGYGGGGYGGYGG",
        "GGYGGYYGGYYGGYGG",
        "GGYGGYYYYGGGYGG.",
        ".GGYGGGGGGGGYGG.",
        ".GGYYGGGGGGYYGG.",
        "..GGYYYYYYYYGG..",
        "...OOOOOOOOOO...",
        "..OOOOOOOOOOOO..",
        ".....OOOOOO....."
    );

    -- ========================================================================
    -- 5. End-of-Round 50 MMC Reward Link & Claim Code Overlay Text Table
    --    (16 Rows x 34 Columns, rendered at 12x16 pixels per character = 408x256)
    --
    -- [주의 / 변동 가능 값 & 1회용 안내]
    --   * 아래 Cloudflare Tunnel 링크(Row 3~4)와 5개의 수령 코드(Row 8~12)는
    --     보상 서버를 새로 실행할 때마다 매번 새로 발급되어 변동되는 값입니다.
    --   * 또한 각 링크(/r/1 ~ /r/5)와 수령 코드는 모두 1회용(1-TIME USE)이므로,
    --     한 번 수령이 완료된 링크/코드는 재사용할 수 없습니다.
    --   * 실제 시연/합성 전 새로 열린 서버의 URL과 수령 코드로 수정하세요.
    --     (각 줄은 반드시 정확히 34글자 길이를 유지해야 하며, 남는 칸은 공백으로 채움)
    -- ========================================================================
    constant REWARD_TEXT_ROWS : integer := 16;
    constant REWARD_TEXT_COLS : integer := 34;

    type reward_text_t is array (0 to REWARD_TEXT_ROWS - 1) of string(1 to REWARD_TEXT_COLS);

    constant REWARD_OVERLAY_TEXT : reward_text_t := (
        " * 50 MMC REWARD (1-TIME USE) *   ", -- Row 0: Title Banner (1회용 보상 안내)
        "----------------------------------", -- Row 1: Divider
        "REWARD LINK (r/1 ~ r/5):          ", -- Row 2: URL Section Header
        "https://ministers-ind-wait-       ", -- Row 3:  [변동 가능] 서버 재시작 시 URL 도메인 수정
        "expired.trycloudflare.com/r/1~5   ", -- Row 4:  [변동 가능] 서버 재시작 시 URL 도메인 수정
        "----------------------------------", -- Row 5: Divider
        "PATH | CLAIM CODE (1-TIME USE)    ", -- Row 6: Table Header
        "----------------------------------", -- Row 7: Divider
        "/r/1 | 7325DF893DE81A34 (1-TIME)  ", -- Row 8:  [변동 가능 / 1회용] 1번 링크 & 수령코드
        "/r/2 | 992615563C73E07F (1-TIME)  ", -- Row 9:  [변동 가능 / 1회용] 2번 링크 & 수령코드
        "/r/3 | 1AC8A728069A2D10 (1-TIME)  ", -- Row 10: [변동 가능 / 1회용] 3번 링크 & 수령코드
        "/r/4 | 2C8A58F62C935A87 (1-TIME)  ", -- Row 11: [변동 가능 / 1회용] 4번 링크 & 수령코드
        "/r/5 | B8D6BF3D55372747 (1-TIME)  ", -- Row 12: [변동 가능 / 1회용] 5번 링크 & 수령코드
        "----------------------------------", -- Row 13: Divider
        "1-TIME ONLY! ENTER CODE & 0x ADDR ", -- Row 14: Claim Page Guide (1회용 주의)
        "PRESS KEY(3) TO RESET NEXT GAME   "  -- Row 15: Reset Guide
    );

    -- 6. Pre-Game 10-Second Rule Explanation Overlay Text Table (16 Rows x 34 Cols)
    constant RULE_OVERLAY_TEXT : reward_text_t := (
        "  * CRYPTO MINER DEFENSE RULES *  ", -- Row 0
        "----------------------------------", -- Row 1
        "R1/2:20s R3:30s | 50 COINS TOTAL  ", -- Row 2
        "                                  ", -- Row 3
        "[P1 HUMAN] MOUSE MOVE + KEY0/CLICK", -- Row 4
        " - DEFEND 50 COINS IN CENTER      ", -- Row 5
        " - WHIFF = 0.5s STUN & -1 COMBO LV", -- Row 6
        " - COMBO 3:DMG2 | 6:SPD3 | 9:CRIT3", -- Row 7
        "                                  ", -- Row 8
        "[P2 MOLE] SW17..SW6 CLOCKWISE SPWN", -- Row 9
        " - MAX 8 MOLES / NO SAME ZONE TWCE", -- Row 10
        " - EXCADRILL: R1:1/8 R2:2/8 R3:4/8", -- Row 11
        " - MOLE HP & SPEED UP EACH ROUND  ", -- Row 12
        "----------------------------------", -- Row 13
        "WINNER GETS 50 MMC CLAIM LINK!    ", -- Row 14
        "STARTING SOON...                  "  -- Row 15
    );

    -- 5x7 Bitmap Font Pixel Lookup Function ('1' = Foreground Pixel, '0' = Background)
    function get_font_pixel(
        ch  : character;
        row : integer range 0 to 6;
        col : integer range 0 to 4
    ) return std_logic;

end package sprite_reward_pkg;

package body sprite_reward_pkg is

    type glyph_5x7_t is array (0 to 6) of std_logic_vector(0 to 4);

    function get_font_pixel(
        ch  : character;
        row : integer range 0 to 6;
        col : integer range 0 to 4
    ) return std_logic is
        variable glyph : glyph_5x7_t;
    begin
        case ch is
            -- Digits 0..9
            when '0' => glyph := ("01110", "10001", "10011", "10101", "11001", "10001", "01110");
            when '1' => glyph := ("00100", "01100", "00100", "00100", "00100", "00100", "01110");
            when '2' => glyph := ("01110", "10001", "00001", "00110", "01000", "10000", "11111");
            when '3' => glyph := ("11110", "00001", "00001", "01110", "00001", "00001", "11110");
            when '4' => glyph := ("00010", "00110", "01010", "10010", "11111", "00010", "00010");
            when '5' => glyph := ("11111", "10000", "11110", "00001", "00001", "10001", "01110");
            when '6' => glyph := ("00110", "01000", "10000", "11110", "10001", "10001", "01110");
            when '7' => glyph := ("11111", "00001", "00010", "00100", "01000", "01000", "01000");
            when '8' => glyph := ("01110", "10001", "10001", "01110", "10001", "10001", "01110");
            when '9' => glyph := ("01110", "10001", "10001", "01111", "00001", "00010", "01100");

            -- Uppercase Letters A..Z
            when 'A' => glyph := ("01110", "10001", "10001", "11111", "10001", "10001", "10001");
            when 'B' => glyph := ("11110", "10001", "10001", "11110", "10001", "10001", "11110");
            when 'C' => glyph := ("01110", "10001", "10000", "10000", "10000", "10001", "01110");
            when 'D' => glyph := ("11100", "10010", "10001", "10001", "10001", "10010", "11100");
            when 'E' => glyph := ("11111", "10000", "10000", "11110", "10000", "10000", "11111");
            when 'F' => glyph := ("11111", "10000", "10000", "11110", "10000", "10000", "10000");
            when 'G' => glyph := ("01110", "10001", "10000", "10111", "10001", "10001", "01110");
            when 'H' => glyph := ("10001", "10001", "10001", "11111", "10001", "10001", "10001");
            when 'I' => glyph := ("01110", "00100", "00100", "00100", "00100", "00100", "01110");
            when 'J' => glyph := ("00111", "00010", "00010", "00010", "10010", "10010", "01100");
            when 'K' => glyph := ("10001", "10010", "10100", "11000", "10100", "10010", "10001");
            when 'L' => glyph := ("10000", "10000", "10000", "10000", "10000", "10000", "11111");
            when 'M' => glyph := ("10001", "11011", "10101", "10101", "10001", "10001", "10001");
            when 'N' => glyph := ("10001", "11001", "10101", "10011", "10001", "10001", "10001");
            when 'O' => glyph := ("01110", "10001", "10001", "10001", "10001", "10001", "01110");
            when 'P' => glyph := ("11110", "10001", "10001", "11110", "10000", "10000", "10000");
            when 'Q' => glyph := ("01110", "10001", "10001", "10001", "10101", "10010", "01101");
            when 'R' => glyph := ("11110", "10001", "10001", "11110", "10100", "10010", "10001");
            when 'S' => glyph := ("01111", "10000", "10000", "01110", "00001", "00001", "11110");
            when 'T' => glyph := ("11111", "00100", "00100", "00100", "00100", "00100", "00100");
            when 'U' => glyph := ("10001", "10001", "10001", "10001", "10001", "10001", "01110");
            when 'V' => glyph := ("10001", "10001", "10001", "10001", "10001", "01010", "00100");
            when 'W' => glyph := ("10001", "10001", "10001", "10101", "10101", "10101", "01010");
            when 'X' => glyph := ("10001", "10001", "01010", "00100", "01010", "10001", "10001");
            when 'Y' => glyph := ("10001", "10001", "01010", "00100", "00100", "00100", "00100");
            when 'Z' => glyph := ("11111", "00001", "00010", "00100", "01000", "10000", "11111");

            -- Lowercase Letters a..z (For URL string rendering)
            when 'a' => glyph := ("00000", "00000", "01110", "00001", "01111", "10001", "01111");
            when 'b' => glyph := ("10000", "10000", "11110", "10001", "10001", "10001", "11110");
            when 'c' => glyph := ("00000", "00000", "01110", "10000", "10000", "10001", "01110");
            when 'd' => glyph := ("00001", "00001", "01111", "10001", "10001", "10001", "01111");
            when 'e' => glyph := ("00000", "00000", "01110", "10001", "11111", "10000", "01110");
            when 'f' => glyph := ("00110", "01001", "01000", "11100", "01000", "01000", "01000");
            when 'g' => glyph := ("00000", "01111", "10001", "10001", "01111", "00001", "01110");
            when 'h' => glyph := ("10000", "10000", "11110", "10001", "10001", "10001", "10001");
            when 'i' => glyph := ("00100", "00000", "01100", "00100", "00100", "00100", "01110");
            when 'j' => glyph := ("00010", "00000", "00110", "00010", "00010", "10010", "01100");
            when 'k' => glyph := ("10000", "10000", "10010", "10100", "11000", "10100", "10010");
            when 'l' => glyph := ("01100", "00100", "00100", "00100", "00100", "00100", "01110");
            when 'm' => glyph := ("00000", "00000", "11010", "10101", "10101", "10001", "10001");
            when 'n' => glyph := ("00000", "00000", "11110", "10001", "10001", "10001", "10001");
            when 'o' => glyph := ("00000", "00000", "01110", "10001", "10001", "10001", "01110");
            when 'p' => glyph := ("00000", "11110", "10001", "10001", "11110", "10000", "10000");
            when 'q' => glyph := ("00000", "01111", "10001", "10001", "01111", "00001", "00001");
            when 'r' => glyph := ("00000", "00000", "10110", "11001", "10000", "10000", "10000");
            when 's' => glyph := ("00000", "00000", "01111", "10000", "01110", "00001", "11110");
            when 't' => glyph := ("01000", "01000", "11100", "01000", "01000", "01001", "00110");
            when 'u' => glyph := ("00000", "00000", "10001", "10001", "10001", "10011", "01101");
            when 'v' => glyph := ("00000", "00000", "10001", "10001", "10001", "01010", "00100");
            when 'w' => glyph := ("00000", "00000", "10001", "10101", "10101", "10101", "01010");
            when 'x' => glyph := ("00000", "00000", "10001", "01010", "00100", "01010", "10001");
            when 'y' => glyph := ("00000", "10001", "10001", "10001", "01111", "00001", "01110");
            when 'z' => glyph := ("00000", "00000", "11111", "00010", "00100", "01000", "11111");

            -- Punctuation & Symbols for URL and Table Formatting
            when ':' => glyph := ("00000", "00100", "00100", "00000", "00100", "00100", "00000");
            when '/' => glyph := ("00001", "00010", "00010", "00100", "01000", "01000", "10000");
            when '-' => glyph := ("00000", "00000", "00000", "11111", "00000", "00000", "00000");
            when '.' => glyph := ("00000", "00000", "00000", "00000", "00000", "01100", "01100");
            when '|' => glyph := ("00100", "00100", "00100", "00100", "00100", "00100", "00100");
            when '*' => glyph := ("00000", "10101", "01110", "11111", "01110", "10101", "00000");
            when '(' => glyph := ("00010", "00100", "01000", "01000", "01000", "00100", "00010");
            when ')' => glyph := ("01000", "00100", "00010", "00010", "00010", "00100", "01000");
            when '~' => glyph := ("00000", "00000", "01101", "10010", "00000", "00000", "00000");
            when '&' => glyph := ("01100", "10010", "10100", "01000", "10101", "10010", "01101");
            when '#' => glyph := ("01010", "01010", "11111", "01010", "11111", "01010", "01010");
            when '+' => glyph := ("00000", "00100", "00100", "11111", "00100", "00100", "00000");
            when '=' => glyph := ("00000", "00000", "11111", "00000", "11111", "00000", "00000");
            when '[' => glyph := ("01110", "01000", "01000", "01000", "01000", "01000", "01110");
            when ']' => glyph := ("01110", "00010", "00010", "00010", "00010", "00010", "01110");
            when '!' => glyph := ("00100", "00100", "00100", "00100", "00100", "00000", "00100");
            when others => glyph := ("00000", "00000", "00000", "00000", "00000", "00000", "00000");
        end case;

        return glyph(row)(col);
    end function get_font_pixel;

end package body sprite_reward_pkg;
