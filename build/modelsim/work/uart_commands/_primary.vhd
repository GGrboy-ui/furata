library verilog;
use verilog.vl_types.all;
entity uart_commands is
    generic(
        CLK_HZ          : integer := 50000000;
        BAUD            : integer := 115200
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        rx              : in     vl_logic;
        tx              : out    vl_logic;
        start_cmd       : out    vl_logic;
        stop_cmd        : out    vl_logic;
        clear_cmd       : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of CLK_HZ : constant is 2;
    attribute mti_svvh_generic_type of BAUD : constant is 2;
end uart_commands;
