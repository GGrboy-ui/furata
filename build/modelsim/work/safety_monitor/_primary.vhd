library verilog;
use verilog.vl_types.all;
entity safety_monitor is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        estop_n         : in     vl_logic;
        fault_n         : in     vl_logic;
        clear_fault     : in     vl_logic;
        running         : in     vl_logic;
        internal_fault  : in     vl_logic_vector(3 downto 0);
        permit          : out    vl_logic;
        latched         : out    vl_logic;
        code            : out    vl_logic_vector(3 downto 0)
    );
end safety_monitor;
