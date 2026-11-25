library ieee;
use ieee.std_logic_1164.all;

-- Common 7-Segment Decoder Package (Active-Low: '0' = ON, '1' = OFF)
package seg7_pkg is
    function seg7(val : integer) return std_logic_vector;
end package seg7_pkg;

package body seg7_pkg is
    function seg7(val : integer) return std_logic_vector is
    begin
        case val is
            when 0      => return "1000000"; -- 0
            when 1      => return "1111001"; -- 1
            when 2      => return "0100100"; -- 2
            when 3      => return "0110000"; -- 3
            when 4      => return "0011001"; -- 4
            when 5      => return "0010010"; -- 5
            when 6      => return "0000010"; -- 6
            when 7      => return "1111000"; -- 7
            when 8      => return "0000000"; -- 8
            when 9      => return "0010000"; -- 9
            when 10     => return "0001000"; -- A
            when 11     => return "0000011"; -- b
            when 12     => return "1000110"; -- C
            when 13     => return "0100001"; -- d
            when 14     => return "0000110"; -- E
            when 15     => return "0001110"; -- F
            when 16     => return "1111111"; -- Blank
            when 17     => return "0111111"; -- '-'
            when 18     => return "0000110"; -- 'E'
            when 19     => return "0101111"; -- 'r'
            when 20     => return "1100001"; -- 'J'
            when 21     => return "0001100"; -- 'P'
            when others => return "1111111"; -- Default: Blank
        end case;
    end function;
end package body seg7_pkg;
