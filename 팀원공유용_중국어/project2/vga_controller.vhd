library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================================
-- Module 1: VGA Timing Controller (640x480 @ 60Hz)
--   * Divides 50 MHz system clock down to 25 MHz pixel clock
--   * Generates H-Sync, V-Sync, active video flag (video_on), and pixel (X, Y)
--   * Generates a 60Hz 1-clock pulse (frame_tick) at the end of every frame
-- ============================================================================
entity vga_controller is
    port (
        CLOCK_50   : in  std_logic;
        reset_n    : in  std_logic;
        vga_clk    : out std_logic;
        hsync      : out std_logic;
        vsync      : out std_logic;
        blank_n    : out std_logic;
        sync_n     : out std_logic;
        video_on   : out std_logic;
        frame_tick : out std_logic; -- 1-clock pulse (60Hz) for game physics update
        pixel_x    : out integer range 0 to 799;
        pixel_y    : out integer range 0 to 524
    );
end entity vga_controller;

architecture behavioral of vga_controller is

    -- Horizontal Timing Constants (Unit: Pixels @ 25 MHz)
    constant H_DISPLAY : integer := 640; -- Visible horizontal area
    constant H_FRONT   : integer := 16;  -- Horizontal front porch
    constant H_SYNC    : integer := 96;  -- Horizontal sync pulse width
    constant H_BACK    : integer := 48;  -- Horizontal back porch
    constant H_TOTAL   : integer := 800; -- Total pixels per line (640+16+96+48)

    -- Vertical Timing Constants (Unit: Lines)
    constant V_DISPLAY : integer := 480; -- Visible vertical area
    constant V_FRONT   : integer := 10;  -- Vertical front porch
    constant V_SYNC    : integer := 2;   -- Vertical sync pulse width
    constant V_BACK    : integer := 33;  -- Vertical back porch
    constant V_TOTAL   : integer := 525; -- Total lines per frame (480+10+2+33)

    signal clk_25      : std_logic := '0';
    signal h_cnt       : integer range 0 to H_TOTAL - 1 := 0;
    signal v_cnt       : integer range 0 to V_TOTAL - 1 := 0;
    signal vid_on      : std_logic := '0';

begin

    -- 1. 50MHz -> 25MHz Clock Divider & Horizontal/Vertical Pixel Counters
    process(CLOCK_50, reset_n)
    begin
        if reset_n = '0' then
            clk_25     <= '0';
            h_cnt      <= 0;
            v_cnt      <= 0;
            frame_tick <= '0';
        elsif rising_edge(CLOCK_50) then
            -- Toggle clk_25 every 50MHz clock -> creates 25MHz frequency
            clk_25     <= not clk_25;
            frame_tick <= '0';

            -- Update pixel coordinates once per 25MHz period (when clk_25 = '1')
            if clk_25 = '1' then
                if h_cnt = H_TOTAL - 1 then
                    h_cnt <= 0;
                    if v_cnt = V_TOTAL - 1 then
                        v_cnt <= 0;
                    else
                        v_cnt <= v_cnt + 1;
                    end if;
                else
                    h_cnt <= h_cnt + 1;
                end if;

                -- Emit 60Hz pulse right after the last visible line (line 480, pixel 0)
                if h_cnt = 0 and v_cnt = V_DISPLAY then
                    frame_tick <= '1';
                end if;
            end if;
        end if;
    end process;

    -- 2. Generate Active-Low H-Sync and V-Sync Signals
    hsync <= '0' when (h_cnt >= H_DISPLAY + H_FRONT and h_cnt < H_DISPLAY + H_FRONT + H_SYNC) else '1';
    vsync <= '0' when (v_cnt >= V_DISPLAY + V_FRONT and v_cnt < V_DISPLAY + V_FRONT + V_SYNC) else '1';

    -- 3. Active Display Region Flag (True when inside 640x480 visible screen)
    vid_on   <= '1' when (h_cnt < H_DISPLAY and v_cnt < V_DISPLAY) else '0';

    -- 4. Output Signals to DE2 ADV7123 VGA DAC
    video_on <= vid_on;
    blank_n  <= vid_on;
    sync_n   <= '0';
    vga_clk  <= clk_25;
    pixel_x  <= h_cnt;
    pixel_y  <= v_cnt;

end architecture behavioral;
