library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================================
-- Module 2: PS/2 Optical Mouse Controller (NETmate NM-OM01)
--   * Automatically sends 0xF4 (Enable Data Reporting) to wake up the mouse
--   * Receives 3-byte PS/2 movement packets (Byte0: Buttons/Signs, Byte1: dX, Byte2: dY)
--   * Updates screen crosshair position (cursor_x, cursor_y) inside the 480x480 map
-- ============================================================================
entity ps2_mouse_unit is
    port (
        CLOCK_50    : in    std_logic;
        reset_n     : in    std_logic;
        PS2_CLK     : inout std_logic;
        PS2_DAT     : inout std_logic;
        cursor_x    : out   integer range 0 to 479;
        cursor_y    : out   integer range 0 to 479;
        left_click  : out   std_logic;
        right_click : out   std_logic
    );
end entity ps2_mouse_unit;

architecture behavioral of ps2_mouse_unit is

    -- 7-State FSM for Mouse Initialization and Continuous Packet Reception
    type state_t is (
        INIT_WAIT,         -- 1. Wait 40ms after power-on/reset
        TX_PULL_CLK_LOW,   -- 2. Pull PS2_CLK low for 150us (Host Request-to-Send)
        TX_PULL_DAT_LOW,   -- 3. Pull PS2_DAT low (Start Bit) and release PS2_CLK
        TX_SEND_BITS,      -- 4. Shift out 0xF4 command + Odd Parity + Stop Bit
        TX_WAIT_ACK,       -- 5. Wait for mouse ACK bit
        RX_WAIT_ACK_BYTE,  -- 6. Receive 0xFA ACK response byte from mouse
        RX_STREAM_PACKETS  -- 7. Continuously receive 3-byte movement packets
    );
    signal state : state_t := INIT_WAIT;

    -- Synchronizer shift registers to detect falling edge of asynchronous PS2_CLK
    signal ps2_clk_sync : std_logic_vector(2 downto 0) := "111";
    signal ps2_dat_sync : std_logic_vector(1 downto 0) := "11";
    signal ps2_clk_fall : std_logic := '0';

    -- Open-Drain bus control signals ('1' = pull line to 0V, '0' = release to 'Z')
    signal clk_out_en   : std_logic := '0';
    signal dat_out_en   : std_logic := '0';
    signal dat_out_val  : std_logic := '1';

    -- Timers and Bit/Byte Counters
    signal timer_cnt    : integer range 0 to 2000000 := 0;
    signal bit_cnt      : integer range 0 to 15 := 0;
    signal byte_idx     : integer range 0 to 2  := 0;
    signal shift_reg    : std_logic_vector(10 downto 0) := (others => '1');

    -- Temporary storage for Byte 0 (Status/Buttons) and Byte 1 (Delta-X)
    signal pkt_byte0    : std_logic_vector(7 downto 0) := (others => '0');
    signal pkt_byte1    : std_logic_vector(7 downto 0) := (others => '0');

    -- Internal Cursor Coordinates (Starts at center of 480x480 map: 240, 240)
    signal cur_x        : integer range 0 to 479 := 240;
    signal cur_y        : integer range 0 to 479 := 240;
    signal btn_l        : std_logic := '0';
    signal btn_r        : std_logic := '0';

    -- 0xF4 Command Frame: Stop(1) & OddParity(0) & Data(0xF4 = "11110100")
    constant CMD_F4_FRAME : std_logic_vector(9 downto 0) := "1011110100";

