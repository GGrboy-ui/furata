library verilog;
use verilog.vl_types.all;
entity clock_reset is
    generic(
        STRETCH_CYCLES  : vl_logic_vector(15 downto 0) := (Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0)
    );
    port(
        clk             : in     vl_logic;
        arst_n          : in     vl_logic;
        locked          : in     vl_logic;
        rst_n           : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of STRETCH_CYCLES : constant is 2;
end clock_reset;
