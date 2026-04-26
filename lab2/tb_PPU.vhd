library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ppu is
end entity;

architecture tb of tb_ppu is
    -- Input Signals
    signal clk          : std_logic := '0';
    signal reset_n      : std_logic := '0';
    signal switches     : std_logic_vector(9 downto 0) := (others => '0');
    signal buttons      : std_logic_vector(3 downto 0) := (others => '0');
    signal pixel_x      : std_logic_vector(9 downto 0) := (others => '0');
    signal pixel_y      : std_logic_vector(9 downto 0) := (others => '0');
    signal video_active : std_logic := '0';

    -- Output Signals
    signal r            : std_logic_vector(7 downto 0);
    signal g            : std_logic_vector(7 downto 0);
    signal b            : std_logic_vector(7 downto 0);

    -- Simulation Control
    constant CLK_PERIOD : time := 40 ns; -- 25 MHz approx
    signal sim_done     : boolean := false;

begin
    -- Instantiate the DUT (Device Under Test)
    dut: entity work.PPU
    port map(
        clk          => clk,
        reset_n      => reset_n,
        switches     => switches,
        buttons      => buttons,
        pixel_x      => pixel_x,
        pixel_y      => pixel_y,
        video_active => video_active,
        r            => r,
        g            => g,
        b            => b
    );

    -- Clock Generator
    clk_gen: process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Stimulus Process
    stim: process
    begin
        -- 1. System Reset
        reset_n <= '0';
        wait for CLK_PERIOD * 2;
        reset_n <= '1';
        wait for CLK_PERIOD * 2;

        -- 2. Test Video Inactive (Blanking period)
        -- Expected: r=00, g=00, b=00
        video_active <= '0';
        pixel_x      <= std_logic_vector(to_unsigned(10, 10));
        pixel_y      <= std_logic_vector(to_unsigned(10, 10));
        wait for CLK_PERIOD * 2;

        -- 3. Test Active Video - Sky Area (Top left)
        -- In RAM, y < 14 (map tiles) is TILE_BG (0).
        -- Expected: Sky color (r=70, g=C0, b=FF)
        video_active <= '1';
        pixel_x      <= std_logic_vector(to_unsigned(10, 10));
        pixel_y      <= std_logic_vector(to_unsigned(10, 10));
        wait for CLK_PERIOD * 2;

        -- 4. Test Active Video - Ground Area (Based on GROUND_PIXEL_Y = 400)
        -- Expected: Ground color (r=20, g=A0, b=20)
        pixel_x      <= std_logic_vector(to_unsigned(10, 10));
        pixel_y      <= std_logic_vector(to_unsigned(410, 10));
        wait for CLK_PERIOD * 2;

        -- 5. Test Tiled Grass Area (Logic in RAM: if y >= 14 in tilemap)
        -- The PPU scales 480 vertical pixels into 60 active tiles (ACTIVE_TILE_H).
        -- Y-pixel 120 should be tile_y_raw = 15.
        -- Expected: Grass tile color if pixel_on = '1' (r=20, g=A0, b=20)
        pixel_x      <= std_logic_vector(to_unsigned(10, 10));
        pixel_y      <= std_logic_vector(to_unsigned(120, 10)); 
        wait for CLK_PERIOD * 2;

        -- 6. Test a specific pixel coordinate to check tile alignment
        -- Let's check a pixel that should trigger the "Cloud" if your ROM/RAM 
        -- addresses map to a specific ID.
        pixel_x      <= std_logic_vector(to_unsigned(320, 10));
        pixel_y      <= std_logic_vector(to_unsigned(240, 10));
        wait for CLK_PERIOD * 10;

        -- End Simulation
        sim_done <= true;
        wait;
    end process;

end architecture;