begin

    -- Open-Drain Tri-state Output Drivers ('Z' allows external mouse to drive the bus)
    PS2_CLK <= '0' when clk_out_en = '1' else 'Z';
    PS2_DAT <= '0' when (dat_out_en = '1' and dat_out_val = '0') else 'Z';

    -- Connect internal registers to module outputs
    cursor_x    <= cur_x;
    cursor_y    <= cur_y;
    left_click  <= btn_l;
    right_click <= btn_r;

    -- 1. Synchronize PS2_CLK / PS2_DAT and detect falling edge of PS2_CLK
    process(CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            ps2_clk_sync <= ps2_clk_sync(1 downto 0) & PS2_CLK;
            ps2_dat_sync <= ps2_dat_sync(0) & PS2_DAT;
        end if;
    end process;

    ps2_clk_fall <= '1' when (ps2_clk_sync(2) = '1' and ps2_clk_sync(1) = '0') else '0';

    -- 2. Main PS/2 Communication & Cursor Update FSM
    process(CLOCK_50, reset_n)
        variable dx, dy     : integer range -256 to 255;
        variable new_x      : integer range -512 to 1023;
        variable new_y      : integer range -512 to 1023;
        variable rx_byte    : std_logic_vector(7 downto 0);
    begin
        if reset_n = '0' then
            state       <= INIT_WAIT;
            timer_cnt   <= 0;
            clk_out_en  <= '0';
            dat_out_en  <= '0';
            dat_out_val <= '1';
            bit_cnt     <= 0;
            byte_idx    <= 0;
            cur_x       <= 240;
            cur_y       <= 240;
            btn_l       <= '0';
            btn_r       <= '0';

        elsif rising_edge(CLOCK_50) then
            case state is

                -- Step 1: Wait 40ms (2,000,000 clocks) for mouse power-up
                when INIT_WAIT =>
                    clk_out_en <= '0';
                    dat_out_en <= '0';
                    if timer_cnt < 2000000 then
                        timer_cnt <= timer_cnt + 1;
                    else
                        timer_cnt <= 0;
                        state     <= TX_PULL_CLK_LOW;
                    end if;

                -- Step 2: Pull PS2_CLK low for 150us (7,500 clocks) to request host-to-mouse TX
                when TX_PULL_CLK_LOW =>
                    clk_out_en <= '1';
                    if timer_cnt < 7500 then
                        timer_cnt <= timer_cnt + 1;
                    else
                        timer_cnt <= 0;
                        state     <= TX_PULL_DAT_LOW;
                    end if;

                -- Step 3: Pull PS2_DAT low (Start Bit) and release PS2_CLK
                when TX_PULL_DAT_LOW =>
                    dat_out_en  <= '1';
                    dat_out_val <= '0';
                    if timer_cnt < 500 then
                        timer_cnt <= timer_cnt + 1;
                    else
                        clk_out_en <= '0'; -- Release clock line; mouse now generates clock
                        bit_cnt    <= 0;
                        state      <= TX_SEND_BITS;
                    end if;

                -- Step 4: Send 0xF4 command bits on each falling edge of PS2_CLK
                when TX_SEND_BITS =>
                    if ps2_clk_fall = '1' then
                        dat_out_val <= CMD_F4_FRAME(bit_cnt);
                        if bit_cnt = 9 then
                            dat_out_en <= '0'; -- Release data line after sending all bits
                            state      <= TX_WAIT_ACK;
                        else
                            bit_cnt <= bit_cnt + 1;
                        end if;
                    end if;

                -- Step 5: Wait for Mouse ACK pulse
                when TX_WAIT_ACK =>
                    if ps2_clk_fall = '1' then
                        bit_cnt <= 0;
                        state   <= RX_WAIT_ACK_BYTE;
                    end if;

                -- Step 6: Absorb the 11-bit 0xFA ACK frame sent by the mouse
                when RX_WAIT_ACK_BYTE =>
                    if ps2_clk_fall = '1' then
                        if bit_cnt = 10 then
                            bit_cnt  <= 0;
                            byte_idx <= 0;
                            state    <= RX_STREAM_PACKETS;
                        else
                            bit_cnt <= bit_cnt + 1;
                        end if;
                    end if;

                -- Step 7: Receive 3-byte movement packets continuously
                when RX_STREAM_PACKETS =>
                    if ps2_clk_fall = '1' then
                        -- Shift in new bit from PS2_DAT (LSB arrives first)
                        shift_reg <= ps2_dat_sync(1) & shift_reg(10 downto 1);

                        if bit_cnt = 10 then
                            bit_cnt <= 0;
                            rx_byte := shift_reg(9 downto 2); -- Extract 8 data bits

                            if byte_idx = 0 then
                                -- Byte 0: Bit 3 is always '1' in a valid PS/2 packet
                                if rx_byte(3) = '1' then
                                    pkt_byte0 <= rx_byte;
                                    btn_l     <= rx_byte(0); -- Left Click
                                    btn_r     <= rx_byte(1); -- Right Click
                                    byte_idx  <= 1;
                                end if;

                            elsif byte_idx = 1 then
                                -- Byte 1: X Movement Magnitude
                                pkt_byte1 <= rx_byte;
                                byte_idx  <= 2;

                            else
                                -- Byte 2: Y Movement Magnitude -> Update Cursor (X, Y)
                                byte_idx <= 0;

                                -- Combine sign bit from Byte 0 with 8-bit magnitude
                                dx := to_integer(signed(pkt_byte0(4) & pkt_byte1));
                                dy := to_integer(signed(pkt_byte0(5) & rx_byte));

                                new_x := cur_x + dx;
                                new_y := cur_y - dy; -- Mouse +Y is Up, Monitor +Y is Down

                                -- Clamp Cursor X inside 480x480 map (16..463)
                                if new_x < 16 then
                                    cur_x <= 16;
                                elsif new_x > 463 then
                                    cur_x <= 463;
                                else
                                    cur_x <= new_x;
                                end if;

                                -- Clamp Cursor Y inside 480x480 map (16..463)
                                if new_y < 16 then
                                    cur_y <= 16;
                                elsif new_y > 463 then
                                    cur_y <= 463;
                                else
                                    cur_y <= new_y;
                                end if;
                            end if;
                        else
                            bit_cnt <= bit_cnt + 1;
                        end if;
                    end if;

            end case;
        end if;
    end process;

end architecture behavioral;
