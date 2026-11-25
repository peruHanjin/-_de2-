library ieee;
use ieee.std_logic_1164.all;

-- Common 7-Segment Decoder Package (Active-Low: '0' = ON, '1' = OFF)
package seg7_pkg is
    function seg7(val : integer) return std_logic_vector;
end package seg7_pkg;

package body seg7_pkg is
    type rom_t is array (0 to 21) of std_logic_vector(6 downto 0);
    -- 0~15: Hex 0~F | 16: Blank | 17: '-' | 18: 'E' | 19: 'r' | 20: 'J' | 21: 'P'
    constant SEG_LUT : rom_t := (
        "1000000", "1111001", "0100100", "0110000", "0011001", "0010010", "0000010", "1111000",
        "0000000", "0010000", "0001000", "0000011", "1000110", "0100001", "0000110", "0001110",
        "1111111", "0111111", "0000110", "0101111", "1100001", "0001100"
    );

    function seg7(val : integer) return std_logic_vector is
    begin
        if val >= 0 and val <= 21 then return SEG_LUT(val); else return "1111111"; end if;
    end function;
end package body seg7_pkg;
